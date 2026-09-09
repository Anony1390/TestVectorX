// VectorPipelinedCore.v  (NEW FILE)
// Top-level integration of the scalar 5-stage pipelined RISC-V core
// ("RISC V 5 stage pipelined Core/top.v", module FullyPipelinedCore)
// with a newly-pipelined vector unit (vector ID/EX/MEM/WB stages
// running alongside the scalar ones, sharing IF/ID and PC).
//
// The scalar section below is functionally identical to the existing
// FullyPipelinedCore — same modules, same wiring — with two additions
// needed to support the vector unit:
//   1. `v_pipe_stall` is ANDed into the scalar hazard unit's wr_pc /
//      wr_if_id outputs, and passed as `stall` into the (modified)
//      id_ex_reg.v / ex_mem_reg.v, so the whole scalar pipeline
//      freezes while a vector load/store is mid-flight.
//   2. The vector datapath is decoded in parallel in ID, and flows
//      through its own v_id_ex_reg / v_ex_mem_reg / v_mem_wb_reg
//      pipeline registers into vector EX (VALU), vector MEM
//      (vector_lsu + vector_data_mem) and vector WB
//      (vector_register_file write port).
//
// See docs/INTEGRATION_NOTES.md for the encoding, the simplifications
// made (no vector forwarding out of an in-flight LSU op, separate
// vector data memory, no vector exceptions), and ideas for follow-up
// work (true dual-issue, shared/arbitrated memory, WAW hazard checks
// between scalar and vector register files if they're ever unified).

import vector_pkg::*;
import vector_isa_pkg::*;

module VectorPipelinedCore (
    input clk,
    input start,
    output wire dummy_out
);

// ===================== Scalar core (unchanged wiring) =====================
wire [31:0] pcout, if_pcplus4, if_instruction;

wire [31:0] id_pc, id_pcplus4, id_immval, id_immx2;
wire [31:0] id_rs1content, id_rs2content;
wire [31:0] pcjumploc, pcbasednextpc;
wire id_branch, id_memRead, id_memtoReg, id_memWrite;
wire id_ALUSrc, id_regWrite, id_jal, id_jalr;
wire [3:0] id_ALUCtl;
wire [1:0] bc;
wire eq, lt, eqorlt;
wire taken;

wire [31:0] ex_pc, ex_pcplus4, ex_rdata1, ex_rdata2;
wire [31:0] ex_immval, ex_ALUOut;
wire [31:0] aluip1, aluip2, ex_aluip2, ex_storedata;
wire [4:0] ex_rd, ex_rs1, ex_rs2;
wire ex_regWrite, ex_memtoReg, ex_memWrite, ex_memRead;
wire ex_branch, ex_ALUSrc, ex_jal, ex_jalr;
wire [3:0] ex_ALUCtl;
wire [1:0] ALUSrc1, ALUSrc2;

wire [31:0] mem_ALUout, mem_rdata2, mem_pcplus4;
wire [31:0] mem_readData;
wire [4:0] mem_rd, mem_rs2;
wire mem_regWrite, mem_memtoReg, mem_memWrite, mem_memRead;
wire mem_jal, mem_jalr;

wire [31:0] wb_ALUout, wb_readData, wb_pcplus4;
wire [31:0] regcontent, rdcontent;
wire [4:0] wb_rd;
wire wb_regWrite, wb_memtoReg, wb_jal, wb_jalr;

wire [31:0] nextpc;
wire wr_pc_hz, wr_if_id_hz, flush_if_id, flush_id_ex;
wire wr_pc, wr_if_id;

// ---- NEW: global vector-induced pipeline stall ----
wire v_pipe_stall;

PC m_PC(
    .clk(clk),
    .rst(start),
    .wr_pc(wr_pc),
    .pc_i(nextpc),
    .pc_o(pcout)
);

Adder m_Adder_1(
    .a(pcout),
    .b(32'd4),
    .sum(if_pcplus4)
);

wire [31:0] id_inst;
InstructionMemory m_InstMem(
    .readAddr(pcout),
    .inst(if_instruction),
    .clk(clk)
);

if_id_reg m_if_id_reg(
    .rst(start),
    .clk(clk),
    .pc_i(pcout),
    .inst_i(if_instruction),
    .pc_o(id_pc),
    .inst_o(id_inst),
    .flush_if_id(flush_if_id),
    .wr_if_id(wr_if_id),
    .pcplus4_i(if_pcplus4),
    .pcplus4_o(id_pcplus4)
);

Control m_Control(
    .opcode(id_inst[6:0]),
    .branch(id_branch),
    .memRead(id_memRead),
    .memtoReg(id_memtoReg),
    .memWrite(id_memWrite),
    .ALUSrc(id_ALUSrc),
    .regWrite(id_regWrite),
    .jal(id_jal),
    .jalr(id_jalr),
    .funct7(id_inst[31:25]),
    .funct3(id_inst[14:12]),
    .ALUCtl(id_ALUCtl),
	.branchcontrol(bc)
);

wire [31:0] reg_readData1, reg_readData2;
Register m_Register(
    .clk(clk),
    .rst(start),
    .regWrite(wb_regWrite),
    .readReg1(id_inst[19:15]),
    .readReg2(id_inst[24:20]),
    .writeReg(wb_rd),
    .writeData(rdcontent),
    .readData1(reg_readData1),
    .readData2(reg_readData2)
);
assign id_rs1content = (wb_regWrite && wb_rd == id_inst[19:15] && wb_rd != 0)
                       ? rdcontent : reg_readData1;
assign id_rs2content = (wb_regWrite && wb_rd == id_inst[24:20] && wb_rd != 0)
                       ? rdcontent : reg_readData2;

ImmGen #(.Width(32)) m_ImmGen(
    .inst(id_inst),
    .imm(id_immval)
);

ShiftLeftOne m_ShiftLeftOne(
    .i(id_immval),
    .o(id_immx2)
);

Adder m_Adder_2(
    .a(id_pc),
    .b(id_immx2),
    .sum(pcjumploc)
);

wire [1:0] cmpSrc1, cmpSrc2;
wire [31:0] cmpA, cmpB;

forwardingUnit m_fwd_unit_cmp(
    .rs1(id_inst[19:15]),
    .rs2(id_inst[24:20]),
    .ex_mem_rd(mem_rd),
    .ex_mem_regwrite(mem_regWrite),
    .mem_wb_rd(wb_rd),
    .mem_wb_regwrite(wb_regWrite),
    .Src1(cmpSrc1),
    .Src2(cmpSrc2)
);

Mux3to1 #(.size(32)) m_Mux_CmpSrc1(
    .sel(cmpSrc1),
    .s0(id_rs1content),
    .s1(rdcontent),
    .s2(mem_ALUout),
    .out(cmpA)
);

Mux3to1 #(.size(32)) m_Mux_CmpSrc2(
    .sel(cmpSrc2),
    .s0(id_rs2content),
    .s1(rdcontent),
    .s2(mem_ALUout),
    .out(cmpB)
);

comparator m_cmp(
    .A(cmpA),
    .B(cmpB),
    .eq(eq),
    .lt(lt)
);

assign eqorlt = bc[1]?lt:eq;
assign taken = id_branch & (bc[0]^eqorlt);

Mux2to1 #(.size(32)) m_Mux_PC1(
    .sel(taken | id_jal),
    .s0(if_pcplus4),
    .s1(pcjumploc),
    .out(pcbasednextpc)
);

hazardDetectionUnit m_hz_unit(
    .id_ex_rd(ex_rd),
    .ex_mem_rd(mem_rd),
    .if_id_inst(id_inst),
    .id_ex_memRead(ex_memRead),
    .ex_mem_memRead(mem_memRead),
    .branch(id_branch),
    .taken(taken),
    .jal(id_jal),
    .jalr(id_jalr),
    .flush_if_id(flush_if_id),
    .flush_id_ex(flush_id_ex),
    .wr_pc(wr_pc_hz),
    .wr_if_id(wr_if_id_hz)
);

// ---- NEW: fold the vector structural stall into PC / IF-ID enables ----
assign wr_pc    = wr_pc_hz    & ~v_pipe_stall;
assign wr_if_id = wr_if_id_hz & ~v_pipe_stall;

id_ex_reg m_id_ex_reg (
    .clk               (clk),
    .rst               (start),
    .stall             (v_pipe_stall),     // NEW
    .regWrite_i        (id_regWrite),
    .memtoReg_i        (id_memtoReg),
    .memWrite_i        (id_memWrite),
    .memRead_i         (id_memRead),
    .ALUSrc_i          (id_ALUSrc),
    .ALUCtl_i          (id_ALUCtl),
    .pc_i              (id_pc),
    .rdata1_i          (id_rs1content),
    .rdata2_i          (id_rs2content),
    .imm_i             (id_immval),
    .rd_i              (id_inst[11:7]),
    .rs1_i             (id_inst[19:15]),
    .rs2_i             (id_inst[24:20]),
    .regWrite_o        (ex_regWrite),
    .memtoReg_o        (ex_memtoReg),
    .memWrite_o        (ex_memWrite),
    .memRead_o         (ex_memRead),
    .ALUSrc_o          (ex_ALUSrc),
    .ALUCtl_o          (ex_ALUCtl),
    .pc_o              (ex_pc),
    .rdata1_o          (ex_rdata1),
    .rdata2_o          (ex_rdata2),
    .imm_o             (ex_immval),
    .rd_o              (ex_rd),
    .rs1_o             (ex_rs1),
    .rs2_o             (ex_rs2),
    .flush_id_ex       (flush_id_ex),
    .jal_i(id_jal),
    .jalr_i(id_jalr),
    .jalr_o(ex_jalr),
    .jal_o(ex_jal),
    .pcplus4_i(id_pcplus4),
    .pcplus4_o(ex_pcplus4)
);

Mux2to1 #(.size(32)) m_Mux_PC(
    .sel(ex_jalr),
    .s0(pcbasednextpc),
    .s1(ex_ALUOut),
    .out(nextpc)
);

forwardingUnit m_fwd_unit_alu(
    .rs1(ex_rs1),
    .rs2(ex_rs2),
    .ex_mem_rd(mem_rd),
    .ex_mem_regwrite(mem_regWrite),
    .mem_wb_rd(wb_rd),
    .mem_wb_regwrite(wb_regWrite),
    .Src1(ALUSrc1),
    .Src2(ALUSrc2)
);

Mux3to1 #(.size(32)) m_Mux_ALUSrc1(
    .sel(ALUSrc1),
    .s0(ex_rdata1),
    .s1(rdcontent),
    .s2(mem_ALUout),
    .out(aluip1)
);

wire [31:0] ex_aluip2_forwarded;
Mux3to1 #(.size(32)) m_Mux_ALUSrc2(
    .sel(ALUSrc2),
    .s0(ex_rdata2),
    .s1(rdcontent),
    .s2(mem_ALUout),
    .out(ex_aluip2_forwarded)
);

Mux2to1 #(.size(32)) m_Mux_ALU(
    .sel(ex_ALUSrc),
    .s0(ex_aluip2_forwarded),
    .s1(ex_immval),
    .out(ex_aluip2)
);

ALU m_ALU(
    .ALUCtl(ex_ALUCtl),
    .A(aluip1),
    .B(ex_aluip2),
    .ALUOut(ex_ALUOut)
);

ex_mem_reg m_ex_mem_reg (
    .clk               (clk),
    .rst               (start),
    .stall             (v_pipe_stall),     // NEW
    .regWrite_i        (ex_regWrite),
    .memtoReg_i        (ex_memtoReg),
    .memWrite_i        (ex_memWrite),
    .memRead_i         (ex_memRead),
    .ALUResult_i       (ex_ALUOut),
    .rdata2_i          (ex_rdata2),
    .rd_i              (ex_rd),
    .rs2_i(ex_rs2),
    .rs2_o(mem_rs2),
    .regWrite_o        (mem_regWrite),
    .memtoReg_o        (mem_memtoReg),
    .memWrite_o        (mem_memWrite),
    .memRead_o         (mem_memRead),
    .ALUResult_o       (mem_ALUout),
    .rdata2_o          (mem_rdata2),
    .rd_o              (mem_rd),
    .jal_i(ex_jal),
    .jalr_i(ex_jalr),
    .jal_o(mem_jal),
    .jalr_o(mem_jalr),
    .pcplus4_i(ex_pcplus4),
    .pcplus4_o(mem_pcplus4)
);

wire [31:0] mem_writedata;
assign mem_writedata = (wb_regWrite && wb_rd != 0 && wb_rd == mem_rs2)
                       ? rdcontent : mem_rdata2;

DataMemory m_DataMemory(
    .rst(start),
    .clk(clk),
    .memWrite(mem_memWrite),
    .memRead(mem_memRead),
    .address(mem_ALUout),
    .writeData(mem_writedata),
    .readData(mem_readData)
);

mem_wb_reg m_mem_wb_reg (
    .clk            (clk),
    .rst            (start),
    .regWrite_i     (mem_regWrite),
    .memtoReg_i     (mem_memtoReg),
    .ALUOut_i       (mem_ALUout),
    .readData_i     (mem_readData),
    .rd_i           (mem_rd),
    .regWrite_o     (wb_regWrite),
    .memtoReg_o     (wb_memtoReg),
    .ALUResult_o    (wb_ALUout),
    .readData_o     (wb_readData),
    .rd_o           (wb_rd),
    .jal_i(mem_jal),
    .jalr_i(mem_jalr),
    .jal_o(wb_jal),
    .jalr_o(wb_jalr),
    .pcplus4_i(mem_pcplus4),
    .pcplus4_o(wb_pcplus4)
);

Mux2to1 #(.size(32)) m_Mux_WriteData(
    .sel(wb_memtoReg),
    .s0(wb_ALUout),
    .s1(wb_readData),
    .out(regcontent)
);

Mux2to1 #(.size(32)) m_Mux_RegContent(
    .sel(wb_jal | wb_jalr),
    .s0(regcontent),
    .s1(wb_pcplus4),
    .out(rdcontent)
);

assign dummy_out = pcout;

// ============================ Vector unit ============================
// ---- ID stage: decode + vector regfile read + config CSR write ----
wire              v_is_vector, v_is_vcfg;
wire              v_regwrite_id;
vector_opcode_t   v_vop_id;
wire [4:0]        v_vrd_id, v_vrs1_id, v_vrs2_id;
vector_mem_mode_t v_mode_id;
wire [31:0]       v_imm_id;
wire              v_lsu_en_id, v_memtoreg_id, v_mem_read_id, v_mem_write_id;
wire              v_cfg_write_id, v_cfg_sel_sew_id;
wire [31:0]       v_cfg_data_id;

vector_decoder m_v_decoder (
    .instruction (id_inst),
    .is_vector   (v_is_vector),
    .is_vcfg     (v_is_vcfg),
    .regwrite    (v_regwrite_id),
    .vop         (v_vop_id),
    .vrd         (v_vrd_id),
    .vrs1        (v_vrs1_id),
    .vrs2        (v_vrs2_id),
    .mode        (v_mode_id),
    .imm_ext     (v_imm_id),
    .lsu_en      (v_lsu_en_id),
    .memtoreg    (v_memtoreg_id),
    .mem_read    (v_mem_read_id),
    .mem_write   (v_mem_write_id),
    .cfg_write   (v_cfg_write_id),
    .cfg_sel_sew (v_cfg_sel_sew_id),
    .cfg_data    (v_cfg_data_id)
);

wire [31:0] v_vl, v_sew, v_epv;
wire [LANES-1:0] v_lane_active;
vector_config m_v_config (
    .clk         (clk),
    .rst         (~start),
    .cfg_write   (v_cfg_write_id),
    .cfg_data    (v_cfg_data_id),
    .cfg_sel_vl  (~v_cfg_sel_sew_id),
    .cfg_sel_sew (v_cfg_sel_sew_id),
    .vl          (v_vl),
    .sew         (v_sew),
    .epv         (v_epv),
    .lane_active (v_lane_active)
);

wire [VLEN-1:0] v_rd1_id, v_rd2_id;
wire [4:0] v_wb_vrd;
wire v_wb_regwrite;
wire [VLEN-1:0] v_wb_write_data;

vector_register_file m_v_regfile (
    .clk      (clk),
    .rst      (~start),
    .addr1    (v_vrs1_id),
    .addr2    (v_vrs2_id),
    .rd1      (v_rd1_id),
    .rd2      (v_rd2_id),
    .addr3    (v_wb_vrd),
    .wr_data  (v_wb_write_data),
    .regwrite (v_wb_regwrite)
);

// ---- ID/EX ----
wire v_ex_valid, v_ex_regwrite, v_ex_lsu_en, v_ex_memtoreg;
wire v_ex_mem_read, v_ex_mem_write;
vector_opcode_t v_ex_vop;
vector_mem_mode_t v_ex_mode;
wire [4:0] v_ex_vrd, v_ex_vrs1, v_ex_vrs2;
wire [VLEN-1:0] v_ex_vs1_data, v_ex_vs2_data;
wire [31:0] v_ex_imm, v_ex_vl;

v_id_ex_reg m_v_id_ex_reg (
    .clk (clk), .rst(~start), .stall(v_pipe_stall), .flush(1'b0),
    .valid_i     (v_is_vector),
    .regwrite_i  (v_regwrite_id),
    .lsu_en_i    (v_lsu_en_id),
    .memtoreg_i  (v_memtoreg_id),
    .mem_read_i  (v_mem_read_id),
    .mem_write_i (v_mem_write_id),
    .vop_i       (v_vop_id),
    .mode_i      (v_mode_id),
    .vrd_i       (v_vrd_id),
    .vrs1_i      (v_vrs1_id),
    .vrs2_i      (v_vrs2_id),
    .vs1_data_i  (v_rd1_id),
    .vs2_data_i  (v_rd2_id),
    .imm_i       (v_imm_id),
    .vl_i        (v_vl),
    .valid_o     (v_ex_valid),
    .regwrite_o  (v_ex_regwrite),
    .lsu_en_o    (v_ex_lsu_en),
    .memtoreg_o  (v_ex_memtoreg),
    .mem_read_o  (v_ex_mem_read),
    .mem_write_o (v_ex_mem_write),
    .vop_o       (v_ex_vop),
    .mode_o      (v_ex_mode),
    .vrd_o       (v_ex_vrd),
    .vrs1_o      (v_ex_vrs1),
    .vrs2_o      (v_ex_vrs2),
    .vs1_data_o  (v_ex_vs1_data),
    .vs2_data_o  (v_ex_vs2_data),
    .imm_o       (v_ex_imm),
    .vl_o        (v_ex_vl)
);

// ---- EX: forward + VALU ----
wire [4:0] v_mem_vrd_pipe, v_wb_vrd_pipe;
wire v_mem_regwrite_pipe, v_mem_lsu_en_pipe, v_wb_regwrite_pipe;
wire [VLEN-1:0] v_mem_vd_alu_pipe;

wire [1:0] v_fwd_src1, v_fwd_src2;
vector_forwarding_unit m_v_fwd (
    .vrs1            (v_ex_vrs1),
    .vrs2            (v_ex_vrs2),
    .ex_mem_vrd      (v_mem_vrd_pipe),
    .ex_mem_regwrite (v_mem_regwrite_pipe),
    .ex_mem_lsu_en   (v_mem_lsu_en_pipe),
    .mem_wb_vrd      (v_wb_vrd_pipe),
    .mem_wb_regwrite (v_wb_regwrite_pipe),
    .Src1 (v_fwd_src1),
    .Src2 (v_fwd_src2)
);

wire [VLEN-1:0] v_ex_vs1_fwd, v_ex_vs2_fwd;
VMux3to1 m_v_fwd_mux1 (.sel(v_fwd_src1), .s0(v_ex_vs1_data), .s1(v_wb_write_data), .s2(v_mem_vd_alu_pipe), .out(v_ex_vs1_fwd));
VMux3to1 m_v_fwd_mux2 (.sel(v_fwd_src2), .s0(v_ex_vs2_data), .s1(v_wb_write_data), .s2(v_mem_vd_alu_pipe), .out(v_ex_vs2_fwd));

wire [VLEN-1:0] v_vd_alu;
VALU m_VALU (
    .op  (v_ex_vop),
    .vs1 (v_ex_vs1_fwd),
    .vs2 (v_ex_vs2_fwd),
    .vl  (v_ex_vl[$clog2(LANES+1)-1:0]),
    .vd  (v_vd_alu)
);

wire [31:0] v_ex_stride;
assign v_ex_stride = (v_ex_mode == STRIDE) ? v_ex_imm : 32'd0;

// ---- EX/MEM ----
wire v_mem_valid_pipe, v_mem_memtoreg_pipe, v_mem_read_pipe, v_mem_write_pipe;
vector_mem_mode_t v_mem_mode_pipe;
wire [31:0] v_mem_base_addr_pipe, v_mem_stride_pipe, v_mem_vl_pipe;
wire [VLEN-1:0] v_mem_store_data_pipe, v_mem_index_pipe;

v_ex_mem_reg m_v_ex_mem_reg (
    .clk(clk), .rst(~start), .stall(v_pipe_stall), .flush(1'b0),
    .valid_i        (v_ex_valid),
    .regwrite_i     (v_ex_regwrite),
    .lsu_en_i       (v_ex_lsu_en),
    .memtoreg_i     (v_ex_memtoreg),
    .mem_read_i     (v_ex_mem_read),
    .mem_write_i    (v_ex_mem_write),
    .mode_i         (v_ex_mode),
    .vrd_i          (v_ex_vrd),
    .vd_alu_i       (v_vd_alu),
    .base_addr_i    (v_ex_vs1_fwd[31:0]),
    .stride_i       (v_ex_stride),
    .store_data_i   (v_ex_vs2_fwd),
    .index_vector_i (v_ex_vs2_fwd),
    .vl_i           (v_ex_vl),
    .valid_o        (v_mem_valid_pipe),
    .regwrite_o     (v_mem_regwrite_pipe),
    .lsu_en_o       (v_mem_lsu_en_pipe),
    .memtoreg_o     (v_mem_memtoreg_pipe),
    .mem_read_o     (v_mem_read_pipe),
    .mem_write_o    (v_mem_write_pipe),
    .mode_o         (v_mem_mode_pipe),
    .vrd_o          (v_mem_vrd_pipe),
    .vd_alu_o       (v_mem_vd_alu_pipe),
    .base_addr_o    (v_mem_base_addr_pipe),
    .stride_o       (v_mem_stride_pipe),
    .store_data_o   (v_mem_store_data_pipe),
    .index_vector_o (v_mem_index_pipe),
    .vl_o           (v_mem_vl_pipe)
);

// ---- MEM: vector_lsu + private vector data memory ----
wire [31:0] v_mem_addr;
wire v_mem_req, v_mem_read_sig, v_mem_write_sig;
wire [ELEN-1:0] v_mem_wdata;
wire v_mem_data_valid;
wire [ELEN-1:0] v_mem_rdata;
wire [VLEN-1:0] v_load_data;
wire v_lsu_done, v_lsu_busy;

vector_opcode_t v_mem_lsu_op;
assign v_mem_lsu_op = v_mem_read_pipe ? VLOAD : (v_mem_write_pipe ? VSTORE : VADD);

vector_lsu m_v_lsu (
    .clk          (clk),
    .rst          (~start),
    .mode         (v_mem_mode_pipe),
    .op           (v_mem_lsu_op),
    .vl           (v_mem_vl_pipe[15:0]),
    .base_addr    (v_mem_base_addr_pipe),
    .stride       (v_mem_stride_pipe),
    .index_vector (v_mem_index_pipe),
    .store_data   (v_mem_store_data_pipe),
    .load_data    (v_load_data),
    .mem_addr     (v_mem_addr),
    .mem_req      (v_mem_req),
    .mem_read     (v_mem_read_sig),
    .mem_write    (v_mem_write_sig),
    .mem_wdata    (v_mem_wdata),
    .mem_valid    (v_mem_data_valid),
    .mem_rdata    (v_mem_rdata),
    .done         (v_lsu_done),
    .busy         (v_lsu_busy)
);

vector_data_mem #(.WORDS(1024)) m_v_data_mem (
    .clk       (clk),
    .rst       (~start),
    .mem_addr  (v_mem_addr),
    .mem_req   (v_mem_req && v_mem_lsu_en_pipe),
    .mem_read  (v_mem_read_sig),
    .mem_write (v_mem_write_sig),
    .mem_wdata (v_mem_wdata),
    .mem_valid (v_mem_data_valid),
    .mem_rdata (v_mem_rdata)
);

vector_hazard_unit m_v_hazard (
    .v_lsu_busy   (v_lsu_busy && v_mem_lsu_en_pipe),
    .v_pipe_stall (v_pipe_stall)
);

wire [VLEN-1:0] v_mem_writeback_data;
VMux2to1 m_v_wb_mux (
    .sel (v_mem_memtoreg_pipe),
    .s0  (v_mem_vd_alu_pipe),
    .s1  (v_load_data),
    .out (v_mem_writeback_data)
);

// ---- MEM/WB ----
v_mem_wb_reg m_v_mem_wb_reg (
    .clk          (clk),
    .rst          (~start),
    .regwrite_i   (v_mem_regwrite_pipe),
    .lsu_en_i     (v_mem_lsu_en_pipe),
    .lsu_done_i   (v_lsu_done),
    .vrd_i        (v_mem_vrd_pipe),
    .write_data_i (v_mem_writeback_data),
    .regwrite_o   (v_wb_regwrite_pipe),
    .vrd_o        (v_wb_vrd_pipe),
    .write_data_o (v_wb_write_data)
);

assign v_wb_regwrite = v_wb_regwrite_pipe;
assign v_wb_vrd       = v_wb_vrd_pipe;

endmodule
