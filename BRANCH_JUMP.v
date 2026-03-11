module BRANCH_JUMP (
    input        iBranch,
    input        iJump,
    input        iZero,
    input [31:0] iOffset,
    input [31:0] iPc,
    input [31:0] iRs1,
    input        iPcSrc,
    output [31:0] oPc
);

    reg [31:0] pc_next;

    always @(*) begin
        if (iJump) begin
            if (iPcSrc)
                // JALR: (rs1 + offset) with LSB cleared
                pc_next = (iRs1 + iOffset) & 32'hFFFFFFFE;
            else
                // JAL: PC + offset
                pc_next = iPc + iOffset;
        end
        else if (iBranch && iZero) begin
            // Taken branch
            pc_next = iPc + iOffset;
        end
        else begin
            // Default: next sequential instruction
            pc_next = iPc + 32'd4;
        end
    end

    assign oPc = pc_next;

endmodule