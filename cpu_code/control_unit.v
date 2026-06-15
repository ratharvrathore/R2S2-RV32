// =============================================================================
// control_unit.v
// RISC-V RV32I (+ M-extension) Control Unit
//
// Decodes the instruction sitting in the fetch→decode pipeline register
// and drives all control signals consumed by the scheduler, ROB, and
// register file in the out-of-order CPU.
//
// ALU Control encoding (ALU_CONTROL_BITS = 6):
//   [5:0]  ALUOp
//   0x00  ADD / ADDI / loads / stores / AUIPC / JAL / JALR
//   0x01  SUB
//   0x02  SLL / SLLI
//   0x03  SLT / SLTI
//   0x04  SLTU / SLTIU
//   0x05  XOR / XORI
//   0x06  SRL / SRLI
//   0x07  SRA / SRAI
//   0x08  OR  / ORI
//   0x09  AND / ANDI
//   0x0A  LUI   (pass B)
//   0x0B  MUL
//   0x0C  MULH
//   0x0D  MULHSU
//   0x0E  MULHU
//   0x0F  DIV
//   0x10  DIVU
//   0x11  REM
//   0x12  REMU
//   0x3F  ILLEGAL / NOP
//
// typeIn encoding (2-bit, matches ROB):
//   2'b10  EXE  (arithmetic / logical / lui / auipc)
//   2'b11  LOAD
//   2'b00  STORE
//   2'b01  JUMP  (jal, jalr, branches)
// =============================================================================

module control_unit #(
    parameter SCHEDULER_TAG_BITS = 4,
    parameter ALU_CONTROL_BITS   = 6
)(
    // Raw instruction word from the fetch/decode pipeline register
    input  wire [31:0] instr,

    // ── Register specifiers ──────────────────────────────────
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rdIn,          // destination register (to ROB / reg-file)

    // ── Fetch-stage control ──────────────────────────────────
    output wire        jumpCtrl,      // this instruction can change the PC
    output wire        float,         // FP instruction (uses FP reg-file)
    output wire        regWrite,      // instruction writes a destination register

    // ── Scheduler / ROB type ─────────────────────────────────
    output wire [1:0]  typeIn,        // 10=EXE 11=LOAD 00=STORE 01=JUMP

    // ── Scheduler control ────────────────────────────────────
    output wire        schMemEnIn,    // instruction accesses memory
    output wire        schMemWrEnIn,  // instruction writes memory (store)
    output wire        schJumpIn,     // instruction is a jump/branch
    output wire [ALU_CONTROL_BITS-1:0] schALUControlIn,

    // ── Immediate / data mux ─────────────────────────────────
    output wire        useImm,        // use sign-extended immediate as operand B

    // ── ROB memory-address hint (for stores, pre-computed base) ──
    // The actual effective address is computed by the ALU; this wire
    // carries the raw imm field so the ROB can track it if needed.
    output wire [31:0] robMemAddrIn,

    // ── Exception / illegal instruction ──────────────────────
    output wire        robExceptionIn
);

    // =========================================================================
    // Instruction field extraction
    // =========================================================================
    wire [6:0] opcode  = instr[6:0];
    wire [2:0] funct3  = instr[14:12];
    wire [6:0] funct7  = instr[31:25];
    wire [4:0] rd_f    = instr[11:7];
    wire [4:0] rs1_f   = instr[19:15];
    wire [4:0] rs2_f   = instr[24:20];

    assign rs1  = rs1_f;
    assign rs2  = rs2_f;
    assign rdIn = rd_f;

    // =========================================================================
    // Opcode constants
    // =========================================================================
    localparam OP_R      = 7'b0110011; // R-type  (ADD, SUB, …, MUL…)
    localparam OP_I      = 7'b0010011; // I-type  (ADDI, XORI, …)
    localparam OP_LOAD   = 7'b0000011; // Loads
    localparam OP_STORE  = 7'b0100011; // Stores
    localparam OP_BRANCH = 7'b1100011; // Branches
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_SYSTEM = 7'b1110011;
    // FP (RV32F/D) — decoded but flagged as float
    localparam OP_FP_LOAD  = 7'b0000111;
    localparam OP_FP_STORE = 7'b0100111;
    localparam OP_FP_OP    = 7'b1010011;
    localparam OP_FP_MADD  = 7'b1000011;
    localparam OP_FP_MSUB  = 7'b1000111;
    localparam OP_FP_NMADD = 7'b1001111;
    localparam OP_FP_NMSUB = 7'b1001011;

    // funct7 distinguishes ADD/SUB, SRL/SRA, and R vs M-extension
    localparam F7_BASE  = 7'b0000000;
    localparam F7_ALT   = 7'b0100000; // SUB / SRA / SRAI
    localparam F7_MEXT  = 7'b0000001; // RV32M

    // =========================================================================
    // Opcode group flags
    // =========================================================================
    wire is_r      = (opcode == OP_R);
    wire is_i      = (opcode == OP_I);
    wire is_load   = (opcode == OP_LOAD);
    wire is_store  = (opcode == OP_STORE);
    wire is_branch = (opcode == OP_BRANCH);
    wire is_jal    = (opcode == OP_JAL);
    wire is_jalr   = (opcode == OP_JALR);
    wire is_lui    = (opcode == OP_LUI);
    wire is_auipc  = (opcode == OP_AUIPC);
    wire is_system = (opcode == OP_SYSTEM);
    wire is_fp_ld  = (opcode == OP_FP_LOAD);
    wire is_fp_st  = (opcode == OP_FP_STORE);
    wire is_fp_op  = (opcode == OP_FP_OP);
    wire is_fp_ma  = (opcode == OP_FP_MADD)  | (opcode == OP_FP_MSUB) |
                     (opcode == OP_FP_NMADD) | (opcode == OP_FP_NMSUB);

    wire is_mext   = is_r && (funct7 == F7_MEXT);
    wire is_float  = is_fp_ld | is_fp_st | is_fp_op | is_fp_ma;

    // =========================================================================
    // ALU control
    // =========================================================================
    // R-type / M-extension
    reg [ALU_CONTROL_BITS-1:0] alu_r;
    always @(*) begin
        if (is_mext) begin
            case (funct3)
                3'h0: alu_r = 6'h0B; // MUL
                3'h1: alu_r = 6'h0C; // MULH
                3'h2: alu_r = 6'h0D; // MULHSU
                3'h3: alu_r = 6'h0E; // MULHU
                3'h4: alu_r = 6'h0F; // DIV
                3'h5: alu_r = 6'h10; // DIVU
                3'h6: alu_r = 6'h11; // REM
                3'h7: alu_r = 6'h12; // REMU
                default: alu_r = 6'h3F;
            endcase
        end else begin
            case (funct3)
                3'h0: alu_r = (funct7 == F7_ALT) ? 6'h01 : 6'h00; // SUB / ADD
                3'h1: alu_r = 6'h02; // SLL
                3'h2: alu_r = 6'h03; // SLT
                3'h3: alu_r = 6'h04; // SLTU
                3'h4: alu_r = 6'h05; // XOR
                3'h5: alu_r = (funct7 == F7_ALT) ? 6'h07 : 6'h06; // SRA / SRL
                3'h6: alu_r = 6'h08; // OR
                3'h7: alu_r = 6'h09; // AND
                default: alu_r = 6'h3F;
            endcase
        end
    end

    // I-type arithmetic
    reg [ALU_CONTROL_BITS-1:0] alu_i;
    always @(*) begin
        case (funct3)
            3'h0: alu_i = 6'h00; // ADDI
            3'h1: alu_i = 6'h02; // SLLI
            3'h2: alu_i = 6'h03; // SLTI
            3'h3: alu_i = 6'h04; // SLTIU
            3'h4: alu_i = 6'h05; // XORI
            3'h5: alu_i = (funct7 == F7_ALT) ? 6'h07 : 6'h06; // SRAI / SRLI
            3'h6: alu_i = 6'h08; // ORI
            3'h7: alu_i = 6'h09; // ANDI
            default: alu_i = 6'h3F;
        endcase
    end

    // Branch: ALU computes (rs1 op rs2); result used by ROB to resolve
    reg [ALU_CONTROL_BITS-1:0] alu_branch;
    always @(*) begin
        case (funct3)
            3'h0: alu_branch = 6'h01; // BEQ  → SUB, check zero
            3'h1: alu_branch = 6'h01; // BNE  → SUB, check non-zero
            3'h4: alu_branch = 6'h03; // BLT  → SLT
            3'h5: alu_branch = 6'h03; // BGE  → SLT, inverted
            3'h6: alu_branch = 6'h04; // BLTU → SLTU
            3'h7: alu_branch = 6'h04; // BGEU → SLTU, inverted
            default: alu_branch = 6'h3F;
        endcase
    end

    // Final ALU control mux
    reg [ALU_CONTROL_BITS-1:0] alu_ctrl;
    always @(*) begin
        case (1'b1)
            is_r:      alu_ctrl = alu_r;
            is_i:      alu_ctrl = alu_i;
            is_load:   alu_ctrl = 6'h00; // ADD  (base + imm)
            is_store:  alu_ctrl = 6'h00; // ADD  (base + imm)
            is_branch: alu_ctrl = alu_branch;
            is_jal:    alu_ctrl = 6'h00; // ALU computes PC+4 (saved as link)
            is_jalr:   alu_ctrl = 6'h00; // ALU computes rs1+imm (jump target)
            is_lui:    alu_ctrl = 6'h0A; // pass upper-imm through B port
            is_auipc:  alu_ctrl = 6'h00; // ADD  (PC + imm<<12)
            is_system: alu_ctrl = 6'h00; // ecall/ebreak treated as nop here
            is_float:  alu_ctrl = 6'h00; // FP handled externally
            default:   alu_ctrl = 6'h3F; // ILLEGAL
        endcase
    end

    assign schALUControlIn = alu_ctrl;

    // =========================================================================
    // useImm — operand-B comes from the sign-extended immediate
    // =========================================================================
    // R-type and branches use both rs1 and rs2 from the register file.
    // Everything else substitutes the immediate for operand B.
    assign useImm = ~is_r & ~is_branch & ~is_float;

    // =========================================================================
    // Memory / jump flags
    // =========================================================================
    assign schMemEnIn   = is_load | is_store | is_fp_ld | is_fp_st;
    assign schMemWrEnIn = is_store | is_fp_st;
    assign schJumpIn    = is_branch | is_jal | is_jalr;

    // =========================================================================
    // Register-file write enable
    // Stores and branches do NOT write a destination register.
    // =========================================================================
    assign regWrite = ~is_store & ~is_branch & ~is_fp_st &
                      ~is_system &
                      (is_r | is_i | is_load | is_jal | is_jalr |
                       is_lui | is_auipc | is_fp_ld | is_fp_op | is_fp_ma);

    // =========================================================================
    // jumpCtrl — this instruction can redirect the PC
    // =========================================================================
    assign jumpCtrl = is_branch | is_jal | is_jalr;

    // =========================================================================
    // float — instruction uses the FP register file
    // =========================================================================
    assign float = is_float;

    // =========================================================================
    // typeIn (ROB instruction type)
    //   2'b10  EXE
    //   2'b11  LOAD
    //   2'b00  STORE
    //   2'b01  JUMP
    // =========================================================================
    reg [1:0] type_out;
    always @(*) begin
        case (1'b1)
            is_load  | is_fp_ld: type_out = 2'b11; // LOAD
            is_store | is_fp_st: type_out = 2'b00; // STORE
            is_branch | is_jal | is_jalr: type_out = 2'b01; // JUMP
            default:             type_out = 2'b10; // EXE
        endcase
    end
    assign typeIn = type_out;

    // =========================================================================
    // robMemAddrIn — raw immediate for store address hint to the ROB
    // For stores the immediate is split across [31:25] and [11:7] (S-type).
    // =========================================================================
    wire [11:0] s_imm = {instr[31:25], instr[11:7]};
    assign robMemAddrIn = is_store ? {{20{s_imm[11]}}, s_imm} : 32'b0;

    // =========================================================================
    // Illegal instruction detection
    // =========================================================================
    wire valid_opcode = is_r | is_i | is_load | is_store |
                        is_branch | is_jal | is_jalr |
                        is_lui | is_auipc | is_system |
                        is_float;

    assign robExceptionIn = ~valid_opcode;

endmodule