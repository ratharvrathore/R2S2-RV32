module reg_file #(
    parameter REORDER_TAG_BITS = 3
) (
    input wire clk, reset,

    input wire [4:0] rs1, rs2, rdDecode,
    input wire floatDecode,
    input wire regWriteDecode,
    input wire fetchNext,
    input wire [REORDER_TAG_BITS-1:0] nextTag,
    output wire [31:0] dataRs1, dataRs2,
    output wire [REORDER_TAG_BITS-1:0] tag1, tag2,
    output wire available1, available2,

    input wire [4:0] rdROB,
    input wire floatROB,
    input wire regWriteROB,
    input wire wBNext,
    input wire [31:0] dataInROB
);
    reg [31:0] regFile [0:63];
    reg [63:0] valid;
    reg [REORDER_TAG_BITS-1:0] tag;

    assign dataRs1 = regFile[{floatDecode, rs1}];
    assign available1 = valid[{floatDecode, rs1}];
    assign tag1 = tag[{floatDecode, rs1}];
    assign dataRs2 = regFile[{floatDecode, rs2}];
    assign available2 = valid[{floatDecode, rs2}];
    assign tag2 = tag[{floatDecode, rs2}];

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            regFile <= 0;
            valid <= 1;
        end else begin
            if (regWriteROB) begin
                regFile[rdROB] <= dataInROB;
                valid[rdROB] <= 1;
            end
        end
    end
    always @(posedge clk) begin
        if (regWriteDecode) begin
            tag[rdDecode] <= nextTag;
            valid[rdDecode] <= 0;
        end
    end
endmodule