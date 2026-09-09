// vector_data_mem.sv
// NEW FILE. A standalone word-addressed data memory for the vector
// LSU, modeled the same zero-extra-latency way the existing
// "Vector Simulation/vector_tb.sv" testbench models memory (mem_valid
// follows mem_req combinationally, read data appears the same cycle,
// writes latch on the clock edge). Kept separate from the scalar
// core's byte-addressed DataMemory.v to avoid needing a dual-port
// arbiter for this phase of the project; see INTEGRATION_NOTES.md
// for how to later merge/arbitrate a single shared memory.
import vector_pkg::*;

module vector_data_mem #(
    parameter int WORDS = 1024
) (
    input  logic clk,
    input  logic rst,

    input  logic [31:0]     mem_addr,
    input  logic             mem_req,
    input  logic             mem_read,
    input  logic             mem_write,
    input  logic [ELEN-1:0]  mem_wdata,
    output logic             mem_valid,
    output logic [ELEN-1:0]  mem_rdata
);

    logic [ELEN-1:0] mem [0:WORDS-1];

    initial begin
        for (int i = 0; i < WORDS; i++) mem[i] = '0;
    end

    assign mem_valid = mem_req;
    assign mem_rdata = (mem_req && mem_read) ? mem[mem_addr[31:2]] : '0;

    always_ff @(posedge clk) begin
        if (mem_req && mem_write)
            mem[mem_addr[31:2]] <= mem_wdata;
    end

endmodule
