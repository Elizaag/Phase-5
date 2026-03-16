// iverilog -o riscv_sim RISCV_TOP.v MUX_2_1.v MUX_3_1.v ALU_CONTROL.v ALU.v REGISTER.v DATA_MEMORY.v INSTRUCTION_MEMORY.v DECODER.v CONTROL.v BRANCH_JUMP.v IF_ID.v ID_EX.v EX_MEM.v MEM_WB.v FORWARDING_UNIT.v HAZARD_DETECTION.v

module RISCV_TOP (
    input iClk,
    input iRstN
);

    // ==========================================================
    // Hazard / stall control wires
    // ==========================================================
    wire       pcWrite;
    wire       if_id_write;
    wire       id_ex_flush;

    // Branch/jump flush (flush IF/ID and ID/EX when branch/jump taken)
    wire       branch_flush;

    // ==========================================================
    // Program Counter
    // ==========================================================
    reg  [31:0] wPC;
    wire [31:0] wNextPC;
    wire [31:0] pc_plus4;

    assign pc_plus4 = wPC + 32'd4;

    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN)
            wPC <= 32'd0;
        else if (pcWrite)          // stall PC if hazard detected
            wPC <= wNextPC;
    end

    // ==========================================================
    // IF Stage: Instruction Fetch
    // ==========================================================
    wire [31:0] wInstr;

    INSTRUCTION_MEMORY imem (
        .iRdAddr(wPC),
        .oInstr(wInstr)
    );

    // ==========================================================
    // IF/ID Pipeline Register
    // ==========================================================
    wire [31:0] if_id_pc;
    wire [31:0] if_id_instr;

    IF_ID if_id_reg (
        .iClk(iClk),
        .iRstN(iRstN),
        .iFlush(branch_flush),
        .iStall(!if_id_write),     // active-low write enable → active-high stall
        .iPC(wPC),
        .iInstr(wInstr),
        .oPC(if_id_pc),
        .oInstr(if_id_instr)
    );

    // ==========================================================
    // ID Stage: Decode
    // ==========================================================
    wire [6:0]  id_opcode;
    wire [4:0]  id_rd, id_rs1_pre, id_rs1, id_rs2;
    wire [2:0]  id_funct3;
    wire [6:0]  id_funct7;
    wire [31:0] id_imm;

    DECODER decoder (
        .iInstr(if_id_instr),
        .oOpcode(id_opcode),
        .oRd(id_rd),
        .oFunct3(id_funct3),
        .oRs1(id_rs1_pre),
        .oRs2(id_rs2),
        .oFunct7(id_funct7),
        .oImm(id_imm)
    );

    assign id_rs1 = (id_lui) ? 5'b0 : id_rs1_pre;

    // ==========================================================
    // ID Stage: Control
    // ==========================================================
    wire        id_lui, id_pcSrc, id_memRd, id_memWr;
    wire        id_memtoReg, id_aluSrc1, id_aluSrc2;
    wire        id_regWrite, id_branch, id_jump;
    wire [2:0]  id_aluOp;
    wire        id_falseRs1, id_falseRs2; // for hazard detection (true if instruction doesn't actually use the register)

    CONTROL control (
        .iOpcode(id_opcode),
        .oLui(id_lui),
        .oPcSrc(id_pcSrc),
        .oMemRd(id_memRd),
        .oMemWr(id_memWr),
        .oAluOp(id_aluOp),
        .oMemtoReg(id_memtoReg),
        .oAluSrc1(id_aluSrc1),
        .oAluSrc2(id_aluSrc2),
        .oRegWrite(id_regWrite),
        .oBranch(id_branch),
        .oJump(id_jump),
        .oFalseRs1(id_falseRs1),
        .oFalseRs2(id_falseRs2)
    );

    // ==========================================================
    // ID Stage: Register File
    // (Write port comes from MEM/WB stage below)
    // ==========================================================
    wire [31:0] id_rs1Data, id_rs2Data;

    // MEM/WB writeback wires (declared here, driven later)
    wire        mem_wb_regWrite;
    wire [4:0]  mem_wb_rd;
    wire [31:0] wb_to_reg;

    REGISTER register (
        .iClk(iClk),
        .iRstN(iRstN),
        .iWriteEn(mem_wb_regWrite),
        .iRdAddr(mem_wb_rd),
        .iRs1Addr(id_rs1),
        .iRs2Addr(id_rs2),
        .iWriteData(wb_to_reg),
        .oRs1Data(id_rs1Data),
        .oRs2Data(id_rs2Data)
    );

    // ==========================================================
    // Hazard Detection Unit
    // ==========================================================
    wire       id_ex_memRd_fwd, id_memWr_fwd;   // from ID/EX (declared after ID/EX reg below)
    wire [4:0] id_ex_rd_fwd;

    HAZARD_DETECTION hazard_detect (
        .iID_EX_MemRd(id_ex_memRd_fwd),
        .iID_EX_MemWr(id_memWr_fwd),
        .iID_EX_Rd(id_ex_rd_fwd),
        .iIF_ID_Rs1(id_rs1),
        .iIF_ID_Rs2(id_rs2),
        .iFalseRs1(id_falseRs1),
        .iFalseRs2(id_falseRs2),
        .oPCWrite(pcWrite),
        .oIF_IDWrite(if_id_write),
        .oID_EX_Flush(id_ex_flush)
    );

    // ==========================================================
    // ID/EX Pipeline Register
    // ==========================================================
    wire        id_ex_lui, id_ex_pcSrc, id_ex_memRd, id_ex_memWr;
    wire        id_ex_memtoReg, id_ex_aluSrc1, id_ex_aluSrc2;
    wire        id_ex_regWrite, id_ex_branch, id_ex_jump;
    wire [2:0]  id_ex_aluOp;
    wire [31:0] id_ex_pc, id_ex_rs1Data, id_ex_rs2Data, id_ex_imm;
    wire [2:0]  id_ex_funct3;
    wire [6:0]  id_ex_funct7;
    wire [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;

    // connect hazard detection wires
    assign id_ex_memRd_fwd = id_ex_memRd;
    assign id_memWr_fwd = id_memWr;
    assign id_ex_rd_fwd    = id_ex_rd;

    ID_EX id_ex_reg (
        .iClk(iClk),
        .iRstN(iRstN),
        .iFlush(id_ex_flush | branch_flush),
        // control
        .iLui(id_lui),
        .iPcSrc(id_pcSrc),
        .iMemRd(id_memRd),
        .iMemWr(id_memWr),
        .iAluOp(id_aluOp),
        .iMemtoReg(id_memtoReg),
        .iAluSrc1(id_aluSrc1),
        .iAluSrc2(id_aluSrc2),
        .iRegWrite(id_regWrite),
        .iBranch(id_branch),
        .iJump(id_jump),
        // data
        .iPC(if_id_pc),
        .iRs1Data(id_rs1Data),
        .iRs2Data(id_rs2Data),
        .iImm(id_imm),
        .iFunct3(id_funct3),
        .iFunct7(id_funct7),
        .iRs1(id_rs1),
        .iRs2(id_rs2),
        .iRd(id_rd),
        // control out
        .oLui(id_ex_lui),
        .oPcSrc(id_ex_pcSrc),
        .oMemRd(id_ex_memRd),
        .oMemWr(id_ex_memWr),
        .oAluOp(id_ex_aluOp),
        .oMemtoReg(id_ex_memtoReg),
        .oAluSrc1(id_ex_aluSrc1),
        .oAluSrc2(id_ex_aluSrc2),
        .oRegWrite(id_ex_regWrite),
        .oBranch(id_ex_branch),
        .oJump(id_ex_jump),
        // data out
        .oPC(id_ex_pc),
        .oRs1Data(id_ex_rs1Data),
        .oRs2Data(id_ex_rs2Data),
        .oImm(id_ex_imm),
        .oFunct3(id_ex_funct3),
        .oFunct7(id_ex_funct7),
        .oRs1(id_ex_rs1),
        .oRs2(id_ex_rs2),
        .oRd(id_ex_rd)
    );

    // ==========================================================
    // EX Stage: Forwarding Unit
    // ==========================================================
    wire [1:0] forwardA, forwardB;
    wire       forwardM; // forwarding control signals for ALU inputs and MEM stage

    // EX/MEM and MEM/WB wires needed here (declared ahead, driven after)
    wire        ex_mem_regWrite;
    wire [4:0]  ex_mem_rd;
    // mem_wb_regWrite and mem_wb_rd already declared above

    FORWARDING_UNIT fwd_unit (
        .iID_EX_Rs1(id_ex_rs1),
        .iID_EX_Rs2(id_ex_rs2),
        .iEX_MEM_Rd(ex_mem_rd),
        .iEX_MEM_RegWrite(ex_mem_regWrite),
        .iEX_MEM_DataWrite(ex_mem_memWr), // for store instructions, we need to forward to the memory stage instead of the ALU
        .iMEM_WB_Rd(mem_wb_rd),
        .iMEM_WB_RegWrite(mem_wb_regWrite),
        .iEX_MEM_Rs2Addr(ex_mem_rs2),
        .iMEM_WB_DataRead(mem_wb_memtoReg), // for load instructions, we need to forward the loaded value from MEM/WB
        .oForwardA(forwardA),
        .oForwardB(forwardB),
        .oForwardM(forwardM)
    );

    // ==========================================================
    // EX Stage: ALU input muxes with forwarding
    // ==========================================================
    // MEM/WB writeback value (needed for MEM->EX forwarding)
    // wb_to_reg declared above, driven in WB section below

    // EX/MEM ALU result (needed for EX->EX forwarding)
    wire [31:0] ex_mem_aluOut;

    // ForwardA mux: selects between reg file, MEM/WB result, EX/MEM result
    wire [31:0] fwd_rs1;
    MUX_3_1 #(.WIDTH(32)) mux_fwdA (
        .iData0(id_ex_rs1Data),   // 2'b00 no forward
        .iData1(wb_to_reg),       // 2'b01 MEM->EX
        .iData2(ex_mem_aluOut),   // 2'b10 EX->EX
        .iSel(forwardA),
        .oData(fwd_rs1)
    );

    // ForwardB mux: selects between reg file, MEM/WB result, EX/MEM result
    wire [31:0] fwd_rs2;
    MUX_3_1 #(.WIDTH(32)) mux_fwdB (
        .iData0(id_ex_rs2Data),   // 2'b00 no forward
        .iData1(wb_to_reg),       // 2'b01 MEM->EX
        .iData2(ex_mem_aluOut),   // 2'b10 EX->EX
        .iSel(forwardB),
        .oData(fwd_rs2)
    );

    // AluSrc1: PC vs forwarded rs1
    wire [31:0] aluInA;
    MUX_2_1 #(.WIDTH(32)) muxA (
        .iData0(fwd_rs1),
        .iData1(id_ex_pc),
        .iSel(id_ex_aluSrc1),
        .oData(aluInA)
    );

    // AluSrc2: forwarded rs2 vs immediate
    wire [31:0] aluInB;
    MUX_2_1 #(.WIDTH(32)) muxB (
        .iData0(fwd_rs2),
        .iData1(id_ex_imm),
        .iSel(id_ex_aluSrc2),
        .oData(aluInB)
    );

    // ==========================================================
    // EX Stage: ALU Control + ALU
    // ==========================================================
    wire [3:0]  aluCtrl;

    ALU_CONTROL alu_control (
        .iAluOp(id_ex_aluOp),
        .iFunct3(id_ex_funct3),
        .iFunct7(id_ex_funct7),
        .oAluCtrl(aluCtrl)
    );

    wire [31:0] ex_aluOut;
    wire        ex_aluZero;

    ALU alu (
        .iDataA(aluInA),
        .iDataB(aluInB),
        .iAluCtrl(aluCtrl),
        .oData(ex_aluOut),
        .oZero(ex_aluZero)
    );

    // PC+4 in EX stage (for JAL/JALR writeback)
    wire [31:0] ex_pc_plus4;
    assign ex_pc_plus4 = id_ex_pc + 32'd4;

    // ==========================================================
    // Branch/Jump resolution (done in EX stage)
    // ==========================================================
    wire [31:0] ex_nextPC;

    BRANCH_JUMP branch_jump (
        .iBranch(id_ex_branch),
        .iJump(id_ex_jump),
        .iZero(ex_aluZero),
        .iOffset(id_ex_imm),
        .iPc(id_ex_pc),
        .iRs1(fwd_rs1),
        .iPcSrc(id_ex_pcSrc),
        .oPc(ex_nextPC)
    );

    // Flush on branch taken or jump
    assign branch_flush = (id_ex_branch & ex_aluZero) | id_ex_jump;

    // Next PC: branch/jump result or sequential
    assign wNextPC = branch_flush ? ex_nextPC : pc_plus4;

    // ==========================================================
    // EX/MEM Pipeline Register
    // ==========================================================
    wire        ex_mem_lui, ex_mem_memRd, ex_mem_memWr;
    wire        ex_mem_memtoReg, ex_mem_branch, ex_mem_jump, ex_mem_pcSrc;
    wire        ex_mem_aluZero;
    wire [31:0] ex_mem_rs2Data, ex_mem_imm, ex_mem_pcPlus4, ex_mem_pc;
    wire [2:0]  ex_mem_funct3;
    wire [4:0]  ex_mem_rs2;

    EX_MEM ex_mem_reg (
        .iClk(iClk),
        .iRstN(iRstN),
        .iFlush(1'b0),
        // control
        .iLui(id_ex_lui),
        .iMemRd(id_ex_memRd),
        .iMemWr(id_ex_memWr),
        .iMemtoReg(id_ex_memtoReg),
        .iRegWrite(id_ex_regWrite),
        .iBranch(id_ex_branch),
        .iJump(id_ex_jump),
        .iPcSrc(id_ex_pcSrc),
        // data
        .iAluOut(ex_aluOut),
        .iAluZero(ex_aluZero),
        .iRs2Data(fwd_rs2),
        .iImm(id_ex_imm),
        .iPcPlus4(ex_pc_plus4),
        .iPC(id_ex_pc),
        .iFunct3(id_ex_funct3),
        .iRd(id_ex_rd),
        .iRs2(id_ex_rs2),
        // control out
        .oLui(ex_mem_lui),
        .oMemRd(ex_mem_memRd),
        .oMemWr(ex_mem_memWr),
        .oMemtoReg(ex_mem_memtoReg),
        .oRegWrite(ex_mem_regWrite),
        .oBranch(ex_mem_branch),
        .oJump(ex_mem_jump),
        .oPcSrc(ex_mem_pcSrc),
        // data out
        .oAluOut(ex_mem_aluOut),
        .oAluZero(ex_mem_aluZero),
        .oRs2Data(ex_mem_rs2Data),
        .oImm(ex_mem_imm),
        .oPcPlus4(ex_mem_pcPlus4),
        .oPC(ex_mem_pc),
        .oFunct3(ex_mem_funct3),
        .oRd(ex_mem_rd),
        .oRs2(ex_mem_rs2)
    );

    // ==========================================================
    // MEM Stage: Data Memory
    // ==========================================================
    wire [31:0] mem_readData, ex_mem_fwd_data;

    assign ex_mem_fwd_data = (forwardM) ? mem_wb_memReadData : ex_mem_rs2Data;

    DATA_MEMORY data_memory (
        .iClk(iClk),
        .iRstN(iRstN),
        .iAddress(ex_mem_aluOut),
        .iWriteData(ex_mem_fwd_data),
        .iFunct3(ex_mem_funct3),
        .iMemWrite(ex_mem_memWr),
        .iMemRead(ex_mem_memRd),
        .oReadData(mem_readData)
    );

    // ==========================================================
    // MEM/WB Pipeline Register
    // ==========================================================
    wire        mem_wb_lui, mem_wb_memtoReg, mem_wb_jump;
    wire [31:0] mem_wb_memReadData, mem_wb_aluOut, mem_wb_imm, mem_wb_pcPlus4;

    MEM_WB mem_wb_reg (
        .iClk(iClk),
        .iRstN(iRstN),
        // control
        .iLui(ex_mem_lui),
        .iMemtoReg(ex_mem_memtoReg),
        .iRegWrite(ex_mem_regWrite),
        .iJump(ex_mem_jump),
        // data
        .iMemReadData(mem_readData),
        .iAluOut(ex_mem_aluOut),
        .iImm(ex_mem_imm),
        .iPcPlus4(ex_mem_pcPlus4),
        .iRd(ex_mem_rd),
        // control out
        .oLui(mem_wb_lui),
        .oMemtoReg(mem_wb_memtoReg),
        .oRegWrite(mem_wb_regWrite),
        .oJump(mem_wb_jump),
        // data out
        .oMemReadData(mem_wb_memReadData),
        .oAluOut(mem_wb_aluOut),
        .oImm(mem_wb_imm),
        .oPcPlus4(mem_wb_pcPlus4),
        .oRd(mem_wb_rd)
    );

    // ==========================================================
    // WB Stage: Writeback muxes
    // ==========================================================
    wire [31:0] wb_mux0_out, wb_final;

    // Select between ALU result and memory read data
    MUX_2_1 #(.WIDTH(32)) muxWB0 (
        .iData0(mem_wb_aluOut),
        .iData1(mem_wb_memReadData),
        .iSel(mem_wb_memtoReg),
        .oData(wb_mux0_out)
    );

    // Select LUI immediate
    MUX_2_1 #(.WIDTH(32)) muxWB1 (
        .iData0(wb_mux0_out),
        .iData1(mem_wb_imm),
        .iSel(mem_wb_lui),
        .oData(wb_final)
    );

    // Select PC+4 for JAL/JALR
    MUX_2_1 #(.WIDTH(32)) muxWB_JUMP (
        .iData0(wb_final),
        .iData1(mem_wb_pcPlus4),
        .iSel(mem_wb_jump),
        .oData(wb_to_reg)
    );

endmodule
