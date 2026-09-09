// vector_forwarding_unit.sv  (NEW FILE)
// Mirrors the scalar core's forwardingUnit.v, but for the vector
// register file. Resolves RAW hazards between a vector instruction in
// EX (reading v_id_ex.vrs1/vrs2) and:
//   - an ALU-producing instruction currently in vector EX/MEM
//     (1 instruction ahead), or
//   - a committing instruction currently in vector MEM/WB
//     (1-2 instructions ahead, includes completed LSU loads).
// LSU-in-flight results are intentionally NOT forwarded from EX/MEM
// (the data isn't valid yet there); consumers of a value produced by
// an in-flight VLOAD simply see Src=00 (stale/no forward) until the
// vector_hazard_unit's structural LSU stall has already resolved the
// ordering -- by construction, the whole pipeline is frozen while an
// LSU op is mid-flight, so no younger vector instruction can even
// reach EX until the LSU (and its MEM/WB forward) has committed.
module vector_forwarding_unit (
    input  logic [4:0] vrs1,
    input  logic [4:0] vrs2,

    input  logic [4:0] ex_mem_vrd,
    input  logic       ex_mem_regwrite,
    input  logic       ex_mem_lsu_en,   // exclude in-flight LSU results

    input  logic [4:0] mem_wb_vrd,
    input  logic       mem_wb_regwrite,

    output logic [1:0] Src1,
    output logic [1:0] Src2
);
    always_comb begin
        if (ex_mem_regwrite && !ex_mem_lsu_en && ex_mem_vrd != 0 && ex_mem_vrd == vrs1)
            Src1 = 2'b10; // forward from vector EX/MEM (VALU result)
        else if (mem_wb_regwrite && mem_wb_vrd != 0 && mem_wb_vrd == vrs1)
            Src1 = 2'b01; // forward from vector MEM/WB (committed write)
        else
            Src1 = 2'b00; // use value read in ID stage

        if (ex_mem_regwrite && !ex_mem_lsu_en && ex_mem_vrd != 0 && ex_mem_vrd == vrs2)
            Src2 = 2'b10;
        else if (mem_wb_regwrite && mem_wb_vrd != 0 && mem_wb_vrd == vrs2)
            Src2 = 2'b01;
        else
            Src2 = 2'b00;
    end
endmodule
