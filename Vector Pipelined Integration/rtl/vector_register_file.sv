// vector_register_file.sv  (FIXED)
// Same structure as before (32 x VLEN-bit registers, sync write /
// comb read, v0 hardwired to zero), with ONE addition: a same-cycle
// write-through bypass on the read port.
//
// Root cause this fixes: a consuming instruction whose ID-stage read
// of this file lands on the *exact* clock edge a producing
// instruction's WB-stage write commits (e.g. the instruction right
// after a multi-cycle VLOAD, which was frozen in ID for the whole
// stall and gets released the same cycle the load's write is
// scheduled) reads the PRE-write value. That's ordinary nonblocking-
// assignment semantics: the write NBA and the ID/EX capture NBA both
// evaluate off pre-edge state, so without a bypass the consumer
// always loses that race, regardless of how the EX-stage forwarding
// mux (vector_forwarding_unit) is tuned -- forwarding can only fix
// operands that haven't been latched yet; here they already have.
//
// The bypass below makes the read port itself hazard-free for any
// same-cycle write, independent of pipeline depth or stall timing,
// which is the standard/robust way to close this class of bug.
import vector_pkg::*;

module vector_register_file (
    input  logic clk,
    input  logic rst,

    input  logic [4:0]      addr1,
    input  logic [4:0]      addr2,
    output logic [VLEN-1:0] rd1,
    output logic [VLEN-1:0] rd2,

    input  logic [4:0]      addr3,
    input  logic [VLEN-1:0] wr_data,
    input  logic            regwrite
);

    logic [VLEN-1:0] vrf [MAX_VREG-1:0];

    always_ff @(posedge clk) begin : Write
        if (rst) begin
            for (int i = 0; i < MAX_VREG; i++)
                vrf[i] <= '0;
        end
        else if (regwrite)
            vrf[addr3] <= wr_data;
    end

    // Asynchronous read, v0 hardwired to zero, with a same-cycle
    // write-through bypass: if this cycle's write target is the same
    // register being read, forward wr_data instead of the (not-yet-
    // updated) array contents.
    always_comb begin : Read
        if (addr1 == 5'd0)
            rd1 = '0;
        else if (regwrite && addr3 == addr1)
            rd1 = wr_data;
        else
            rd1 = vrf[addr1];

        if (addr2 == 5'd0)
            rd2 = '0;
        else if (regwrite && addr3 == addr2)
            rd2 = wr_data;
        else
            rd2 = vrf[addr2];
    end

endmodule