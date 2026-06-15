module imm_extend (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    wire [6:0] opcode = instr[6:0];

    always @(*) begin
        case (opcode)
            // I-type: ALU-immediate (ADDI/SLTI/…), loads, JALR
            7'b0010011,
            7'b0000011,
            7'b1100111: imm = {{20{instr[31]}}, instr[31:20]};

            // S-type: stores (SW/SH/SB)
            7'b0100011: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            // B-type: branches (BEQ/BNE/BLT/BGE/…)
            //   imm = { sign×19, [31], [7], [30:25], [11:8], 0 }
            7'b1100011: imm = {{19{instr[31]}},
                                instr[31],
                                instr[7],
                                instr[30:25],
                                instr[11:8],
                                1'b0};

            // U-type: LUI / AUIPC  (immediate already in upper 20 bits)
            7'b0110111,
            7'b0010111: imm = {instr[31:12], 12'b0};

            // J-type: JAL
            //   imm = { sign×11, [31], [19:12], [20], [30:21], 0 }
            7'b1101111: imm = {{11{instr[31]}},
                                instr[31],
                                instr[19:12],
                                instr[20],
                                instr[30:21],
                                1'b0};

            // R-type and anything else: no immediate
            default: imm = 32'b0;
        endcase
    end
endmodule