// vmux.sv  (NEW FILE)
// VLEN-wide 2:1 / 3:1 muxes, mirroring the scalar core's Mux2to1 /
// Mux3to1 style but sized for full vector registers.
import vector_pkg::*;

module VMux2to1 (
    input  logic            sel,
    input  logic [VLEN-1:0] s0,
    input  logic [VLEN-1:0] s1,
    output logic [VLEN-1:0] out
);
    assign out = sel ? s1 : s0;
endmodule

module VMux3to1 (
    input  logic [1:0]      sel,
    input  logic [VLEN-1:0] s0,
    input  logic [VLEN-1:0] s1,
    input  logic [VLEN-1:0] s2,
    output logic [VLEN-1:0] out
);
    always_comb begin
        case (sel)
            2'b00:   out = s0;
            2'b01:   out = s1;
            2'b10:   out = s2;
            default: out = s0;
        endcase
    end
endmodule
