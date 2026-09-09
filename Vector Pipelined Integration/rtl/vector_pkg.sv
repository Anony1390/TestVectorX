// vector_pkg.sv
// Core vector datapath parameters + enums.
// (Same as "Vector Simulation/vector_pkg.sv" in the repo - copied here
//  unmodified so this integration package compiles standalone.)
package vector_pkg;
    localparam int VLEN     = 256;
    localparam int SEW      = 32;
    localparam int ELEN     = SEW;       // element width (alias for SEW)
    localparam int LANES    = 8;
    localparam int MAX_VREG = 32;

    // Memory access modes for LSU
    typedef enum logic [1:0] {
        UNIT_STRIDE,   // consecutive elements
        STRIDE,        // fixed stride between elements
        INDEX          // indexed (scatter/gather)
    } vector_mem_mode_t;

    // Vector opcodes
    typedef enum logic [3:0] {
        VADD,
        VSUB,
        VAND,
        VOR,
        VXOR,
        VSLL,
        VSRL,
        VSRA,
        VMIN,
        VMAX,
        VMINU,
        VMAXU,
        VLOAD,
        VSTORE
    } vector_opcode_t;
endpackage
