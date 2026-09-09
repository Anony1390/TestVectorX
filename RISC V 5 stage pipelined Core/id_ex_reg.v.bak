module id_ex_reg(
    input rst,
    input clk,
    input flush_id_ex,

    // to WB stage
    input regWrite_i,
    input memtoReg_i,

    // to MEM stage
    input memWrite_i,
    input memRead_i,

    // to EX stage
    input ALUSrc_i,
    input [3:0] ALUCtl_i,   // Corrected to 4-bit as per output
    input jal_i,            // Added
    input jalr_i,           // Added

    // data signals from ID stage
    input [31:0] pc_i,
    input [31:0] pcplus4_i, // Added
    input [31:0] rdata1_i,
    input [31:0] rdata2_i,
    input [31:0] imm_i,

    // identifiers
    input [4:0] rd_i,
    input [4:0] rs1_i,
    input [4:0] rs2_i,
    
    // outputs to EX stage
    output reg regWrite_o,
    output reg memtoReg_o,
    output reg memWrite_o,
    output reg memRead_o,
    output reg ALUSrc_o,
    output reg [3:0] ALUCtl_o,
    output reg jal_o,       // Added
    output reg jalr_o,      // Added
    output reg [31:0] pc_o,
    output reg [31:0] pcplus4_o, // Added
    output reg [31:0] rdata1_o,
    output reg [31:0] rdata2_o,
    output reg [31:0] imm_o,
    output reg [4:0] rd_o,
    output reg [4:0] rs1_o,
    output reg [4:0] rs2_o
);

always @(posedge clk) begin
    if (~rst) begin
        // Reset all signals to 0
        regWrite_o      <= 1'b0;
        memtoReg_o      <= 1'b0;
        memWrite_o      <= 1'b0;
        memRead_o       <= 1'b0;
        ALUSrc_o        <= 1'b0;
        ALUCtl_o        <= 4'b0000;
        jal_o           <= 1'b0;
        jalr_o          <= 1'b0;
        pc_o            <= 32'b0;
        pcplus4_o       <= 32'b0;
        rdata1_o        <= 32'b0;
        rdata2_o        <= 32'b0;
        imm_o           <= 32'b0;
        rd_o            <= 5'b00000;
        rs1_o           <= 5'b00000;
        rs2_o           <= 5'b00000;
    end
    else if (flush_id_ex) begin
        // Flush: Clear control signals to prevent state changes (NOP)
        regWrite_o      <= 1'b0;
        memWrite_o      <= 1'b0;
        memRead_o       <= 1'b0;
        jal_o           <= 1'b0;
        jalr_o          <= 1'b0;
        // Data signals don't strictly need to be cleared, but it's cleaner
        ALUSrc_o        <= 1'b0;
        ALUCtl_o        <= 4'b0000;
        rd_o            <= 5'b00000;
    end
    else begin
        // Normal pipeline operation
        regWrite_o      <= regWrite_i;
        memtoReg_o      <= memtoReg_i;
        memWrite_o      <= memWrite_i;
        memRead_o       <= memRead_i;
        ALUSrc_o        <= ALUSrc_i;
        ALUCtl_o        <= ALUCtl_i;
        jal_o           <= jal_i;
        jalr_o          <= jalr_i;
        pc_o            <= pc_i;
        pcplus4_o       <= pcplus4_i;
        rdata1_o        <= rdata1_i;
        rdata2_o        <= rdata2_i;
        imm_o           <= imm_i;
        rd_o            <= rd_i;
        rs1_o           <= rs1_i;
        rs2_o           <= rs2_i;
    end
end

endmodule