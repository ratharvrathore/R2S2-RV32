`timescale 1ns/1ps
module tb_ALU ();

    reg clk, reset;
    reg [31:0] dataA, dataB;
    reg [5:0] ALUControl;
    reg pushNewALU;

    wire busy, done;
    wire [31:0] dataOut;
    wire exceptionRaised;

    ALU #(.ALU_CONTROL_BITS(6)) dut (
        clk, reset,
        dataA, dataB,
        ALUControl,
        pushNewALU,
        busy, done,
        dataOut,
        exceptionRaised
    );

    initial begin
        clk = 0;
        reset = 1;
        #13
        reset = 0;
    end

    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Tasks
    // ----------------------------------------------------------------

    task drive_alu;
        input [31:0] dataAInp, dataBInp;
        input [5:0]  ctrl;
        begin
            @(negedge clk);
            pushNewALU = 1;
            dataA      = dataAInp;
            dataB      = dataBInp;
            ALUControl = ctrl;
            @(posedge clk);
            @(negedge clk);
            pushNewALU = 0;
        end
    endtask

    task wait_done;
        begin
            @(negedge done);
        end
    endtask

    // ----------------------------------------------------------------
    // localparams mirrored from DUT for readability
    // ----------------------------------------------------------------
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

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        pushNewALU = 0;
        dataA      = 0;
        dataB      = 0;
        ALUControl = 0;
        #20;

        // ---- ADD ----
        drive_alu(32'd15,         32'd10,        ADD);  wait_done();
        drive_alu(32'hFFFFFFFF,   32'd1,         ADD);  wait_done();
        drive_alu(32'd0,          32'd0,         ADD);  wait_done();

        // ---- SUB ----
        drive_alu(32'd20,         32'd7,         SUB);  wait_done();
        drive_alu(32'd0,          32'd1,         SUB);  wait_done();
        drive_alu(32'd42,         32'd42,        SUB);  wait_done();

        // ---- XOR ----
        drive_alu(32'hA5A5A5A5,   32'h5A5A5A5A, XOR);  wait_done();
        drive_alu(32'hDEADBEEF,   32'hDEADBEEF, XOR);  wait_done();

        // ---- OR ----
        drive_alu(32'hF0F0F0F0,   32'h0F0F0F0F, OR);   wait_done();
        drive_alu(32'd0,          32'd0,         OR);   wait_done();

        // ---- AND ----
        drive_alu(32'hFFFFFFFF,   32'hA5A5A5A5, AND);  wait_done();
        drive_alu(32'hF0F0F0F0,   32'h0F0F0F0F, AND);  wait_done();

        // ---- SLL ----
        drive_alu(32'd1,          32'd4,         SLL);  wait_done();
        drive_alu(32'hFFFFFFFF,   32'd1,         SLL);  wait_done();

        // ---- SRL ----
        drive_alu(32'd16,         32'd4,         SRL);  wait_done();
        drive_alu(32'hFFFFFFFF,   32'd1,         SRL);  wait_done();

        // ---- SRA ----
        drive_alu(32'hFFFFFFFF,   32'd4,         SRA);  wait_done();
        drive_alu(32'd16,         32'd4,         SRA);  wait_done();

        // ---- SLT ----
        drive_alu(32'd5,          32'd10,        SLT);  wait_done();
        drive_alu(32'd10,         32'd5,         SLT);  wait_done();
        drive_alu(32'hFFFFFFFF,   32'd1,         SLT);  wait_done();

        // ---- SLTU ----
        drive_alu(32'd5,          32'd10,        SLTU); wait_done();
        drive_alu(32'hFFFFFFFF,   32'd1,         SLTU); wait_done();

        // ---- MUL (signed lower 32) ----
        drive_alu(32'd3,          32'd5,         MUL);  wait_done();
        drive_alu(32'd0,          32'd999,       MUL);  wait_done();
        drive_alu(32'd1000,       32'd1000,      MUL);  wait_done();
        drive_alu(32'hFFFFFFFF,   32'd2,         MUL);  wait_done();

        // ---- MULU (unsigned lower 32) ----
        drive_alu(32'hFFFFFFFF,   32'hFFFFFFFF,  MULU); wait_done();

        // ---- MULH (signed upper 32) ----
        drive_alu(32'hFFFFFFFF,   32'hFFFFFFFF,  MULH); wait_done();
        drive_alu(32'h80000000,   32'd2,         MULH); wait_done();

        // ---- MULHU (unsigned upper 32) ----
        drive_alu(32'hFFFFFFFF,   32'hFFFFFFFF,  MULHU);wait_done();

        // ---- DIV (signed) ----
        drive_alu(32'd20,         32'd4,         DIV);  wait_done();
        drive_alu(32'd7,          32'd2,         DIV);  wait_done();
        drive_alu(32'hFFFFFFEC,   32'd4,         DIV);  wait_done();

        // ---- DIVU (unsigned) ----
        drive_alu(32'hFFFFFFFF,   32'd2,         DIVU); wait_done();

        // ---- REM (signed) ----
        drive_alu(32'd7,          32'd3,         REM);  wait_done();
        drive_alu(32'hFFFFFFF9,   32'd3,         REM);  wait_done();

        // ---- REMU (unsigned) ----
        drive_alu(32'hFFFFFFFF,   32'd3,         REMU); wait_done();

        #30;
        $finish;
    end

    initial begin
        $dumpfile("tb_ALU.vcd");
        $dumpvars(0, tb_ALU);
    end

endmodule