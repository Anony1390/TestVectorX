module ImmGen#(parameter Width = 32) (
    input [Width-1:0] inst,
    output reg signed [Width-1:0] imm
);
    // ImmGen generate imm value based on opcode

    wire [6:0] opcode = inst[6:0];
    always @(*) 
    begin
        case(opcode)

            7'b0000011: begin // lw : I 
                imm = {{20{inst[31]}}, inst[31:20]};
            end
            7'b0010011: begin // I
                imm = {{20{inst[31]}}, inst[31:20]};
            end
            7'b0100011: begin // sw : S
                imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            end
            7'b1100011: begin // branch : SB
                imm = {{20{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8]};
            end
            7'b1100111: begin // jalr : I 
                imm = {{20{inst[31]}}, inst[31:20]};
            end
            7'b1101111: begin // jal : UJ 
                imm = {{12{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21]};
            end
	    // sign extended extraction of immediate bits
	endcase
    end
           
endmodule

