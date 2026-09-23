// vector_lsu.sv
// Based on "Vector Simulation/vector_lsu.sv", with two changes from
// the original, both needed for correct pipeline integration:
//
// 1. `busy` output: asserted for the FULL duration an instruction
//    occupies the MEM stage, INCLUDING the DONE state. This matters
//    because `done` itself is a *registered* signal -- it only
//    becomes 1 the cycle AFTER the FSM reaches DONE, not on the same
//    cycle. If `busy` (and therefore the pipeline stall it drives)
//    dropped as soon as state==DONE, the surrounding pipeline would
//    unstall and advance to the next instruction one cycle before
//    v_mem_wb_reg ever actually sees done==1, silently dropping the
//    just-finished instruction's commit.
//
// 2. `issue`: an explicit one-shot pulse INPUT (from the wrapper),
//    replacing the original design's internal `start = load||store`.
//    Because the surrounding pipeline intentionally holds this
//    module's op/mode/base_addr/etc. inputs steady for the ENTIRE
//    time an LSU instruction is in flight (including the extra
//    DONE-state hold cycle from point 1), a level-based `start`
//    derived straight from `op` would spuriously re-trigger the FSM
//    the moment `state` returns to IDLE but the (stale, still-held)
//    op fields are still present -- i.e. it would silently re-run
//    the instruction that just finished. `issue` instead pulses
//    exactly once, only on the cycle a NEW instruction has actually
//    just landed in this stage (see the `v_lsu_issue` generation in
//    VectorPipelineStandalone.sv / VectorPipelinedCore.sv).
//
// NOTE: the FSM `typedef`/state declarations are placed near the top
// of the module, before anything references `state`/`nstate`. Icarus
// Verilog requires a typedef'd enum variable to be declared before
// its first use within the same module (unlike some other
// simulators, which tolerate out-of-order module items) -- keep this
// ordering if you edit this file.
module vector_lsu
import vector_pkg::*;
(
    input logic clk,
    input logic rst,

    input vector_mem_mode_t mode,
    input vector_opcode_t   op,      // VLOAD / VSTORE (others => idle)
    input logic             issue,   // one-shot: a NEW op just arrived

    input logic [15:0] vl,
    input logic [31:0] base_addr,
    input logic [31:0] stride,
    input logic [VLEN-1:0] index_vector,
    input logic [VLEN-1:0] store_data,

    output logic [VLEN-1:0] load_data,

    output logic [31:0] mem_addr,
    output logic mem_req,
    output logic mem_read,
    output logic mem_write,
    output logic [ELEN-1:0] mem_wdata,
    input  logic mem_valid,
    input  logic [ELEN-1:0] mem_rdata,

    output logic done,
    output logic busy     // pipeline-stall qualifier (see header)
);

// ---- FSM state declared first (must precede any use below) ----
typedef enum logic [1:0] {IDLE, EXEC, DONE} state_t;
state_t state, nstate;

logic [15:0] elem_idx;
logic [31:0] addr;
logic load;
logic store;
assign load  = (op == VLOAD);
assign store = (op == VSTORE);

localparam SHIFT = $clog2(ELEN/8);

always_comb begin : LSU_Mode
    logic [ELEN-1:0] curr_index;
    logic [31:0] offset;
    curr_index = index_vector[elem_idx*ELEN +: ELEN];
    unique case (mode)
        UNIT_STRIDE: offset = elem_idx << SHIFT;
        STRIDE:      offset = elem_idx * stride;
        INDEX:       offset = curr_index << SHIFT;
        default:     offset = '0;
    endcase
    addr = base_addr + offset;
end

assign mem_addr  = addr;
assign mem_req   = (state == EXEC);
assign mem_read  = load;
assign mem_write = store;
assign mem_wdata = store_data[elem_idx*ELEN +: ELEN];

always_ff @(posedge clk) begin : Loads
    if (load && mem_valid) begin
        load_data[elem_idx*ELEN +: ELEN] <= mem_rdata;
    end
end

always_ff @(posedge clk or posedge rst) begin : FSM
    if (rst) state <= IDLE;
    else     state <= nstate;
end

always_comb begin : Next_State
    case (state)
        IDLE: if (issue) nstate = EXEC; else nstate = IDLE;
        EXEC: if (mem_valid && elem_idx == vl-1) nstate = DONE; else nstate = EXEC;
        DONE: nstate = IDLE;
        default: nstate = IDLE;
    endcase
end

always_ff @(posedge clk or posedge rst) begin : LSU_OP
    if (rst) begin
        elem_idx <= 0;
        done     <= 0;
    end
    else if (state == IDLE && issue) begin
        elem_idx <= 0;
        done     <= 0;
    end
    else if (state == EXEC && mem_valid) begin
        elem_idx <= elem_idx + 1;
    end
    else if (state == DONE) begin
        done <= 1;
    end
end

// Busy for the entire time this stage is occupied by an in-flight
// instruction: the issue cycle itself, the whole EXEC burst, AND the
// DONE cycle (so the surrounding pipe doesn't unstall/advance before
// `done` is actually visible -- see header comment).
assign busy = (state != IDLE) || issue;

endmodule
