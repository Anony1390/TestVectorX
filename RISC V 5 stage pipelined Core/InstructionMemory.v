`timescale 1ns/1ps
// Word-addressed instruction memory for the 5-stage pipelined core.
// Combinational read (matches the existing single-cycle/vector-core
// imem style): instruction changes immediately with readAddr, and is
// captured into if_id_reg on the next posedge like the rest of IF.
//
// `clk` is unused by the read path itself; it's accepted only because
// the pipelined top-level (top.v / VectorPipelinedCore.sv) wires a
// .clk() port into this module. Kept here in case you want to switch
// to a synchronous single-port ROM later.
//
// `mem` is exposed with this exact name so testbenches can force
// instructions in directly via hierarchical reference, e.g.:
//   dut.m_InstMem.mem[0] = 32'h00500093;
module InstructionMemory #(
    parameter DEPTH = 256   // number of 32-bit words
)(
    input              clk,
    input      [31:0]  readAddr,
    output     [31:0]  inst
);

    reg [31:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'b0;
        // Uncomment to load a program from a hex file instead of
        // poking mem[] from a testbench:
        // $readmemh("program.hex", mem);
    end

    // word-addressed (byte address >> 2), combinational read
    assign inst = mem[readAddr[31:2]];

endmodule
