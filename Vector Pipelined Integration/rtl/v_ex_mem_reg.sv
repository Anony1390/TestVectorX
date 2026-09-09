// v_ex_mem_reg.sv  (NEW FILE)
// Vector EX/MEM pipeline register. Carries the (already-computed,
// single-cycle) VALU result for ALU ops, and the address/stride/
// store-data for LSU ops, into the vector MEM stage where vector_lsu
// actually runs (multi-cycle for LSU ops).
import vector_pkg::*;

module v_ex_mem_reg (
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
    input vector_mem_mode_t mode_i,
    input logic [4:0]       vrd_i,
    input logic [VLEN-1:0]  vd_alu_i,
    input logic [31:0]      base_addr_i,
    input logic [31:0]      stride_i,
    input logic [VLEN-1:0]  store_data_i,
    input logic [VLEN-1:0]  index_vector_i,
    input logic [31:0]      vl_i,

    output logic             valid_o,
    output logic             regwrite_o,
    output logic             lsu_en_o,
    output logic             memtoreg_o,
    output logic             mem_read_o,
    output logic             mem_write_o,
    output vector_mem_mode_t mode_o,
    output logic [4:0]       vrd_o,
    output logic [VLEN-1:0]  vd_alu_o,
    output logic [31:0]      base_addr_o,
    output logic [31:0]      stride_o,
    output logic [VLEN-1:0]  store_data_o,
    output logic [VLEN-1:0]  index_vector_o,
    output logic [31:0]      vl_o
);

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_o        <= 1'b0;
            regwrite_o     <= 1'b0;
            lsu_en_o       <= 1'b0;
            memtoreg_o     <= 1'b0;
            mem_read_o     <= 1'b0;
            mem_write_o    <= 1'b0;
            mode_o         <= UNIT_STRIDE;
            vrd_o          <= 5'd0;
            vd_alu_o       <= '0;
            base_addr_o    <= 32'd0;
            stride_o       <= 32'd0;
            store_data_o   <= '0;
            index_vector_o <= '0;
            vl_o           <= 32'd0;
        end
        else if (!stall) begin
            valid_o        <= valid_i;
            regwrite_o     <= regwrite_i;
            lsu_en_o       <= lsu_en_i;
            memtoreg_o     <= memtoreg_i;
            mem_read_o     <= mem_read_i;
            mem_write_o    <= mem_write_i;
            mode_o         <= mode_i;
            vrd_o          <= vrd_i;
            vd_alu_o       <= vd_alu_i;
            base_addr_o    <= base_addr_i;
            stride_o       <= stride_i;
            store_data_o   <= store_data_i;
            index_vector_o <= index_vector_i;
            vl_o           <= vl_i;
        end
        // else: hold (stall) -- crucial while vector_lsu is mid-burst,
        // so its control/address inputs stay stable across the whole
        // multi-cycle access.
    end

endmodule
