// =============================================================================
// control_unit.v
//
// CONTROL UNIT
//
// What this module is:
//   Every RV32I instruction is a 32-bit pattern. The low 7 bits (the
//   "opcode") say roughly what KIND of instruction it is (arithmetic,
//   load, branch, ...). Two more small fields -- funct3 (3 bits) and one
//   bit of funct7 -- narrow that down further (e.g. opcode alone can't
//   tell "add" from "sub"; funct7 bit 5 is what distinguishes them).
//
//   The control unit's entire job is decoding: opcode + funct3 + funct7
//   go in, and a bundle of simple 1-bit and multi-bit "steering signals"
//   come out, telling the rest of the CPU what to do this instruction:
//   write a register? read/write memory? which ALU operation? etc.
//
// Why this is useful to think of as a lookup table:
//   Conceptually this module is nothing more than a big table: "if the
//   instruction looks like THIS, set these signals to THAT." In hardware
//   it becomes decode logic (a mix of AND/OR gates and multiplexers), but
//   the case statement below is meant to read exactly like that table.
//
// A note on scope:
//   This decodes the RV32I subset from the project plan: R-type ALU ops,
//   I-type ALU ops (addi/andi/ori, plus slli/srli/srai/slti/sltiu/xori
//   for completeness since they cost nothing extra to decode), lw, sw,
//   the four branches (beq/bne/blt/bge), jal, jalr, and lui.
//
//   LUI's handling here is a SIMPLIFICATION: a real datapath needs an
//   extra mux to route the raw upper-immediate straight to the register
//   file, bypassing the ALU entirely. That mux doesn't exist yet because
//   the full datapath isn't wired up yet.
// =============================================================================

module control_unit (
    input  wire [6:0] opcode,     // instruction bits [6:0] -- says the
                                   // broad instruction category

    input  wire [2:0] funct3,     // instruction bits [14:12] -- narrows
                                   // down which specific operation within
                                   // that category

    input  wire       funct7_5,   // instruction bit [30] (the 6th bit of
                                   // the 7-bit funct7 field). This single
                                   // bit is the ONLY thing that
                                   // distinguishes add from sub, and srl
                                   // from sra, in RV32I's encoding.

    output reg         reg_write, // 1 = this instruction writes a result
                                   // into the register file

    output reg         mem_read,  // 1 = this instruction reads data memory
                                   // (only true for lw)

    output reg         mem_write, // 1 = this instruction writes data memory
                                   // (only true for sw)

    output reg         mem_to_reg,// 1 = the value written back to the
                                   // register file comes from DATA MEMORY
                                   // (a load); 0 = it comes from the ALU
                                   // result instead

    output reg         alu_src,   // 1 = the ALU's second operand (b) comes
                                   // from the sign-extended IMMEDIATE;
                                   // 0 = it comes from the rs2 register
                                   // value instead

    output reg         branch,    // 1 = this is a conditional branch
                                   // instruction (beq/bne/blt/bge)

    output reg         jump,      // 1 = this is an unconditional jump
                                   // (jal or jalr)

    output reg  [3:0]  alu_op     // which ALU operation to perform --
                                   // uses the SAME 4-bit encoding defined
                                   // in alu.v, so this output can be wired
                                   // directly into the ALU's alu_op input
);

    // -------------------------------------------------------------------
    // Opcode constants -- the low 7 bits of each instruction type, as
    // defined by the RV32I spec. Naming them makes the case statement
    // below readable as "if this is an R-type instruction" instead of
    // "if opcode equals this cryptic bit pattern".
    // -------------------------------------------------------------------
    localparam OPC_RTYPE   = 7'b0110011;  // add, sub, and, or, xor, sll, srl, sra, slt, sltu
    localparam OPC_ITYPE   = 7'b0010011;  // addi, andi, ori, xori, slli, srli, srai, slti, sltiu
    localparam OPC_LOAD    = 7'b0000011;  // lw
    localparam OPC_STYPE   = 7'b0100011;  // sw
    localparam OPC_BTYPE   = 7'b1100011;  // beq, bne, blt, bge
    localparam OPC_JAL     = 7'b1101111;  // jal
    localparam OPC_JALR    = 7'b1100111;  // jalr
    localparam OPC_LUI     = 7'b0110111;  // lui

    // -------------------------------------------------------------------
    // ALU operation constants -- MUST exactly match the encoding in
    // alu.v. Redeclared here (rather than shared some other way) because
    // this project keeps each module self-contained and readable on its
    // own -- a deliberate simplicity/readability tradeoff at this project
    // size.
    // -------------------------------------------------------------------
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;

    // -------------------------------------------------------------------
    // Main decode logic. Combinational, same reasoning as the ALU: no
    // clock, output is purely a function of the current instruction
    // fields.
    // -------------------------------------------------------------------
    always @(*) begin
        // -----------------------------------------------------------
        // SAFE DEFAULTS. Set every output to its "do nothing risky"
        // value FIRST, before the case statement below. This means any
        // opcode pattern we don't explicitly recognize (an invalid or
        // unsupported instruction) safely does nothing rather than
        // accidentally writing a register or corrupting memory. This
        // also avoids Gowin's synthesis tool inferring an unwanted
        // latch for signals that might otherwise not get assigned on
        // every possible path through the case statement.
        // -----------------------------------------------------------
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        alu_src    = 1'b0;
        branch     = 1'b0;
        jump       = 1'b0;
        alu_op     = ALU_ADD;

        case (opcode)

            // =========================================================
            // R-TYPE: rd = rs1 OP rs2   (e.g. "add x1, x2, x3")
            // Both operands come from registers, so alu_src = 0.
            // Which ALU operation depends on funct3, and for two cases
            // (000 and 101) ALSO on funct7_5, since RV32I reuses the
            // same funct3 for two different operations there.
            // =========================================================
            OPC_RTYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b0;
                case (funct3)
                    3'b000: alu_op = funct7_5 ? ALU_SUB : ALU_ADD; // sub vs add
                    3'b001: alu_op = ALU_SLL;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b101: alu_op = funct7_5 ? ALU_SRA : ALU_SRL; // sra vs srl
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end

            // =========================================================
            // I-TYPE ALU: rd = rs1 OP immediate   (e.g. "addi x1, x2, 5")
            // Same operations as R-type, but the second operand is an
            // immediate baked into the instruction rather than a
            // register, so alu_src = 1. This is the ONLY difference
            // between R-type and I-type ALU instructions in terms of
            // control signals.
            // =========================================================
            OPC_ITYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;                        // addi
                    3'b001: alu_op = ALU_SLL;                        // slli
                    3'b010: alu_op = ALU_SLT;                        // slti
                    3'b011: alu_op = ALU_SLTU;                       // sltiu
                    3'b100: alu_op = ALU_XOR;                        // xori
                    3'b101: alu_op = funct7_5 ? ALU_SRA : ALU_SRL;   // srai/srli
                    3'b110: alu_op = ALU_OR;                         // ori
                    3'b111: alu_op = ALU_AND;                        // andi
                    default: alu_op = ALU_ADD;
                endcase
            end

            // =========================================================
            // LOAD: rd = memory[rs1 + immediate]   (lw)
            // The ALU computes an ADDRESS (rs1 + offset), so alu_src=1
            // and alu_op=ADD. mem_read=1 fetches from data memory, and
            // mem_to_reg=1 says the value written back comes from that
            // memory read, not from the ALU's own result.
            // =========================================================
            OPC_LOAD: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                alu_op     = ALU_ADD;
            end

            // =========================================================
            // STORE: memory[rs1 + immediate] = rs2   (sw)
            // Same address computation as a load (rs1 + offset), but
            // this instruction writes memory instead of reading it, and
            // never writes a register at all (reg_write stays 0).
            // =========================================================
            OPC_STYPE: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                alu_op    = ALU_ADD;
            end

            // =========================================================
            // BRANCH: compare rs1 and rs2, conditionally jump   (beq/bne/blt/bge)
            // Both operands come from registers (alu_src=0). We reuse
            // the ALU to do the comparison work:
            //   - beq/bne use SUBTRACT: rs1-rs2 == 0 means equal. The
            //     later branch-decision logic (not part of this module)
            //     checks whether the ALU result is zero, and beq/bne
            //     differ only in whether they branch on zero or
            //     non-zero -- that distinction is handled downstream,
            //     not here.
            //   - blt/bge use SLT (signed less-than): the ALU directly
            //     produces the "is rs1 < rs2" answer as 0 or 1. blt
            //     branches when that's 1, bge branches when it's 0 --
            //     again decided downstream, not in this module.
            // This module's only job here is: recognize it's a branch,
            // and pick the right ALU operation to support that later
            // decision.
            // =========================================================
            OPC_BTYPE: begin
                branch  = 1'b1;
                alu_src = 1'b0;
                case (funct3)
                    3'b000:  alu_op = ALU_SUB; // beq
                    3'b001:  alu_op = ALU_SUB; // bne
                    3'b100:  alu_op = ALU_SLT; // blt
                    3'b101:  alu_op = ALU_SLT; // bge
                    default: alu_op = ALU_SUB;
                endcase
            end

            // =========================================================
            // JAL: unconditional jump, rd = return address (pc + 4)
            // No ALU operand computation needed here at all -- this
            // module just flags reg_write and jump. The actual "which
            // address to jump to" and "compute pc+4" logic lives in the
            // datapath/fetch stage, not the control unit.
            // =========================================================
            OPC_JAL: begin
                reg_write = 1'b1;
                jump      = 1'b1;
            end

            // =========================================================
            // JALR: unconditional jump to rs1 + immediate, rd = pc + 4
            // Needs the ALU to compute the target address (rs1 +
            // immediate), so alu_src=1 and alu_op=ADD, same shape as a
            // load/store address computation.
            // =========================================================
            OPC_JALR: begin
                reg_write = 1'b1;
                jump      = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;
            end

            // =========================================================
            // LUI: rd = immediate << 12 (load a constant into the upper
            // 20 bits of a register). SIMPLIFICATION (see module header
            // comment): a fully correct datapath needs a dedicated mux
            // to pass the shifted immediate straight through to the
            // register file, bypassing the ALU. That extra mux doesn't
            // exist yet in this project. Flagged here rather than
            // silently modeled as something it isn't yet.
            // =========================================================
            OPC_LUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;
            end

            // =========================================================
            // Anything else: leave every signal at its safe default
            // (set at the top of this block). Acts like a NOP.
            // =========================================================
            default: begin
                // intentionally empty - defaults already apply
            end

        endcase
    end

endmodule
