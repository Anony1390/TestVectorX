// vector_alu.sv (VALU)
// Unmodified copy of "Vector Simulation/vector_alu.sv" — combinational,
// lane-parallel, 1 cycle latency. Reused as-is as the vector EX stage.
import vector_pkg::*;

module VALU (
    input  vector_opcode_t             op,
    input  logic [VLEN-1:0]            vs1, // Vector Source 1
    input  logic [VLEN-1:0]            vs2, // Vector Source 2
    input  logic [$clog2(LANES+1)-1:0] vl,
    output logic [VLEN-1:0]            vd   // Vector Destination
);

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : alu_lanes
            wire [SEW-1:0] vs1_lane = vs1[(i+1)*SEW-1 : i*SEW];
            wire [SEW-1:0] vs2_lane = vs2[(i+1)*SEW-1 : i*SEW];

            // Pulled out of the always_comb below as a plain continuous
            // assign: Icarus's support for constant part-selects inside
            // always_* processes is incomplete ("sorry: constant
            // selects in always_* processes are not fully supported")
            // and it falls back to sensitizing the whole vs2_lane bus.
            // Slicing here instead avoids the warning; behavior is
            // identical either way.
            wire [$clog2(SEW)-1:0] shamt = vs2_lane[$clog2(SEW)-1:0];

            logic [SEW-1:0] vd_lane;

            logic lane_active;
            assign lane_active = (i < vl);

            always_comb begin
                if (lane_active) begin
                    case (op)
                        VADD:    vd_lane = vs1_lane + vs2_lane;
                        VSUB:    vd_lane = vs1_lane - vs2_lane;
                        VAND:    vd_lane = vs1_lane & vs2_lane;
                        VOR:     vd_lane = vs1_lane | vs2_lane;
                        VXOR:    vd_lane = vs1_lane ^ vs2_lane;
                        VSLL:    vd_lane = vs1_lane << shamt;
                        VSRL:    vd_lane = vs1_lane >> shamt;
                        VSRA:    vd_lane = $signed(vs1_lane) >>> shamt;
                        VMIN:    vd_lane = ($signed(vs1_lane) < $signed(vs2_lane)) ? vs1_lane : vs2_lane;
                        VMAX:    vd_lane = ($signed(vs1_lane) > $signed(vs2_lane)) ? vs1_lane : vs2_lane;
                        VMINU:   vd_lane = (vs1_lane < vs2_lane) ? vs1_lane : vs2_lane;
                        VMAXU:   vd_lane = (vs1_lane > vs2_lane) ? vs1_lane : vs2_lane;
                        default: vd_lane = 0;
                    endcase
                end else vd_lane = '0;
            end

            assign vd[(i+1)*SEW-1 : i*SEW] = vd_lane;
        end
    endgenerate

endmodule
