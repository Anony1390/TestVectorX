// vector_hazard_unit.sv  (NEW FILE)
// Structural hazard handling for the vector unit's multi-cycle LSU.
// Because there is ONE shared fetch stream for scalar + vector
// instructions, a vector load/store that takes N cycles in the vector
// MEM stage must freeze the ENTIRE pipeline (PC, IF/ID, both scalar
// and vector ID/EX and EX/MEM) for those N-1 extra cycles, exactly
// like a multi-cycle memory stall in a simple in-order machine.
//
// v_pipe_stall is driven directly from vector_lsu's `busy` output
// (see vector_lsu.sv) which is asserted starting the SAME cycle the
// op is issued (state==IDLE && start), avoiding a 1-cycle race that
// a state-registered-only signal would have.
module vector_hazard_unit (
    input  logic v_lsu_busy,     // vector_lsu.busy, MEM stage
    output logic v_pipe_stall
);
    assign v_pipe_stall = v_lsu_busy;
endmodule
