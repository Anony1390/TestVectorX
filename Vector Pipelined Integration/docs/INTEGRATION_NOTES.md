# Pipelined Vector Unit — Integration Notes

## What this package contains

A pipelined vector datapath (ID → EX → MEM → WB, matching the scalar
core's stage names) wired into a copy of
`RISC V 5 stage pipelined Core/top.v` (`FullyPipelinedCore`), renamed
`VectorPipelinedCore`. Scalar and vector instructions share a single
fetch stream, single PC, and a single IF/ID register.

```
rtl/
  vector_pkg.sv            - unmodified copy of Vector Simulation/vector_pkg.sv
  vector_isa_pkg.sv         - NEW: opcode constants + encoding docs
  vector_decoder.sv         - NEW: ID-stage combinational decode
  vector_alu.sv (VALU)      - unmodified copy of Vector Simulation/vector_alu.sv
  vector_register_file.sv   - unmodified copy
  vector_config.sv          - unmodified copy (vl/sew CSRs)
  vector_lsu.sv             - modified: added `busy` output (see below)
  vector_data_mem.sv        - NEW: private vector data memory
  v_id_ex_reg.sv            - NEW: vector ID/EX pipeline register
  v_ex_mem_reg.sv           - NEW: vector EX/MEM pipeline register
  v_mem_wb_reg.sv           - NEW: vector MEM/WB pipeline register
  vector_forwarding_unit.sv - NEW: RAW-hazard forwarding for vector regs
  vmux.sv                   - NEW: VLEN-wide 2:1 / 3:1 muxes
  vector_hazard_unit.sv     - NEW: turns LSU busy into a global pipe stall
  id_ex_reg.v                - MODIFIED: added `stall` (hold) input
  ex_mem_reg.v                - MODIFIED: added `stall` (hold) input
  VectorPipelinedCore.sv      - NEW: top-level integration
tb/
  tb_vector_pipelined_core.sv - smoke-test testbench
docs/
  INTEGRATION_NOTES.md (this file)
  VERIFICATION_MACOS.md
```

**Files you should drop into the repo, replacing the existing ones:**
- `RISC V 5 stage pipelined Core/id_ex_reg.v` → replace with `rtl/id_ex_reg.v`
- `RISC V 5 stage pipelined Core/ex_mem_reg.v` → replace with `rtl/ex_mem_reg.v`
- Everything else here is additive (new files); nothing else in the
  existing pipelined core needs to change. `PC.v`, `if_id_reg.v`,
  `mem_wb_reg.v`, `hazardDetectionUnit`, `Control.v`, `ALU.v`,
  `comparator.v`, `forwardingUnit.v`, `Register.v` (do-not-modify) are
  reused exactly as-is.

## Instruction encoding

Vector instructions are carried in the same 32-bit fetch stream as
scalar RV32IM using two of RISC-V's reserved "custom" opcodes so they
can never collide with real RV32IM encodings:

- **custom-2** (`opcode = 7'b1011011`) → vector ALU/LSU instructions
- **custom-3** (`opcode = 7'b1111011`) → vector config (`vsetvl`/`vsetsew`)

Full bit layout is documented at the top of `vector_isa_pkg.sv` and
`vector_decoder.sv`. Note the stride immediate is only 4 bits (vs. 11
bits in the old non-pipelined `vector_controller.sv` encoding) because
7 bits are now reserved for the opcode field — widen it only if you
free up encoding space elsewhere (e.g. drop `INDEX` addressing mode).

Because any instruction whose `opcode[6:0]` isn't custom-2/custom-3 is
ignored by the vector decoder (outputs all-zero control), and any
instruction that IS custom-2/custom-3 is ignored by the scalar
`Control` module (falls into its `default:` case → all-zero control),
scalar and vector instructions can be freely interleaved with zero
extra decode-conflict logic.

## Pipeline / hazard design

- **Vector ALU ops** are single-cycle in EX (the existing `VALU` is
  fully combinational and lane-parallel), so they flow through the
  vector pipeline exactly like a scalar ALU op — no stalling needed.
- **Vector LSU ops** (`VLOAD`/`VSTORE`) take `vl` cycles in the vector
  MEM stage (`vector_lsu`'s own FSM). Because there's a single shared
  fetch stream, the **entire** pipeline (scalar and vector: `PC`,
  `IF/ID`, both `ID/EX` regs, both `EX/MEM` regs) is frozen for the
  duration via `v_pipe_stall`, generated in `vector_hazard_unit.sv`
  from `vector_lsu`'s new `busy` output. This is a simple **structural
  stall**, not real dual-issue — it is correct but not fast; see
  "Ideas for follow-up work" below.
- `vector_lsu.busy` is asserted the *same* cycle the op is issued
  (`state==IDLE && start`), not one cycle later — this closes a race
  that would otherwise let one extra instruction slip into the
  pipeline before the stall takes effect.
- **RAW hazards on vector registers** (an instruction reading a vector
  register that an immediately-preceding vector instruction is about
  to write) are resolved by forwarding for ALU-producing instructions
  (`vector_forwarding_unit.sv`, same structure as the scalar core's
  `forwardingUnit.v`). Because the whole pipeline stalls while an
  LSU op is in flight, a load's result is always safely committed to
  the register file (and forwarded via the MEM/WB path) before any
  younger instruction can reach EX, so LSU results don't need a
  separate EX/MEM forward path.
- **Branch/jump squash**: unchanged — the existing scalar
  `hazardDetectionUnit` still flushes `IF/ID` on a taken branch/
  jal/jalr. Once `IF/ID` is zeroed, both the scalar `Control` decoder
  and the new `vector_decoder` naturally see an all-zero instruction
  and produce no-op control signals, so the vector pipeline doesn't
  need a second, separate flush path for this case.

## Known simplifications / good next steps

1. **Separate vector data memory.** `vector_data_mem.sv` is a
   standalone word-addressed array, independent from the scalar
   core's `DataMemory.v`. This avoids needing a dual-port arbiter for
   this milestone. Follow-up: merge into one arbitrated memory (or map
   both into distinct address ranges of one larger memory) if you want
   scalar loads/stores and vector loads/stores to see a consistent
   view of memory.
2. **No true dual-issue.** A vector LSU op stalls the scalar pipeline
   completely rather than letting independent scalar instructions
   continue underneath it. This is the simplest correct design; a
   faster version would let non-dependent scalar instructions continue
   fetching/executing while only the vector MEM stage is busy (this
   needs a second, independent scalar program-counter-advance path or
   an out-of-order-issue scoreboard, which is a bigger project).
3. **No WAW/structural checks between back-to-back LSU ops.** Because
   the whole pipeline stalls until an LSU op fully completes before
   the next instruction is even fetched, there's no way for two
   vector LSU ops to be in flight at once, so this is safe by
   construction — but it also means back-to-back vector loads/stores
   are as slow as a fully serial design (no LSU pipelining across
   instructions). This matches "make the vector unit pipelined" at the
   per-instruction/stage level; deeper LSU-to-LSU pipelining is future
   work.
4. **No vector exceptions/misalignment checks.** Not implemented.
