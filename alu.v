// =============================================================================
// alu.v
//
// ARITHMETIC LOGIC UNIT (ALU)
//
// What this module is:
//   The ALU is the CPU's calculator. It takes two 32-bit numbers and a
//   "which operation" selector, and produces one 32-bit result. Every
//   arithmetic instruction (add, subtract, ...), every logical instruction
//   (and, or, xor, ...), every shift, and every comparison used by
//   branches all go through this one module.
//
// Why it's simpler than the register file:
//   The ALU has NO clock and NO memory/storage. It's purely combinational
//   logic - meaning the output is just a (fairly complex) function of the
//   current inputs, computed instantly, with nothing "remembered" between
//   cycles. Change an input, the output changes immediately, like a plain
//   calculator circuit. Compare this to the register file, which had to
//   remember written values across clock cycles using flip-flops -- the
//   ALU has none of that.
//
// How the operation is selected:
//   Rather than having a separate module for "add", another for
//   "subtract", etc., real hardware (and this module) has ONE circuit
//   that can do ALL the operations, and a "selector" input (alu_op) picks
//   which one's result actually reaches the output. This mirrors how a
//   real ALU is built as a single reusable circuit block.
// =============================================================================

// ---------------------------------------------------------------------------
// Operation selector encoding. Each operation gets a unique 4-bit code.
// These constants are just human-readable names for those 4-bit patterns,
// used both here and in the testbench so nobody has to remember raw binary.
// (This block lives outside the module so both alu.v and alu_tb.v can
// `include` or simply retype these - here we just document the encoding;
// the testbench redeclares matching localparams.)
// ---------------------------------------------------------------------------
// 4'b0000 = ADD   : result = a + b
// 4'b0001 = SUB   : result = a - b
// 4'b0010 = AND   : result = a & b            (bitwise AND)
// 4'b0011 = OR    : result = a | b            (bitwise OR)
// 4'b0100 = XOR   : result = a ^ b            (bitwise XOR)
// 4'b0101 = SLL   : result = a << b[4:0]      (shift left logical)
// 4'b0110 = SRL   : result = a >> b[4:0]      (shift right logical, zero-fill)
// 4'b0111 = SRA   : result = a >>> b[4:0]     (shift right arithmetic, sign-fill)
// 4'b1000 = SLT   : result = (a <  b) ? 1 : 0, treating a and b as SIGNED
// 4'b1001 = SLTU  : result = (a <  b) ? 1 : 0, treating a and b as UNSIGNED
// ---------------------------------------------------------------------------

module alu (
    input  wire [31:0] a,          // first operand (e.g. value from rs1)
    input  wire [31:0] b,          // second operand (e.g. value from rs2,
                                    // or a sign-extended immediate)
    input  wire [3:0]  alu_op,     // which operation to perform - see the
                                    // encoding table above
    output reg  [31:0] result      // the 32-bit output of the selected
                                    // operation
);

    // -------------------------------------------------------------------
    // Operation encoding constants -- must match the table above and the
    // matching constants in alu_tb.v. Defined here so the case statement
    // below reads like plain English instead of raw binary.
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
    // Main operation select logic.
    //
    // "always @(*)" means: re-evaluate this block immediately whenever
    // ANY signal it reads (a, b, or alu_op) changes -- this is how you
    // describe purely combinational logic in Verilog, the equivalent of
    // the "assign" statements used in regfile.v, but written as a case
    // statement because we have many possible operations to choose from
    // instead of one simple expression.
    //
    // "result" is declared as "reg" above (not "wire") because it's
    // assigned inside an always block -- that's a Verilog syntax rule,
    // NOT a sign that it's clocked/stored. This block has no
    // "posedge clk" anywhere, so it is still purely combinational.
    // -------------------------------------------------------------------
    always @(*) begin
        case (alu_op)
            ALU_ADD:  result = a + b;
            ALU_SUB:  result = a - b;
            ALU_AND:  result = a & b;
            ALU_OR:   result = a | b;
            ALU_XOR:  result = a ^ b;

            // Shift amounts only ever need 5 bits (since shifting a 32-bit
            // value by 0-31 covers every meaningful case; RV32I encodes
            // shift amounts using only the low 5 bits of the operand for
            // exactly this reason), so we slice b[4:0] as the shift amount.
            ALU_SLL:  result = a << b[4:0];   // logical left shift, zero-fills
            ALU_SRL:  result = a >> b[4:0];   // logical right shift, zero-fills

            // $signed(...) tells Verilog to treat 'a' as a signed number
            // for this operation, so >>> performs an ARITHMETIC right
            // shift - it fills newly-opened bits on the left with copies
            // of the original sign bit, rather than with zeros. This
            // preserves the sign of negative numbers during the shift,
            // which is what RV32I's SRA instruction requires.
            ALU_SRA:  result = $signed(a) >>> b[4:0];

            // Set-Less-Than, signed: interpret both operands as signed
            // (two's complement) 32-bit integers, and output 1 if a < b,
            // else 0. Used to implement RV32I's SLT/SLTI instructions,
            // and indirectly for signed branch comparisons.
            ALU_SLT:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;

            // Set-Less-Than, unsigned: same idea, but comparing a and b
            // as plain unsigned 32-bit values. Used for SLTU/SLTIU.
            ALU_SLTU: result = (a < b) ? 32'd1 : 32'd0;

            // Default case: covers any alu_op pattern not listed above.
            // Included so the case statement is exhaustive from a
            // synthesis tool's point of view (this avoids Gowin inferring
            // an unwanted latch for "what if alu_op is some unused value"
            // -- an easy, common source of subtle synthesis bugs).
            default:  result = 32'd0;
        endcase
    end

endmodule
