module ex_mem_reg(
    input clk,
    input rst,

    //to WB stage
    input regWrite_i,
    input memtoReg_i,
    input jal_i,
    input jalr_i,

    //to MEM stage
    input memWrite_i,
    input memRead_i,

    //data signals from EX stage
    input [31:0] ALUResult_i,
    input [31:0] rdata2_i,
    input [4:0] rd_i,
    
    input [4:0] rs2_i,
    output reg [4:0] rs2_o,

    //outputs to MEM stage
    output reg regWrite_o,
    output reg memtoReg_o,
    output reg memWrite_o,
    output reg memRead_o,
    output reg [31:0] ALUResult_o,
    output reg [31:0] rdata2_o,
    output reg [4:0] rd_o,
    output reg jal_o,
    output reg jalr_o,
    input [31:0] pcplus4_i,
    output reg [31:0] pcplus4_o
);

always @(posedge clk) begin
    if (~rst) begin
        regWrite_o <= 0;
        memtoReg_o <= 0;
        memWrite_o <= 0;
        memRead_o <= 0;
        ALUResult_o <= 32'b0;
        rdata2_o <= 32'b0;
        rd_o <= 5'b0;
        jal_o <= 0;
        jalr_o <= 0;
        pcplus4_o <= 0;
        rs2_o <= 0;
    end
    else begin
        regWrite_o <= regWrite_i;
        memtoReg_o <= memtoReg_i;
        memWrite_o <= memWrite_i;
        memRead_o <= memRead_i;
        ALUResult_o <= ALUResult_i;
        rdata2_o <= rdata2_i;
        rd_o <= rd_i;
        jal_o <= jal_i;
        jalr_o <= jalr_i;
        pcplus4_o <= pcplus4_i;
        rs2_o <= rs2_i;
    end
end
endmodule