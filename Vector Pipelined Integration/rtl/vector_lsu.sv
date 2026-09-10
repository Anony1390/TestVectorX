// vector_lsu.sv
// Based on "Vector Simulation/vector_lsu.sv", with TWO additions on
// top of the original FSM:
//
// 1) `busy` (see below) is asserted the same cycle a load/store is
//    issued (state==IDLE && start), not one cycle later, so the
//    pipeline-stall signal derived from it doesn't come up a cycle
//    too late.
//
// 2) `done` is COMBINATIONAL (`state == DONE`), not a registered
//    pulse. This matters for correctness, not just style:
//    `busy` drops as soon as the FSM leaves EXEC (state==DONE),
//    which is also exactly the cycle the final element's data
//    finishes landing in `load_data`. That's the ONE cycle where
//    both (a) load_data is fully valid and (b) the pipeline stall
//    hasn't yet let v_ex_mem_reg advance past this instruction.
//    A REGISTERED `done` (as in the original file) fires one cycle
//    later than that -- by which point v_ex_mem_reg has already
//    moved on to the next instruction, so v_mem_wb_reg commits
//    using the WRONG (or no) regwrite/vrd, and the destination
//    vector register is never correctly written. Making `done`
//    combinational on `state==DONE` collapses that extra cycle of
//    delay and lines the commit up with the one cycle where
//    everything is actually correct.
module vector_lsu
import vector_pkg::*;
(
    input logic clk,
    input logic rst,

    input vector_mem_mode_t mode,
    input vector_opcode_t   op,      // VLOAD / VSTORE (others => idle)

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

// FSM state declared up front, before it's referenced by
// `assign mem_req = (state == EXEC)` below -- Icarus does not support
// forward references to a typedef'd enum variable declared later in
// the same module.
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

logic start;
assign start = load || store;

always_ff @(posedge clk or posedge rst) begin : FSM
    if (rst) state <= IDLE;
    else     state <= nstate;
end

// Written as explicit if/else rather than a ternary between enum
// literals -- Icarus's SV elaborator treats a ternary of two enum
// values as a self-determined (non-enum) expression and refuses to
// assign it back to an enum-typed variable without an explicit cast.
always_comb begin : Next_State
    case (state)
        IDLE: begin
            if (start) nstate = EXEC;
            else       nstate = IDLE;
        end
        EXEC: begin
            if (mem_valid && elem_idx == vl-1) nstate = DONE;
            else                                nstate = EXEC;
        end
        DONE:    nstate = IDLE;
        default: nstate = IDLE;
    endcase
end

always_ff @(posedge clk or posedge rst) begin : LSU_OP
    if (rst) begin
        elem_idx <= 0;
    end
    else if (state == IDLE && start) begin
        elem_idx <= 0;
    end
    else if (state == EXEC && mem_valid) begin
        elem_idx <= elem_idx + 1;
    end
end

// `done` is purely combinational on `state`, deliberately NOT a
// registered pulse -- see header comment for why this matters.
// It reads high for exactly the one cycle state==DONE, then drops
// again once the FSM returns to IDLE.
assign done = (state == DONE);

// Busy the same cycle a new op is issued, through EXEC. Note this
// does NOT include DONE: `busy` dropping during DONE is what lets
// v_ex_mem_reg advance to the next instruction one cycle later,
// which in turn changes `op` away from VLOAD/VSTORE before the FSM
// ever revisits IDLE -- avoiding a self-retriggering stall loop.
assign busy = (state == EXEC) || (state == IDLE && start);

endmodule
