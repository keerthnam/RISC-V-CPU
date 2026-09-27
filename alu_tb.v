// =============================================================================
// alu_tb.v
//
// TESTBENCH for alu.v
//
// How to run this (in Terminal):
//   iverilog -o tb/alu_tb.out rtl/alu.v tb/alu_tb.v
//   vvp tb/alu_tb.out
// =============================================================================

module alu_tb;

    // Testbench-driven inputs to the ALU.
    reg  [31:0] a, b;
    reg  [3:0]  alu_op;

    // ALU's output, which we only ever read.
    wire [31:0] result;

    // Running count of failures.
    integer errors = 0;

    // Must exactly match the encoding defined in alu.v.
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

    // Instantiate the ALU under test.
    alu dut (
        .a(a),
        .b(b),
        .alu_op(alu_op),
        .result(result)
    );

    // Same PASS/FAIL check helper as the register file testbench.
    // NOTE: "name" is sized to 512 bits (64 characters) rather than 256
    // (32 characters) like the register file testbench used -- some of
    // the descriptive test names below are longer than 32 characters,
    // and a too-small width here silently truncates the FRONT of the
    // string (e.g. "SRA: ..." was observed printing as just "A: ...").
    // Always size this comfortably larger than your longest test name.
    task check(input [511:0] name, input [31:0] actual, input [31:0] expected);
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s -- expected %0d (0x%0h), got %0d (0x%0h)",
                          name, expected, expected, actual, actual);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s -- got %0d as expected", name, actual);
            end
        end
    endtask

    initial begin
        // ================================================================
        // ADD: 15 + 27 = 42. The most basic possible check.
        // ================================================================
        a = 32'd15; b = 32'd27; alu_op = ALU_ADD; #1;
        check("ADD: 15 + 27", result, 32'd42);

        // ================================================================
        // SUB: 50 - 8 = 42.
        // ================================================================
        a = 32'd50; b = 32'd8; alu_op = ALU_SUB; #1;
        check("SUB: 50 - 8", result, 32'd42);

        // ================================================================
        // SUB producing a negative result: 5 - 10 = -5. In 32-bit two's
        // complement, -5 is represented as 32'hFFFFFFFB. We check the
        // raw bit pattern using $signed() so the comparison itself
        // correctly treats the value as negative.
        // ================================================================
        a = 32'd5; b = 32'd10; alu_op = ALU_SUB; #1;
        if ($signed(result) !== -5) begin
            $display("FAIL: SUB: 5 - 10 -- expected -5, got %0d", $signed(result));
            errors = errors + 1;
        end else begin
            $display("PASS: SUB: 5 - 10 -- got -5 as expected");
        end

        // ================================================================
        // AND: 0xF0F0F0F0 & 0x0FF00FF0 = 0x00F000F0
        // Picked so the answer isn't obvious by accident -- forces the
        // bitwise logic to actually be correct, not just look plausible.
        // ================================================================
        a = 32'hF0F0F0F0; b = 32'h0FF00FF0; alu_op = ALU_AND; #1;
        check("AND: 0xF0F0F0F0 & 0x0FF00FF0", result, 32'h00F000F0);

        // ================================================================
        // OR: 0xF0F0F0F0 | 0x0FF00FF0 = 0xFFF0FFF0
        // ================================================================
        a = 32'hF0F0F0F0; b = 32'h0FF00FF0; alu_op = ALU_OR; #1;
        check("OR: 0xF0F0F0F0 | 0x0FF00FF0", result, 32'hFFF0FFF0);

        // ================================================================
        // XOR: a value XORed with itself is always 0. A clean, easy to
        // hand-verify identity check.
        // ================================================================
        a = 32'hDEADBEEF; b = 32'hDEADBEEF; alu_op = ALU_XOR; #1;
        check("XOR: x ^ x == 0", result, 32'd0);

        // ================================================================
        // SLL: 1 << 4 = 16 (shifting the bit pattern ...0001 left by 4
        // gives ...10000).
        // ================================================================
        a = 32'd1; b = 32'd4; alu_op = ALU_SLL; #1;
        check("SLL: 1 << 4", result, 32'd16);

        // ================================================================
        // SRL: logical right shift zero-fills from the left, even for a
        // negative (high-bit-set) number. 0x80000000 >> 4 should give
        // 0x08000000 -- the top 4 bits become 0, not sign-extended 1s.
        // ================================================================
        a = 32'h80000000; b = 32'd4; alu_op = ALU_SRL; #1;
        check("SRL: 0x80000000 >> 4 (logical)", result, 32'h08000000);

        // ================================================================
        // SRA: arithmetic right shift SIGN-EXTENDS from the left. Same
        // starting value as above, but now the top 4 bits should fill
        // with 1s (preserving the fact the original number was negative),
        // giving 0xF8000000 instead of 0x08000000.
        // ================================================================
        a = 32'h80000000; b = 32'd4; alu_op = ALU_SRA; #1;
        check("SRA: 0x80000000 >>> 4 (arithmetic)", result, 32'hF8000000);

        // ================================================================
        // SLT (signed): -1 < 1 is true when treated as signed numbers.
        // -1 in 32-bit two's complement is 0xFFFFFFFF, which as a raw
        // unsigned number is enormous -- this test exists specifically
        // to prove the ALU is doing a SIGNED comparison, not accidentally
        // comparing the raw bit patterns as unsigned.
        // ================================================================
        a = 32'hFFFFFFFF; b = 32'd1; alu_op = ALU_SLT; #1;
        check("SLT: -1 < 1 (signed)", result, 32'd1);

        // ================================================================
        // SLTU (unsigned): the exact same bit patterns as the test above,
        // but now compared as UNSIGNED. 0xFFFFFFFF as unsigned is the
        // largest possible 32-bit value, so it is NOT less than 1 here.
        // This pair of tests (SLT vs SLTU on identical inputs) is the
        // clearest possible proof the signed/unsigned distinction is
        // actually implemented correctly, not just present in the code.
        // ================================================================
        a = 32'hFFFFFFFF; b = 32'd1; alu_op = ALU_SLTU; #1;
        check("SLTU: 0xFFFFFFFF < 1 (unsigned)", result, 32'd0);

        // ---------------------------------------------------------------
        // Summary.
        // ---------------------------------------------------------------
        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
