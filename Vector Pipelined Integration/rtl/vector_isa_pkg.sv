// vector_isa_pkg.sv
// Instruction-encoding constants for the vector extension, as issued
// through the SAME fetch/decode stream as the scalar RV32IM core.
//
// We piggy-back on two of the four RISC-V "custom" major opcodes
// (guaranteed never to collide with standard RV32IM), so scalar and
// vector instructions can be freely interleaved in one instruction
// stream and fetched by the existing scalar IF stage unmodified.
//
//   custom-2 (0x5B) -> vector ALU / LSU instruction
//   custom-3 (0x7B) -> vector "config" instruction (vsetvl / vsetsew)
//
// custom-2 layout (vector ALU / LSU):
//   [31:28] vop    - vector_opcode_t (VADD..VMAXU, VLOAD, VSTORE)
//   [27:23] vrd    - destination vector register
//   [22:18] vrs1   - source vector register 1 (also base_addr for LSU)
//   [17:13] vrs2   - source vector register 2 (also store_data / index for LSU)
//   [12:11] mode   - vector_mem_mode_t (UNIT_STRIDE/STRIDE/INDEX), ALU ops ignore
//   [10:7]  imm4   - signed 4-bit immediate, used as stride for STRIDE mode
//   [6:0]   opcode - 7'b1011011 (custom-2)
//
//   NOTE: the immediate is only 4 bits (vs. 11 bits in the older
//   non-pipelined vector_controller.sv encoding) because bits [6:0]
//   are now reserved for the opcode so the instruction can live in the
//   same fetch stream as scalar RV32IM instructions. Widen this field
//   further only if you free up more encoding space (e.g. by dropping
//   INDEX mode or shrinking register-file addressing).
//
// custom-3 layout (vector config, vsetvl/vsetsew):
//   [31:12] cfg_data     - 20-bit immediate, sign-extended to 32
//   [11]    cfg_sel_sew  - 1 = write SEW, 0 = write VL
//   [10:7]  reserved
//   [6:0]   opcode       - 7'b1111011 (custom-3)

package vector_isa_pkg;
    localparam logic [6:0] VEC_OP  = 7'b1011011; // custom-2
    localparam logic [6:0] VCFG_OP = 7'b1111011; // custom-3
endpackage
