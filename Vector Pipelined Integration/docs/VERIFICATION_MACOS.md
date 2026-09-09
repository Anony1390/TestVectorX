# Verifying the Pipelined Vector Unit on macOS

This walks through simulating `VectorPipelinedCore` (scalar 5-stage
core + pipelined vector unit) end-to-end on macOS using free,
open-source tools: **Icarus Verilog** (`iverilog`/`vvp`) for
compilation + simulation, and **GTKWave** for waveform viewing.

---

## 1. Install the toolchain (Homebrew)

If you don't already have Homebrew:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then install the simulator and waveform viewer:
```bash
brew install icarus-verilog
brew install --cask gtkwave
```

Verify:
```bash
iverilog -V | head -1
vvp -V | head -1
gtkwave --version
```

(If `brew install --cask gtkwave` fails because Homebrew casks aren't
tapped, run `brew tap homebrew/cask` first.)

---

## 2. Lay out the files

Clone your repo and drop the two replacement pipeline registers in,
then add all the new vector files alongside them:

```bash
git clone https://github.com/shady-guy/Vector-X-Capstone-project-.git
cd Vector-X-Capstone-project-

# Back up the two files this integration replaces
cp "RISC V 5 stage pipelined Core/id_ex_reg.v"  "RISC V 5 stage pipelined Core/id_ex_reg.v.bak"
cp "RISC V 5 stage pipelined Core/ex_mem_reg.v" "RISC V 5 stage pipelined Core/ex_mem_reg.v.bak"

# Create a folder for the new pipelined vector integration
mkdir -p "Vector Pipelined Integration"
# Copy in everything from the provided package's rtl/, tb/, docs/
# (unzip the delivered vectorx_pipelined_vector_unit.zip here, or
#  copy the individual files Claude generated)
```

Replace the two backed-up files with the modified versions
(`rtl/id_ex_reg.v`, `rtl/ex_mem_reg.v` from the package) **in place**
at `RISC V 5 stage pipelined Core/`, since `VectorPipelinedCore.sv`
instantiates `id_ex_reg` / `ex_mem_reg` by module name and expects the
`stall` port to exist.

Your file list for compilation will be:
```
RISC V 5 stage pipelined Core/PC.v
RISC V 5 stage pipelined Core/if_id_reg.v
RISC V 5 stage pipelined Core/Control.v
RISC V 5 stage pipelined Core/id_ex_reg.v        <- replaced version
RISC V 5 stage pipelined Core/ex_mem_reg.v       <- replaced version
RISC V 5 stage pipelined Core/mem_wb_reg.v
RISC V 5 stage pipelined Core/hazard_unit.v
RISC V 5 stage pipelined Core/forwardingUnit.v
RISC V 5 stage pipelined Core/comparator.v
RISC V 5 stage pipelined Core/ALU.v
RISC V 5 stage pipelined Core/*.v (Mux2to1.v, Mux3to1.v, InstructionMemory.v, ImmGen.v, ShiftLeftOne.v, Adder.v, Register.v, DataMemory.v)
Vector Pipelined Integration/rtl/vector_pkg.sv
Vector Pipelined Integration/rtl/vector_isa_pkg.sv
Vector Pipelined Integration/rtl/vector_decoder.sv
Vector Pipelined Integration/rtl/vector_alu.sv
Vector Pipelined Integration/rtl/vector_register_file.sv
Vector Pipelined Integration/rtl/vector_config.sv
Vector Pipelined Integration/rtl/vector_lsu.sv
Vector Pipelined Integration/rtl/vector_data_mem.sv
Vector Pipelined Integration/rtl/v_id_ex_reg.sv
Vector Pipelined Integration/rtl/v_ex_mem_reg.sv
Vector Pipelined Integration/rtl/v_mem_wb_reg.sv
Vector Pipelined Integration/rtl/vector_forwarding_unit.sv
Vector Pipelined Integration/rtl/vmux.sv
Vector Pipelined Integration/rtl/vector_hazard_unit.sv
Vector Pipelined Integration/rtl/VectorPipelinedCore.sv
Vector Pipelined Integration/tb/tb_vector_pipelined_core.sv
```

> Note: `Mux2to1.v`, `Mux3to1.v`, `InstructionMemory.v`, `ImmGen.v`,
> `ShiftLeftOne.v`, `Adder.v` were referenced by the existing
> `RISC V 5 stage pipelined Core/top.v` but weren't in the file set
> shown to Claude — they should already exist in your repo (the
> pipelined core wouldn't compile without them today). If `Mux3to1.v`
> is missing, add it — it's the same shape as the `Mux2to1.v` already
> in the repo, just with a 2-bit select and 3 data inputs, matching
> the `sel/s0/s1/s2/out` ports used throughout `top.v`.

---

## 3. Compile with Icarus Verilog

Icarus needs `-g2012` because the new files use SystemVerilog
(`import`, `typedef`, packages, `always_comb`/`always_ff`):

```bash
iverilog -g2012 -o vx_sim.vvp \
  -s tb_vector_pipelined_core \
  "RISC V 5 stage pipelined Core"/*.v \
  "Vector Pipelined Integration/rtl"/*.sv \
  "Vector Pipelined Integration/rtl"/*.v \
  "Vector Pipelined Integration/tb"/*.sv
```

If `iverilog` complains about a **duplicate module** (e.g. if an old
`id_ex_reg.v.bak` is still glob-matched), double-check you removed the
`.bak` copies from the glob, or pass files explicitly instead of `*.v`.

If it complains a module (`Mux3to1`, `InstructionMemory`, etc.) is
**missing**, that file exists in your repo but under a slightly
different path/name than assumed above — find it with:
```bash
find . -iname "Mux3to1*"
find . -iname "InstructionMemory*"
```
and add its path to the `iverilog` command.

---

## 4. Run the simulation

```bash
vvp vx_sim.vvp
```

Expected output (tail of it) — the testbench self-checks and prints a
summary:
```
--- Scalar register file ---
x1=5 x2=7 x3=9 x4=11

--- Vector register file (lane 0..3) ---
v5: 11 12 13 14
v6: -9 -8 -7 -6
v7: 11 12 13 14

Expected: v5 = 11,12,13,14 | v6 = -9,-8,-7,-6 | v7 = 11,12,13,14 (round-tripped through memory)
Expected: x1=5 x2=7 x3=9 x4=11 (scalar instructions must all still retire correctly)
```

What this is checking:
- `v5`/`v6` confirm the **vector EX stage** (VALU) and **forwarding**
  are correct.
- `v7` confirms the full **VSTORE → VLOAD round trip through
  `vector_data_mem`** works, i.e. the multi-cycle vector MEM stage and
  its `done`/`busy` handshake are correct.
- `x1..x4` all landing on their expected values confirms the
  **structural stall correctly freezes and then resumes the scalar
  pipeline** around the two vector LSU instructions (instructions 6
  and 8 must not execute early, and must not be lost/duplicated).

If any value is wrong: re-run with the waveform (`wave.vcd`, written
automatically by the testbench) open in GTKWave and inspect
`v_pipe_stall`, `dut.m_v_lsu.state`, `dut.m_v_lsu.busy`, and
`dut.m_v_lsu.done` around the `VSTORE`/`VLOAD` instructions first —
that's the most likely place a hand-integrated hookup mistake shows up
(wrong port order, or `stall` accidentally tied off).

---

## 5. Inspect waveforms in GTKWave

```bash
gtkwave wave.vcd &
```

In the GTKWave SST/hierarchy pane on the left, drill into:
- `tb_vector_pipelined_core.dut` — top-level signals (`clk`, `start`,
  `v_pipe_stall`, `wr_pc`, `wr_if_id`)
- `dut.m_v_lsu` — `state`, `elem_idx`, `busy`, `done`, `mem_req`
- `dut.m_v_id_ex_reg` / `dut.m_v_ex_mem_reg` — confirm these **hold**
  their outputs (don't change) every cycle `v_pipe_stall` is high
- `dut.m_id_ex_reg` / `dut.m_ex_mem_reg` (scalar) — same check
- `dut.m_v_regfile.vrf[5]` .. `vrf[7]` — final vector register values

Drag the signals of interest into the waveform pane, right-click →
"Data Format" → "Decimal" (or "Signed Decimal" for `v6`) to read
values more easily than hex.

---

## 6. Iterating

Once the smoke test passes, extend `tb_vector_pipelined_core.sv` with
more instructions — e.g. back-to-back vector ALU ops (checks
forwarding without any stall), a scalar load/store interleaved with a
vector load/store (checks the two independent memories don't
interfere), and a branch immediately after a vector instruction
(checks squash/flush interaction with `v_pipe_stall`). Each new
scenario is just a few more lines added to the `dut.m_InstMem.mem[]`
program array before `start = 1`.
