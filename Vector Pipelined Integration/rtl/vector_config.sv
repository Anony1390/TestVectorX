// vector_config.sv
// Unmodified copy of "Vector Simulation/vector_config.sv".
// Holds the architectural vl/sew CSRs, written by vsetvl/vsetsew
// (custom-3) instructions decoded in the ID stage.
import vector_pkg::*;

module vector_config (
    input  logic clk,
    input  logic rst,
    input  logic cfg_write,
    input  logic [31:0] cfg_data,
    input  logic cfg_sel_vl,
    input  logic cfg_sel_sew,
    output logic [31:0] vl,
    output logic [31:0] sew,
    output logic [31:0] epv,
    output logic [LANES-1:0] lane_active
);

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        vl  <= VLEN / SEW;
        sew <= SEW;
    end
    else if (cfg_write) begin
        if (cfg_sel_vl)
            vl <= cfg_data;
        if (cfg_sel_sew)
            sew <= cfg_data;
    end
end

assign epv = VLEN / sew;

integer i;
always_comb begin
    for (i = 0; i < LANES; i++) begin
        if (i < vl) lane_active[i] = 1;
        else        lane_active[i] = 0;
    end
end

endmodule
