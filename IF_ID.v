module IF_ID (
    input        iClk,
    input        iRstN,
    input        iFlush,
    input        iStall,
    input [31:0] iPC,
    input [31:0] iInstr,
    output reg [31:0] oPC,
    output reg [31:0] oInstr
);

    always @(posedge iClk or negedge iRstN) begin
    //active low asynchronous reset
        if (!iRstN) begin 
            oPC    <= 32'b0;
            oInstr <= 32'b0;
            
     //Flush to take priority over stall 
        end else if (iFlush) begin
            oPC    <= 32'b0;
            oInstr <= 32'b0;
            
     //Stall signal will be 1 or 0
     //if iStall is 1, normal operation, IF_ID updates with new PC and new Instruction
     //if iStall is 0, IF_ID ignores the clock edge and holds what it currently has
     //Will only update when not stalling
        end else if (!iStall) begin
            oPC    <= iPC;
            oInstr <= iInstr;
        end
    end
    

endmodule
