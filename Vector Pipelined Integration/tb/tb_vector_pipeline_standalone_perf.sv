`timescale 1ns/1ps

// ============================================================================
// tb_vector_pipeline_standalone_perf.sv
//
// Performance characterization for VectorPipelineStandalone ONLY.
//
// No scalar RISC-V core is instantiated.
//
// Measures:
//   - architectural vector parameters
//   - vector ALU steady-state throughput
//   - vector EX->WB latency
//   - LSU issue/done latency
//   - LSU busy cycles
//   - vector pipeline stall cycles
//   - vector WB commits
//   - final architectural results
//   - VCD waveform
//
// The standalone DUT is:
//   VectorPipelineStandalone.sv
//
// Test:
//   VSETVL VL=8
//   12 independent back-to-back VADD instructions
//   VSTORE
//   VLOAD
//   VADD dependent on the loaded vector
//
// This deliberately measures the vector pipeline in isolation.
// ============================================================================

module tb_vector_pipeline_standalone_perf;

    import vector_pkg::*;
    import vector_isa_pkg::*;

    logic clk;
    logic rst;
    logic v_pipe_stall;

    VectorPipelineStandalone #(.IMEM_WORDS(64)) dut (
        .clk            (clk),
        .rst            (rst),
        .v_pipe_stall_o (v_pipe_stall)
    );

    // 100 MHz reference clock: 10 ns period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // Instruction encoders -- same layout as the standalone verification TB
    // ------------------------------------------------------------------------
    function automatic logic [31:0] vinstr(
        input vector_opcode_t   vop,
        input logic [4:0]       vrd,
        input logic [4:0]       vrs1,
        input logic [4:0]       vrs2,
        input vector_mem_mode_t mode,
        input logic [3:0]       imm4
    );
        vinstr = {vop, vrd, vrs1, vrs2, mode, imm4, VEC_OP};
    endfunction

    function automatic logic [31:0] vcfginstr(
        input logic        sel_sew,
        input logic [19:0] data
    );
        vcfginstr = {data, sel_sew, 4'b0000, VCFG_OP};
    endfunction

    // ------------------------------------------------------------------------
    // Counters
    // ------------------------------------------------------------------------
    integer cycle_count;
    integer total_cycles;
    integer vector_ex_count;
    integer vector_alu_ex_count;
    integer vector_lsu_ex_count;
    integer vector_wb_count;

    integer stall_cycles;
    integer lsu_busy_cycles;
    integer lsu_issue_count;
    integer lsu_done_count;

    integer first_alu_ex_cycle;
    integer last_alu_ex_cycle;
    integer first_alu_wb_cycle;
    integer last_alu_wb_cycle;

    integer alu_latency_sum;
    integer alu_latency_count;

    integer lsu_issue_cycle [0:7];
    integer lsu_done_cycle  [0:7];
    integer lsu_latency     [0:7];

    integer ex_cycle_for_rd [0:31];
    integer wb_cycle_for_rd [0:31];

    integer i;
    integer r;

    logic prev_lsu_done;
    logic finished;
    integer finish_cycle;

    // Benchmark ALU destinations:
    // v4-v15 are the 12 independent VADDs.
    // v17 is the post-load dependent VADD.
    function automatic integer is_benchmark_alu_rd(input integer rd);
        begin
            if ((rd >= 4 && rd <= 15) || rd == 17)
                is_benchmark_alu_rd = 1;
            else
                is_benchmark_alu_rd = 0;
        end
    endfunction

    // ------------------------------------------------------------------------
    // Main stimulus + measurement
    // ------------------------------------------------------------------------
    initial begin

        cycle_count         = 0;
        total_cycles        = 0;
        vector_ex_count     = 0;
        vector_alu_ex_count = 0;
        vector_lsu_ex_count = 0;
        vector_wb_count     = 0;

        stall_cycles        = 0;
        lsu_busy_cycles     = 0;
        lsu_issue_count     = 0;
        lsu_done_count      = 0;

        first_alu_ex_cycle  = -1;
        last_alu_ex_cycle   = -1;
        first_alu_wb_cycle  = -1;
        last_alu_wb_cycle   = -1;

        alu_latency_sum     = 0;
        alu_latency_count   = 0;

        prev_lsu_done       = 1'b0;
        finished            = 1'b0;
        finish_cycle        = -1;

        for (i = 0; i < 8; i = i + 1) begin
            lsu_issue_cycle[i] = -1;
            lsu_done_cycle[i]  = -1;
            lsu_latency[i]     = -1;
        end

        for (r = 0; r < 32; r = r + 1) begin
            ex_cycle_for_rd[r] = -1;
            wb_cycle_for_rd[r] = -1;
        end

        // ================================================================
        // RESET
        // ================================================================
        rst = 1'b1;
        repeat (3) @(posedge clk);

        // ================================================================
        // SEED VECTOR REGISTER FILE
        //
        // v1 = [1,2,3,4,5,6,7,8]
        // v2 = [10,10,10,10,10,10,10,10]
        //
        // Therefore each independent VADD gives:
        // [11,12,13,14,15,16,17,18]
        //
        // v9 = base address 0x80 for LSU operations.
        // ================================================================
        for (i = 0; i < LANES; i = i + 1) begin
            dut.m_v_regfile.vrf[1][i*SEW +: SEW] = 32'(i+1);
            dut.m_v_regfile.vrf[2][i*SEW +: SEW] = 32'd10;
        end

        dut.m_v_regfile.vrf[9] = '0;
        dut.m_v_regfile.vrf[9][31:0] = 32'h00000080;

        // ================================================================
        // PROGRAM
        //
        // 0   : VSETVL VL=8
        //
        // 1-12: 12 independent back-to-back VADDs
        //       v4-v15 = v1 + v2
        //
        //       Since these are independent, the VALU pipeline can be
        //       measured in steady state without RAW dependencies.
        //
        // 13  : VSTORE v4 -> memory[0x80]
        // 14  : VLOAD  v16 <- memory[0x80]
        // 15  : VADD   v17 = v16 + v2
        //
        // 16+ : NOP
        // ================================================================

        dut.v_imem[0] =
            vcfginstr(1'b0, 20'd8);

        dut.v_imem[1] =
            vinstr(VADD, 5'd4,  5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[2] =
            vinstr(VADD, 5'd5,  5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[3] =
            vinstr(VADD, 5'd6,  5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[4] =
            vinstr(VADD, 5'd7, 5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[5] =
            vinstr(VADD, 5'd8, 5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[6] =
            vinstr(VADD, 5'd9, 5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[7] =
            vinstr(VADD, 5'd10, 5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[8] =
            vinstr(VADD, 5'd11, 5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[9] =
            vinstr(VADD, 5'd12, 5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[10] =
            vinstr(VADD, 5'd13, 5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[11] =
            vinstr(VADD, 5'd14, 5'd1, 5'd2, UNIT_STRIDE, 4'd0);
        dut.v_imem[12] =
            vinstr(VADD, 5'd15, 5'd1, 5'd2, UNIT_STRIDE, 4'd0);

        dut.v_imem[13] =
            vinstr(VSTORE, 5'd0, 5'd9, 5'd4, UNIT_STRIDE, 4'd0);

        dut.v_imem[14] =
            vinstr(VLOAD, 5'd16, 5'd9, 5'd0, UNIT_STRIDE, 4'd0);

        dut.v_imem[15] =
            vinstr(VADD, 5'd17, 5'd16, 5'd2, UNIT_STRIDE, 4'd0);

        for (i = 16; i < 64; i = i + 1)
            dut.v_imem[i] = 32'd0;

        // Release reset
        rst = 1'b0;

        // ================================================================
        // MEASUREMENT LOOP
        // ================================================================
        for (cycle_count = 0; cycle_count < 300; cycle_count = cycle_count + 1) begin

            @(posedge clk);
            #1;

            // -----------------------------
            // Vector instruction reaches EX
            // -----------------------------
            if (dut.v_ex_valid) begin
                vector_ex_count = vector_ex_count + 1;

                if (dut.v_ex_lsu_en) begin
                    vector_lsu_ex_count = vector_lsu_ex_count + 1;
                end
                else begin
                    vector_alu_ex_count = vector_alu_ex_count + 1;

                    if (first_alu_ex_cycle < 0)
                        first_alu_ex_cycle = cycle_count;

                    last_alu_ex_cycle = cycle_count;

                    if (is_benchmark_alu_rd(dut.v_ex_vrd)) begin
                        if (ex_cycle_for_rd[dut.v_ex_vrd] < 0)
                            ex_cycle_for_rd[dut.v_ex_vrd] = cycle_count;
                    end
                end
            end

            // -----------------------------
            // Vector writeback
            // -----------------------------
            if (dut.v_wb_regwrite) begin
                vector_wb_count = vector_wb_count + 1;

                if (first_alu_wb_cycle < 0)
                    first_alu_wb_cycle = cycle_count;

                last_alu_wb_cycle = cycle_count;

                if (is_benchmark_alu_rd(dut.v_wb_vrd)) begin
                    if (wb_cycle_for_rd[dut.v_wb_vrd] < 0)
                        wb_cycle_for_rd[dut.v_wb_vrd] = cycle_count;
                end
            end

            // -----------------------------
            // Pipeline stall
            // -----------------------------
            if (v_pipe_stall)
                stall_cycles = stall_cycles + 1;

            // -----------------------------
            // LSU busy
            // -----------------------------
            if (dut.m_v_lsu.busy)
                lsu_busy_cycles = lsu_busy_cycles + 1;

            // -----------------------------
            // LSU issue
            // -----------------------------
            if (dut.v_lsu_issue) begin
                if (lsu_issue_count < 8)
                    lsu_issue_cycle[lsu_issue_count] = cycle_count;

                lsu_issue_count = lsu_issue_count + 1;
            end

            // -----------------------------
            // LSU done
            //
            // done can remain asserted during the completion state, so
            // count its rising edge rather than every cycle it is high.
            // -----------------------------
            if (dut.v_lsu_done && !prev_lsu_done) begin
                if (lsu_done_count < 8) begin
                    lsu_done_cycle[lsu_done_count] = cycle_count;

                    if (lsu_issue_count > lsu_done_count &&
                        lsu_issue_cycle[lsu_done_count] >= 0) begin
                        lsu_latency[lsu_done_count] =
                            cycle_count - lsu_issue_cycle[lsu_done_count];
                    end
                end

                lsu_done_count = lsu_done_count + 1;
            end

            prev_lsu_done = dut.v_lsu_done;

            // -----------------------------
            // Final benchmark instruction
            // -----------------------------
            if (dut.v_wb_regwrite && dut.v_wb_vrd == 5'd17) begin
                finished     = 1'b1;
                finish_cycle = cycle_count;
                total_cycles = cycle_count + 1;
                break;
            end
        end

        // ================================================================
        // EX -> WB LATENCY
        // ================================================================
        for (r = 0; r < 32; r = r + 1) begin
            if (is_benchmark_alu_rd(r) &&
                ex_cycle_for_rd[r] >= 0 &&
                wb_cycle_for_rd[r] >= 0) begin

                alu_latency_sum =
                    alu_latency_sum +
                    (wb_cycle_for_rd[r] - ex_cycle_for_rd[r]);

                alu_latency_count = alu_latency_count + 1;
            end
        end

        // ================================================================
        // REPORT
        // ================================================================
        $display("");
        $display("================================================================");
        $display("       STANDALONE VECTOR PIPELINE PERFORMANCE REPORT");
        $display("================================================================");

        $display("");
        $display("--- Architectural Parameters ---");
        $display("VLEN                   : %0d bits", VLEN);
        $display("SEW                    : %0d bits", SEW);
        $display("Physical lanes         : %0d", LANES);
        $display("Vector registers       : %0d", MAX_VREG);
        $display("Vector RF capacity     : %0d bits", MAX_VREG * VLEN);
        $display("Vector RF capacity     : %0d bytes", (MAX_VREG * VLEN) / 8);
        $display("Pipeline stages        : ID -> EX -> MEM -> WB");
        $display("Test VL                : 8");
        $display("Clock period           : 10 ns");
        $display("Reference clock        : 100 MHz");

        $display("");
        $display("--- Instruction Activity ---");
        $display("Vector EX instructions    : %0d", vector_ex_count);
        $display("Vector ALU EX operations  : %0d", vector_alu_ex_count);
        $display("Vector LSU EX operations  : %0d", vector_lsu_ex_count);
        $display("Vector WB commits         : %0d", vector_wb_count);

        $display("");
        $display("--- VALU Throughput ---");

        if (first_alu_ex_cycle >= 0 &&
            last_alu_ex_cycle >= first_alu_ex_cycle) begin

            $display("First benchmark ALU EX cycle : %0d",
                     first_alu_ex_cycle);
            $display("Last benchmark ALU EX cycle  : %0d",
                     last_alu_ex_cycle);

            $display("ALU benchmark span           : %0d cycles",
                     last_alu_ex_cycle - first_alu_ex_cycle + 1);

            $display("Measured ALU instructions/cycle : %0f",
                     $itor(vector_alu_ex_count) /
                     $itor(last_alu_ex_cycle - first_alu_ex_cycle + 1));

            $display("Measured vector elements/cycle  : %0f",
                     ($itor(vector_alu_ex_count) * $itor(LANES)) /
                     $itor(last_alu_ex_cycle - first_alu_ex_cycle + 1));
        end
        else begin
            $display("ALU benchmark span : NOT MEASURED");
        end

        if (alu_latency_count > 0) begin
            $display("Measured average EX->WB latency : %0f cycles",
                     $itor(alu_latency_sum) /
                     $itor(alu_latency_count));
        end
        else begin
            $display("Measured EX->WB latency : NOT MEASURED");
        end

        $display("");
        $display("--- LSU Performance ---");
        $display("LSU issue count          : %0d", lsu_issue_count);
        $display("LSU done count           : %0d", lsu_done_count);
        $display("LSU busy cycles          : %0d", lsu_busy_cycles);
        $display("Pipeline stall cycles    : %0d", stall_cycles);

        for (i = 0; i < lsu_done_count && i < 8; i = i + 1) begin
            $display("LSU[%0d] issue=%0d done=%0d latency=%0d cycles",
                     i,
                     lsu_issue_cycle[i],
                     lsu_done_cycle[i],
                     lsu_latency[i]);
        end

        $display("");
        $display("--- Overall Run ---");

        if (finished)
            $display("Final VADD(v17) WB cycle : %0d", finish_cycle);
        else
            $display("WARNING: final VADD(v17) did not reach WB");

        $display("Total measured cycles    : %0d", total_cycles);

        if (total_cycles > 0)
            $display("Overall vector instr/cycle : %0f",
                     $itor(vector_wb_count) / $itor(total_cycles));

        $display("");
        $display("--- Architectural Results ---");

        $write("v4 :");
        for (i = 0; i < LANES; i = i + 1)
            $write(" %0d",
                   $signed(dut.m_v_regfile.vrf[4][i*SEW +: SEW]));
        $display("");

        $write("v16:");
        for (i = 0; i < LANES; i = i + 1)
            $write(" %0d",
                   $signed(dut.m_v_regfile.vrf[16][i*SEW +: SEW]));
        $display("");

        $write("v17:");
        for (i = 0; i < LANES; i = i + 1)
            $write(" %0d",
                   $signed(dut.m_v_regfile.vrf[17][i*SEW +: SEW]));
        $display("");

        $display("");
        $display("Expected v4/v16 : 11 12 13 14 15 16 17 18");
        $display("Expected v17    : 21 22 23 24 25 26 27 28");

        $display("");
        $display("--- Peak Architectural Throughput ---");
        $display("Peak VALU elements/cycle : %0d", LANES);
        $display("Peak VALU bits/cycle     : %0d", VLEN);

        $display("");
        $display("NOTE:");
        $display("  These throughput/latency values are simulation measurements.");
        $display("  LUTs, flip-flops, gates, area and Fmax require synthesis.");
        $display("================================================================");

        $finish;
    end

    // ------------------------------------------------------------------------
    // Waveform
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("wave_standalone_perf.vcd");
        $dumpvars(0, tb_vector_pipeline_standalone_perf);
    end

    // ------------------------------------------------------------------------
    // Watchdog
    // ------------------------------------------------------------------------
    initial begin
        #10000;
        $display("[ERROR] standalone performance TB watchdog timeout");
        $finish;
    end

endmodule
