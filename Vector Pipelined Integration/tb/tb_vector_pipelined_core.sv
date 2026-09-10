// tb_vector_pipelined_core.sv  (NEW FILE)
// Standalone testbench for VectorPipelinedCore. Drives clk/reset,
// force-loads a tiny hand-assembled program (mix of scalar + vector
// instructions) directly into the DUT's instruction memory array via
// hierarchical reference (same trick used by the existing repo
// testbenches, e.g. vector_tb.sv poking dut_top.imem[]), and prints
// the vector register file contents as the program runs.
//
// NOTE: This testbench assumes InstructionMemory exposes its storage
// array as `mem` (the same convention as instruction_mem.v in the
// repo's single-cycle core). If your InstructionMemory module in
// "RISC V 5 stage pipelined Core/" names its array differently,
// update the hierarchical path below (search: dut.m_InstMem.<name>).
`timescale 1ns/1ps

module tb_vector_pipelined_core;
    import vector_pkg::*;
    import vector_isa_pkg::*;

    logic clk, start;

    VectorPipelinedCore dut (
        .clk(clk),
        .start(start),
        .dummy_out()
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Vector instruction encoder (matches vector_isa_pkg.sv layout)
    function automatic logic [31:0] vinstr(
        input vector_opcode_t vop,
        input logic [4:0]     vrd,
        input logic [4:0]     vrs1,
        input logic [4:0]     vrs2,
        input vector_mem_mode_t mode = UNIT_STRIDE,
        input logic [3:0]     imm4 = 4'd0
    );
        return {vop, vrd, vrs1, vrs2, mode, imm4, VEC_OP};
    endfunction

    // Vector config instruction encoder (vsetvl / vsetsew)
    function automatic logic [31:0] vcfginstr(
        input logic         sel_sew, // 0 = vl, 1 = sew
        input logic [19:0]  data
    );
        return {data, sel_sew, 4'b0000, VCFG_OP};
    endfunction

    // Scalar RV32I "addi rd, x0, imm" encoder, for loading base addrs
    // into scalar regs which we then copy into vector regs via a
    // scalar store + vector load sequence is overkill for this smoke
    // test -- instead we load vector base addresses directly with a
    // VADD against v0 (hardwired zero) using the immediate is NOT
    // possible (no vector-immediate ALU op defined), so this testbench
    // seeds vector source registers directly via hierarchical force
    // instead, which is simpler for a first bring-up test.
    localparam [6:0] OP_ADDI = 7'b0010011;
    function automatic logic [31:0] addi(
        input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm
    );
        return {imm, rs1, 3'b000, rd, OP_ADDI};
    endfunction

    initial begin
        // ---- reset ----
        start = 0;
        repeat (2) @(posedge clk);

        // Let the synchronous reset processes (vector_register_file,
        // vector_config, etc.) finish their NBA-scheduled updates for
        // THIS edge (rst was still asserted when it fired) before we
        // force any values in below. Without this, our blocking
        // writes below execute in the same "active" region as the
        // edge, but the reset's own non-blocking `vrf[i] <= '0`
        // updates land in the "NBA" region right after — silently
        // clobbering our seeded values back to zero in the same
        // timestep. A tiny delay moves us past that NBA region.
        #1;
        start = 1;

        // ---- seed vector source registers directly (bring-up shortcut) ----
        // v1[lane i] = i+1, v2[lane i] = 10  (see vector_register_file hierarchy)
        for (int i = 0; i < LANES; i++) begin
            dut.m_v_regfile.vrf[1][i*SEW +: SEW] = 32'(i+1);
            dut.m_v_regfile.vrf[2][i*SEW +: SEW] = 32'd10;
        end
        // v3 = base address (element 0) for the LSU tests, in lane 0's
        // low word (vector_lsu reads base_addr from vs1[31:0]).
        dut.m_v_regfile.vrf[3] = '0;
        dut.m_v_regfile.vrf[3][31:0] = 32'h40;

        // ---- program ----
        // 0: scalar NOP-ish (addi x1,x0,5)          -- exercise scalar path
        // 1: vsetvl  vl = 4
        // 2: VADD  v5 = v1 + v2      (expect 11,12,13,14,...)
        // 3: scalar addi x2,x0,7     -- runs concurrently with vector EX
        // 4: VSUB  v6 = v1 - v2
        // 5: VSTORE v5 -> mem[v3 base], unit-stride   (multi-cycle: stalls pipeline)
        // 6: scalar addi x3,x0,9     -- must NOT execute until stall clears
        // 7: VLOAD  v7 <- mem[v3 base], unit-stride   (multi-cycle)
        // 8: scalar addi x4,x0,11
        dut.m_InstMem.mem[0] = addi(5'd1, 5'd0, 12'd5);
        dut.m_InstMem.mem[1] = vcfginstr(1'b0, 20'd4);
        dut.m_InstMem.mem[2] = vinstr(VADD, 5'd5, 5'd1, 5'd2);
        dut.m_InstMem.mem[3] = addi(5'd2, 5'd0, 12'd7);
        dut.m_InstMem.mem[4] = vinstr(VSUB, 5'd6, 5'd1, 5'd2);
        dut.m_InstMem.mem[5] = vinstr(VSTORE, 5'd0, 5'd3, 5'd5, UNIT_STRIDE);
        dut.m_InstMem.mem[6] = addi(5'd3, 5'd0, 12'd9);
        dut.m_InstMem.mem[7] = vinstr(VLOAD, 5'd7, 5'd3, 5'd0, UNIT_STRIDE);
        dut.m_InstMem.mem[8] = addi(5'd4, 5'd0, 12'd11);
        for (int i = 9; i < 32; i++) dut.m_InstMem.mem[i] = 32'd0;

        repeat (400) @(posedge clk);

        $display("\n--- Scalar register file ---");
        $display("x1=%0d x2=%0d x3=%0d x4=%0d",
                  dut.m_Register.regs[1], dut.m_Register.regs[2],
                  dut.m_Register.regs[3], dut.m_Register.regs[4]);

        $display("\n--- Vector register file (lane 0..3) ---");
        for (int r = 5; r <= 7; r++) begin
            $write("v%0d:", r);
            for (int i = 0; i < 4; i++)
                $write(" %0d", dut.m_v_regfile.vrf[r][i*SEW +: SEW]);
            $display("");
        end

        $display("\nExpected: v5 = 11,12,13,14 | v6 = -9,-8,-7,-6 | v7 = 11,12,13,14 (round-tripped through memory)");
        $display("Expected: x1=5 x2=7 x3=9 x4=11 (scalar instructions must all still retire correctly)");

        $finish;
    end

    // waveform dump
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_vector_pipelined_core);
    end

    // watchdog
    initial begin
        #10_000;
        $display("[ERROR] watchdog timeout");
        $finish;
    end

endmodule
