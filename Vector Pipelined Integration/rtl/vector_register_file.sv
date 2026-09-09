// vector_register_file.sv
// Unmodified copy of "Vector Simulation/vector_register_file.sv".
// 32 x VLEN-bit registers, async read / sync write, v0 hardwired to 0.
import vector_pkg::*;

module vector_register_file (
    input  logic clk,
    input  logic rst,

    input  logic [4:0]      addr1,
    input  logic [4:0]      addr2,
    output logic [VLEN-1:0] rd1,
    output logic [VLEN-1:0] rd2,

    input  logic [4:0]      addr3,
    input  logic [VLEN-1:0] wr_data,
    input  logic            regwrite
);

    logic [VLEN-1:0] vrf [MAX_VREG-1:0];

    always_ff @(posedge clk) begin : Write
        if (rst) begin
            for (int i = 0; i < MAX_VREG; i++)
                vrf[i] <= '0;
        end
        else if (regwrite)
            vrf[addr3] <= wr_data;
    end

    always_comb begin : Read
        rd1 = (addr1 == 5'd0) ? '0 : vrf[addr1];
        rd2 = (addr2 == 5'd0) ? '0 : vrf[addr2];
    end

endmodule
