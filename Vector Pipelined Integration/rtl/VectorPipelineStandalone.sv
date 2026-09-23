// VectorPipelineStandalone.sv  (NEW FILE)
// Wraps JUST the vector pipeline (ID -> EX -> MEM -> WB) with its own
// tiny fetch counter and instruction memory -- no scalar core, no
// shared PC/IF-ID with FullyPipelinedCore. This is the module to use
// for the MIDSEM milestone: it proves the vector pipeline itself is
// correctly pipelined (forwarding, multi-cycle LSU stall/resume,
// vl/sew config) in complete isolation from the scalar-core
// integration work, which is a separate (ENDSEM) milestone built on
// top of this same set of vector modules -- see
// VectorPipelinedCore.sv for that.
//
// Internally this is the exact same vector datapath instantiated in
// VectorPipelinedCore.sv (same module names, same wiring), just fed
// by a private 1-instruction-per-cycle fetch counter instead of the
// scalar core's shared PC. That keeps the two milestones' RTL
// genuinely identical where it matters (you are not building/
// verifying a second copy of the vector pipeline -- you're verifying
// the SAME one, standalone here and integrated in the other module).
import vector_pkg::*;
import vector_isa_pkg::*;

module VectorPipelineStandalone #(
    parameter int IMEM_WORDS = 64
) (
    input  logic clk,
    input  logic rst,             // active-high
    output logic v_pipe_stall_o   // exposed for the testbench/waveform
);

    // ---- private fetch counter + instruction memory ----
    logic [31:0] v_pc;
    logic [31:0] v_imem [0:IMEM_WORDS-1];
    logic [31:0] v_instruction;
    logic [31:0] id_inst;         // 1-cycle "IF/ID" register

    initial begin
        for (int i = 0; i < IMEM_WORDS; i++) v_imem[i] = 32'd0;
    end

    assign v_instruction = v_imem[v_pc[$clog2(IMEM_WORDS)-1:0]];

    logic v_pipe_stall;
    assign v_pipe_stall_o = v_pipe_stall;

    always_ff @(posedge clk) begin
        if (rst) v_pc <= 32'd0;
        else if (!v_pipe_stall) v_pc <= v_pc + 32'd1;
    end

    always_ff @(posedge clk) begin
        if (rst) id_inst <= 32'd0;
        else if (!v_pipe_stall) id_inst <= v_instruction;
    end

    // ================= everything below is identical to the =================
    // ================= vector section of VectorPipelinedCore.sv =============

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
        .rst         (rst),
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
        .rst      (rst),
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
        .clk (clk), .rst(rst), .stall(v_pipe_stall), .flush(1'b0),
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
        .clk(clk), .rst(rst), .stall(v_pipe_stall), .flush(1'b0),
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

    // NOTE: written as an always_comb with one enum literal per branch
    // rather than a nested ternary continuous assignment -- Icarus
    // Verilog requires an explicit cast when a ternary mixes enum
    // literals inside a continuous `assign`; a plain if/else avoids
    // that entirely and is at least as readable.
    vector_opcode_t v_mem_lsu_op;
    always_comb begin
        if (v_mem_read_pipe)       v_mem_lsu_op = VLOAD;
        else if (v_mem_write_pipe) v_mem_lsu_op = VSTORE;
        else                       v_mem_lsu_op = VADD;
    end

    // One-shot issue pulse for the LSU FSM (see vector_lsu.sv header
    // for why this can't just be derived from level-held op bits).
    // Fires exactly once, the cycle a new LSU instruction's fields
    // have just landed in v_ex_mem_reg (i.e. the pipe was NOT
    // stalled the cycle before).
    logic v_prev_stall;
    always_ff @(posedge clk) begin
        if (rst) v_prev_stall <= 1'b0;
        else     v_prev_stall <= v_pipe_stall;
    end
    wire v_lsu_issue = v_mem_lsu_en_pipe && !v_prev_stall;

    vector_lsu m_v_lsu (
        .clk          (clk),
        .rst          (rst),
        .mode         (v_mem_mode_pipe),
        .op           (v_mem_lsu_op),
        .issue        (v_lsu_issue),
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
        .rst       (rst),
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
        .rst          (rst),
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
