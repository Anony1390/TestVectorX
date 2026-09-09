// vector_decoder.sv
// Combinational vector-instruction decode. Lives in the scalar core's
// ID stage, running in parallel with the existing scalar `Control`
// module. Splits vector ALU/LSU instructions (custom-2) from vector
// config instructions (custom-3); everything else is "not a vector
// instruction" and the scalar decoder drives the pipeline as before.
import vector_pkg::*;
import vector_isa_pkg::*;

module vector_decoder (
    input  logic [31:0]        instruction,

    output logic                is_vector,   // custom-2 (ALU/LSU)
    output logic                is_vcfg,     // custom-3 (config)

    output logic                regwrite,
    output vector_opcode_t      vop,
    output logic [4:0]          vrd,
    output logic [4:0]          vrs1,
    output logic [4:0]          vrs2,
    output vector_mem_mode_t    mode,
    output logic [31:0]         imm_ext,     // sign-extended stride imm

    output logic                lsu_en,
    output logic                memtoreg,
    output logic                mem_read,
    output logic                mem_write,

    output logic                cfg_write,
    output logic                cfg_sel_sew,
    output logic [31:0]         cfg_data
);

    logic [6:0] opcode;
    assign opcode = instruction[6:0];

    assign is_vector = (opcode == VEC_OP);
    assign is_vcfg   = (opcode == VCFG_OP);

    assign vop     = vector_opcode_t'(instruction[31:28]);
    assign vrd     = instruction[27:23];
    assign vrs1    = instruction[22:18];
    assign vrs2    = instruction[17:13];
    assign mode    = vector_mem_mode_t'(instruction[12:11]);
    assign imm_ext = {{28{instruction[10]}}, instruction[10:7]};

    assign cfg_sel_sew = instruction[11];
    assign cfg_data    = {{12{instruction[31]}}, instruction[31:12]};

    always_comb begin
        regwrite  = 1'b0;
        lsu_en    = 1'b0;
        memtoreg  = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        cfg_write = 1'b0;

        if (is_vector) begin
            unique case (vop)
                VADD, VSUB, VAND, VOR, VXOR, VSLL, VSRL, VSRA,
                VMIN, VMAX, VMINU, VMAXU: begin
                    regwrite = 1'b1;
                    memtoreg = 1'b0;
                end
                VLOAD: begin
                    regwrite = 1'b1;
                    lsu_en   = 1'b1;
                    mem_read = 1'b1;
                    memtoreg = 1'b1;
                end
                VSTORE: begin
                    lsu_en    = 1'b1;
                    mem_write = 1'b1;
                end
                default: ; // treat as NOP
            endcase
        end
        else if (is_vcfg) begin
            cfg_write = 1'b1;
        end
    end

endmodule
