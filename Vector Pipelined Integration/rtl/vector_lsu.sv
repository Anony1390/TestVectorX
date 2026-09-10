// vector_lsu.sv
// Based on "Vector Simulation/vector_lsu.sv", with ONE addition: an
// explicit combinational `busy` output that is asserted starting on
// the very same cycle a load/store is issued (state==IDLE && start),
// not just once the FSM has already moved to EXEC. This closes a
// 1-cycle race: without it, the pipeline stall signal (derived from
// `busy`) would come up one cycle too late and let a second
// instruction slip into the pipeline before the multi-cycle LSU op
// is actually accounted for. `done` itself is unchanged from the
// original file (a level signal, held high after completion until
// the next `start`).
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
    output logic busy     // NEW: pipeline-stall qualifier (see header)
);

// FSM state declared up front, BEFORE it's referenced by the
// `assign mem_req = (state == EXEC)` below. Icarus does not support
// forward references to a typedef'd enum variable declared later in
// the same module ("declaration after use").
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
// literals: Icarus's SV elaborator treats a ternary of two enum
// values as a self-determined (non-enum) expression and refuses to
// assign it back to an enum-typed variable without an explicit cast
// ("This assignment requires an explicit cast."). if/else sidesteps
// the issue and reads the same.
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
        done     <= 0;
    end
    else if (state == IDLE && start) begin
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

// Busy the same cycle a new op is issued, through completion.
assign busy = (state == EXEC) || (state == IDLE && start);

endmodule
