// v_id_ex_reg.sv  (NEW FILE)
// Vector ID/EX pipeline register. Runs alongside the scalar id_ex_reg,
// gated by the SAME global pipeline `stall` (asserted while the
// vector LSU is mid-flight) and the SAME `flush` (branch/jump
// misprediction squash) signals used by the scalar pipeline, so
// vector and scalar instructions stay correctly interleaved.
import vector_pkg::*;

module v_id_ex_reg (
    input logic clk,
    input logic rst,
    input logic stall,
    input logic flush,

    input logic             valid_i,
    input logic             regwrite_i,
    input logic             lsu_en_i,
    input logic             memtoreg_i,
    input logic             mem_read_i,
    input logic             mem_write_i,
    input vector_opcode_t   vop_i,
    input vector_mem_mode_t mode_i,
    input logic [4:0]       vrd_i,
    input logic [4:0]       vrs1_i,
    input logic [4:0]       vrs2_i,
    input logic [VLEN-1:0]  vs1_data_i,
    input logic [VLEN-1:0]  vs2_data_i,
    input logic [31:0]      imm_i,
    input logic [31:0]      vl_i,

    output logic             valid_o,
    output logic             regwrite_o,
    output logic             lsu_en_o,
    output logic             memtoreg_o,
    output logic             mem_read_o,
    output logic             mem_write_o,
    output vector_opcode_t   vop_o,
    output vector_mem_mode_t mode_o,
    output logic [4:0]       vrd_o,
    output logic [4:0]       vrs1_o,
    output logic [4:0]       vrs2_o,
    output logic [VLEN-1:0]  vs1_data_o,
    output logic [VLEN-1:0]  vs2_data_o,
    output logic [31:0]      imm_o,
    output logic [31:0]      vl_o
);

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_o     <= 1'b0;
            regwrite_o  <= 1'b0;
            lsu_en_o    <= 1'b0;
            memtoreg_o  <= 1'b0;
            mem_read_o  <= 1'b0;
            mem_write_o <= 1'b0;
            vop_o       <= VADD;
            mode_o      <= UNIT_STRIDE;
            vrd_o       <= 5'd0;
            vrs1_o      <= 5'd0;
            vrs2_o      <= 5'd0;
            vs1_data_o  <= '0;
            vs2_data_o  <= '0;
            imm_o       <= 32'd0;
            vl_o        <= 32'd0;
        end
        else if (!stall) begin
            valid_o     <= valid_i;
            regwrite_o  <= regwrite_i;
            lsu_en_o    <= lsu_en_i;
            memtoreg_o  <= memtoreg_i;
            mem_read_o  <= mem_read_i;
            mem_write_o <= mem_write_i;
            vop_o       <= vop_i;
            mode_o      <= mode_i;
            vrd_o       <= vrd_i;
            vrs1_o      <= vrs1_i;
            vrs2_o      <= vrs2_i;
            vs1_data_o  <= vs1_data_i;
            vs2_data_o  <= vs2_data_i;
            imm_o       <= imm_i;
            vl_o        <= vl_i;
        end
        // else: hold current values (stall)
    end

endmodule
