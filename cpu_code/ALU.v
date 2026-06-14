`include "divider.v"
`include "multiplier.v"
`include "fp_addsub.v"
`include "fpmult.v"
`include "fpdivision.v"
`include "fpToInt.v"
`include "intToFp.v"
module ALU #(
    parameter ALU_CONTROL_BITS = 6
) (
    input wire clk, reset,
    input wire [31:0] dataA, dataB,
    input wire [ALU_CONTROL_BITS-1:0] ALUControl,
    input wire pushNewALU,

    output wire busy, done,
    output wire [31:0] dataOut,
    output wire exceptionRaised
);

    localparam ADD  = 6'b0_0_1_000;
    localparam SUB  = 6'b0_0_1_001;
    localparam XOR  = 6'b0_0_0_000;
    localparam OR   = 6'b0_0_0_001;
    localparam AND  = 6'b0_0_0_010;
    localparam SLL  = 6'b0_0_0_100;
    localparam SRL  = 6'b0_0_0_101;
    localparam SRA  = 6'b0_1_0_000;
    localparam SLT  = 6'b0_0_1_111;
    localparam SLTU = 6'b1_0_1_111;
    localparam MUL  = 6'b0_0_1_010;
    localparam MULU = 6'b1_0_1_010;
    localparam MULH = 6'b0_0_1_011;
    localparam MULHU= 6'b1_0_1_011;
    localparam DIV  = 6'b0_0_1_100;
    localparam DIVU = 6'b1_0_1_100;
    localparam REM  = 6'b0_0_1_101;
    localparam REMU = 6'b1_0_1_101;
    localparam FADD = 6'b0_1_1_000;
    localparam FSUB = 6'b0_1_1_001;
    localparam FMUL = 6'b0_1_1_010;
    localparam FDIV = 6'b0_1_1_100;
    localparam FSLT = 6'b0_1_1_111;
    localparam FCTI = 6'b0_1_0_001;
    localparam ICTF = 6'b0_1_0_010;

    wire sOrU  = ALUControl[5];
    wire isFP  = ALUControl[4];
    wire isInt = ALUControl[3];

    wire isMult = !isFP && (ALUControl[2:0] == 3'b010 || ALUControl[2:0] == 3'b011);
    wire isDiv  = !isFP && (ALUControl[2:0] == 3'b100 || ALUControl[2:0] == 3'b101) && isInt;
    wire isFPMul= isFP  &&  ALUControl[2:0] == 3'b010;
    wire isFPDiv= isFP  &&  ALUControl[2:0] == 3'b100;
    wire isFPAdd= isFP  && (ALUControl[2:0] == 3'b000 || ALUControl[2:0] == 3'b001);
    wire isFastOp = !isMult && !isDiv && !isFPMul && !isFPDiv;

    assign multPushNewData = pushNewALU && isMult;
    assign divPushNewData  = pushNewALU && isDiv;
    assign fpPushNewMult   = pushNewALU && isFPMul;
    assign fpPushNewDiv    = pushNewALU && isFPDiv;

    assign multInA = dataA;
    assign multInB = dataB;
    assign divInA  = dataA;
    assign divInB  = dataB;

    wire [31:0] multInA, multInB, divInA, divInB, quoOut, remOut;
    wire [63:0] multOut;
    wire multBusy, multDone, multPushNewData, divBusy, divDone, divPushNewData, divException;

    multiplier multiplier_inst (
        .clk          (clk),
        .reset        (reset),
        .dataA        (multInA),
        .dataB        (multInB),
        .pushNewMult  (multPushNewData),
        .signed_mode  (sOrU),
        .dataOut      (multOut),
        .busy         (multBusy),
        .done         (multDone)
    );

    divider divider_inst (
        .clk            (clk),
        .reset          (reset),
        .dataA          (divInA),
        .dataB          (divInB),
        .pushNewDiv     (divPushNewData),
        .signed_mode    (sOrU),
        .quoOut         (quoOut),
        .remOut         (remOut),
        .busy           (divBusy),
        .done           (divDone),
        .exceptionRaised(divException)
    );

    wire is_sub         = (ALUControl == FSUB);
    wire fpAddException;
    wire [31:0] fpAddDataOut;

    fp_addsub fp_addsub_inst (
        .dataA          (dataA),
        .dataB          (dataB),
        .is_sub         (is_sub),
        .dataOut        (fpAddDataOut),
        .exceptionRaised(fpAddException)
    );

    wire fpSltRes = (dataA[31] > dataB[31]) ? 1'b1 :
                   (dataA[31] < dataB[31]) ? 1'b0 :
                   (dataA[30:0] > dataB[30:0]) ? dataA[31] : ~dataA[31];

    wire [31:0] fpMultOut;
    wire fpMultBusy, fpMultDone, fpPushNewMult;

    fpmult fpmult_inst (
        .clk        (clk),
        .reset      (reset),
        .dataA      (dataA),
        .dataB      (dataB),
        .pushNewMult(fpPushNewMult),
        .dataOut    (fpMultOut),
        .busy       (fpMultBusy),
        .done       (fpMultDone)
    );

    wire [31:0] fpDivOut;
    wire fpDivBusy, fpDivDone, fpPushNewDiv, fpDivException;

    fpdivision fpdivision_inst (
        .clk            (clk),
        .reset          (reset),
        .dataA          (dataA),
        .dataB          (dataB),
        .pushNewDiv     (fpPushNewDiv),
        .quoOut         (fpDivOut),
        .busy           (fpDivBusy),
        .done           (fpDivDone),
        .exceptionRaised(fpDivException)
    );

    wire [31:0] fpToIntOut;
    wire fpToIntException;

    fpToInt fpToInt_inst (
        .dataIn         (dataA),
        .dataOut        (fpToIntOut),
        .exceptionRaised(fpToIntException)
    );

    wire [31:0] intToFpOut;

    intToFp intToFp_inst (
        .dataIn (dataA),
        .dataOut(intToFpOut)
    );

    wire [31:0] addOut  = dataA + dataB;
    wire [31:0] subOut  = dataA - dataB;
    wire [31:0] xorOut  = dataA ^ dataB;
    wire [31:0] orOut   = dataA | dataB;
    wire [31:0] andOut  = dataA & dataB;
    wire [31:0] sllOut  = dataA << dataB[4:0];
    wire [31:0] srlOut  = dataA >> dataB[4:0];
    wire [31:0] sraOut  = $signed(dataA) >>> dataB[4:0];
    wire [31:0] sltOut  = {31'b0, $signed(dataA) < $signed(dataB)};
    wire [31:0] sltuOut = {31'b0, dataA < dataB};

    reg [31:0] fastResult;
    always @(*) begin
        case (ALUControl)
            ADD  : fastResult = addOut;
            SUB  : fastResult = subOut;
            XOR  : fastResult = xorOut;
            OR   : fastResult = orOut;
            AND  : fastResult = andOut;
            SLL  : fastResult = sllOut;
            SRL  : fastResult = srlOut;
            SRA  : fastResult = sraOut;
            SLT  : fastResult = sltOut;
            SLTU : fastResult = sltuOut;
            FADD : fastResult = fpAddDataOut;
            FSUB : fastResult = fpAddDataOut;   // is_sub already set
            FSLT : fastResult = {31'b0, fpSltRes};
            FCTI : fastResult = fpToIntOut;
            ICTF : fastResult = intToFpOut;
            default: fastResult = 32'b0;
        endcase
    end

    reg [31:0] slowResult;
    reg        slowException;
    always @(*) begin
        case (1'b1)
            isMult : begin
                slowResult    = ALUControl[2:0] == 3'b011 ? multOut[63:32] : multOut[31:0];
                slowException = 1'b0;
            end
            isDiv  : begin
                slowResult    = ALUControl[2:0] == 3'b101 ? remOut : quoOut;
                slowException = divException;
            end
            isFPMul: begin
                slowResult    = fpMultOut;
                slowException = 1'b0;
            end
            isFPDiv: begin
                slowResult    = fpDivOut;
                slowException = fpDivException;
            end
            default: begin
                slowResult    = 32'b0;
                slowException = 1'b0;
            end
        endcase
    end

    reg        fastDone_r;
    reg [31:0] fastResult_r;
    reg        fastException_r;
    reg        isFastOp_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fastDone_r      <= 1'b0;
            fastResult_r    <= 32'b0;
            fastException_r <= 1'b0;
            isFastOp_r      <= 1'b0;
        end else begin
            fastDone_r      <= pushNewALU && isFastOp;
            fastResult_r    <= fastResult;
            isFastOp_r      <= pushNewALU && isFastOp;
            // Capture combinational exceptions for fast FP ops
            fastException_r <= pushNewALU && isFastOp &&
                               ((isFPAdd && fpAddException) ||
                                (ALUControl == FCTI && fpToIntException));
        end
    end

    wire slowDone = (isMult  && multDone)  ||
                    (isDiv   && divDone)   ||
                    (isFPMul && fpMultDone)||
                    (isFPDiv && fpDivDone);

    assign busy = multBusy || divBusy || fpMultBusy || fpDivBusy;
    assign done = fastDone_r || slowDone;

    assign dataOut        = fastDone_r ? fastResult_r : slowResult;
    assign exceptionRaised = fastDone_r ? fastException_r : (slowDone && slowException);

endmodule