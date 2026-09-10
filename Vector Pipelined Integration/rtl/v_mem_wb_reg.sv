import vector_pkg::*;

module v_mem_wb_reg (
    input  logic             clk,
    input  logic             rst,

    input  logic             valid_i,
    input  logic             regwrite_i,
    input  logic             lsu_en_i,
    input  logic             lsu_done_i,

    input  logic [4:0]       vrd_i,
    input  logic [VLEN-1:0]  write_data_i,

    output logic             valid_o,
    output logic             regwrite_o,
    output logic [4:0]       vrd_o,
    output logic [VLEN-1:0]  write_data_o
);

    logic commit;

    always_comb begin
        commit = valid_i &&
                 regwrite_i &&
                 (!lsu_en_i || lsu_done_i);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_o     <= 1'b0;
            regwrite_o  <= 1'b0;
            vrd_o       <= 5'd0;
            write_data_o <= '0;
        end
        else begin
            valid_o     <= valid_i;
            regwrite_o  <= commit;
            vrd_o       <= commit ? vrd_i : 5'd0;
            write_data_o <= write_data_i;
        end
    end

endmodule