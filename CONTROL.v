module CONTROL (
    input  [6:0] iOpcode,
    output        oLui,
    output        oPcSrc,
    output        oMemRd,
    output        oMemWr,
    output [2:0]  oAluOp,
    output        oMemtoReg,
    output        oAluSrc1,
    output        oAluSrc2,
    output        oRegWrite,
    output        oBranch,
    output        oJump
);

    // Internal control registers
    reg        rLui;
    reg        rPcSrc;
    reg        rMemRd;
    reg        rMemWr;
    reg [2:0]  rAluOp;
    reg        rMemtoReg;
    reg        rAluSrc1;
    reg        rAluSrc2;
    reg        rRegWrite;
    reg        rBranch;
    reg        rJump;

    // Drive outputs
    assign oLui       = rLui;
    assign oPcSrc     = rPcSrc;
    assign oMemRd     = rMemRd;
    assign oMemWr     = rMemWr;
    assign oAluOp     = rAluOp;
    assign oMemtoReg  = rMemtoReg;
    assign oAluSrc1   = rAluSrc1;
    assign oAluSrc2   = rAluSrc2;
    assign oRegWrite  = rRegWrite;
    assign oBranch    = rBranch;
    assign oJump      = rJump;

    // Combinational control logic
    always @(*) begin
        // Defaults (safe / no-op)
        rLui       = 1'b0;
        rPcSrc     = 1'b0;
        rMemRd     = 1'b0;
        rMemWr     = 1'b0;
        rAluOp     = 3'b000;
        rMemtoReg  = 1'b0;
        rAluSrc1   = 1'b0;
        rAluSrc2   = 1'b0;
        rRegWrite  = 1'b0;
        rBranch    = 1'b0;
        rJump      = 1'b0;

        case (iOpcode)

            // R-type (register-register ALU ops)
            7'b0110011: begin
                rAluOp    = 3'b010;
                rRegWrite = 1'b1;
            end

            // I-type ALU (ADDI, etc.)
            7'b0010011: begin
                rAluOp    = 3'b011;
                rAluSrc2 = 1'b1;
                rRegWrite = 1'b1;
            end

            // Loads
            7'b0000011: begin
                rMemRd     = 1'b1;
                rMemtoReg = 1'b1;
                rAluSrc2  = 1'b1;
                rRegWrite = 1'b1;
                rAluOp    = 3'b000;
            end

            // Stores
            7'b0100011: begin
                rMemWr    = 1'b1;
                rAluSrc2 = 1'b1;
                rAluOp   = 3'b000;
            end

            // Branches
            7'b1100011: begin
                rBranch = 1'b1;
                rAluOp = 3'b001;
            end

            // JAL
            7'b1101111: begin
                rJump     = 1'b1;
                rRegWrite = 1'b1;
                rAluSrc1  = 1'b1;
                rAluSrc2  = 1'b1;
                rAluOp    = 3'b000;
            end

            // JALR
            7'b1100111: begin
                rJump     = 1'b1;
                rPcSrc   = 1'b1;
                rAluSrc2 = 1'b1;
                rRegWrite = 1'b1;
                rAluOp    = 3'b000;
            end

            // LUI
            7'b0110111: begin
                rLui      = 1'b1;
                rRegWrite = 1'b1;
                rAluOp    = 3'b000;
            end

            // AUIPC
            7'b0010111: begin
                rAluSrc1  = 1'b1;
                rAluSrc2  = 1'b1;
                rRegWrite = 1'b1;
                rAluOp    = 3'b000;
            end

            default: begin
                // unsupported opcode → no-op
            end
        endcase
    end

endmodule