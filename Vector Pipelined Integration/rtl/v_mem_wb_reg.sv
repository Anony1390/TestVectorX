// v_mem_wb_reg.sv  (NEW FILE)
// Vector MEM/WB pipeline register. Updates EVERY cycle (never stalled)
// -- while the LSU is mid-burst, `commit` below is forced low so this
// stage simply latches "no write" each cycle, and on the exact cycle
// the LSU (or single-cycle ALU op) finishes, the real result and a
// qualified regwrite are captured for the WB mux/vector regfile.
import vector_pkg::*;

module v_mem_wb_reg (
    input logic clk,
    input logic rst,

    input logic            regwrite_i,
    input logic            lsu_en_i,
    input logic            lsu_done_i,      // from vector_lsu.done
    input logic [4:0]      vrd_i,
    input logic [VLEN-1:0] write_data_i,    // muxed ALU-result / load-data

    output logic            regwrite_o,
    output logic [4:0]      vrd_o,
    output logic [VLEN-1:0] write_data_o
);

    // Non-LSU (ALU) ops commit every cycle they're present (1-cycle EX).
    // LSU ops only commit once vector_lsu asserts done.
    wire commit = regwrite_i && (~lsu_en_i || lsu_done_i);

    always_ff @(posedge clk) begin
        if (rst) begin
            regwrite_o   <= 1'b0;
            vrd_o        <= 5'd0;
            write_data_o <= '0;
        end
        else begin
            regwrite_o   <= commit;
            vrd_o        <= vrd_i;
            write_data_o <= write_data_i;
        end
    end

endmodule
