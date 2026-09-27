// =============================================================================
// control_unit_tb.v
//
// TESTBENCH for control_unit.v
//
// How to run this (in Terminal):
//   iverilog -o tb/control_unit_tb.out rtl/control_unit.v tb/control_unit_tb.v
//   vvp tb/control_unit_tb.out
// =============================================================================

module control_unit_tb;

    // Testbench-driven inputs.
    reg [6:0] opcode;
    reg [2:0] funct3;
    reg       funct7_5;

    // DUT outputs, read-only from here.
    wire       reg_write, mem_read, mem_write, mem_to_reg, alu_src, branch, jump;
    wire [3:0] alu_op;

    integer errors = 0;

    // Must match control_unit.v exactly.
    localparam OPC_RTYPE = 7'b0110011;
    localparam OPC_ITYPE = 7'b0010011;
    localparam OPC_LOAD  = 7'b0000011;
    localparam OPC_STYPE = 7'b0100011;
    localparam OPC_BTYPE = 7'b1100011;
    localparam OPC_JAL   = 7'b1101111;
    localparam OPC_JALR  = 7'b1100111;
    localparam OPC_LUI   = 7'b0110111;

    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_SLT  = 4'b1000;

    control_unit dut (
        .opcode(opcode),
        .funct3(funct3),
        .funct7_5(funct7_5),
        .reg_write(reg_write),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_to_reg(mem_to_reg),
        .alu_src(alu_src),
        .branch(branch),
        .jump(jump),
        .alu_op(alu_op)
    );

    // ---------------------------------------------------------------
    // Bundled check: compares ALL 8 control outputs against expected
    // values in one call, and reports exactly which signal(s) were
    // wrong if something fails -- rather than one check per signal,
    // which would take 8x as many lines for the same coverage.
    // ---------------------------------------------------------------
    task check_all(
        input [511:0] name,
        input exp_reg_write, input exp_mem_read, input exp_mem_write,
        input exp_mem_to_reg, input exp_alu_src, input exp_branch,
        input exp_jump, input [3:0] exp_alu_op
    );
        reg ok;
        begin
            ok = 1'b1;
            if (reg_write  !== exp_reg_write)  begin ok = 1'b0; $display("  -> reg_write mismatch: expected %0d, got %0d", exp_reg_write, reg_write); end
            if (mem_read   !== exp_mem_read)   begin ok = 1'b0; $display("  -> mem_read mismatch: expected %0d, got %0d", exp_mem_read, mem_read); end
            if (mem_write  !== exp_mem_write)  begin ok = 1'b0; $display("  -> mem_write mismatch: expected %0d, got %0d", exp_mem_write, mem_write); end
            if (mem_to_reg !== exp_mem_to_reg) begin ok = 1'b0; $display("  -> mem_to_reg mismatch: expected %0d, got %0d", exp_mem_to_reg, mem_to_reg); end
            if (alu_src    !== exp_alu_src)    begin ok = 1'b0; $display("  -> alu_src mismatch: expected %0d, got %0d", exp_alu_src, alu_src); end
            if (branch     !== exp_branch)     begin ok = 1'b0; $display("  -> branch mismatch: expected %0d, got %0d", exp_branch, branch); end
            if (jump       !== exp_jump)       begin ok = 1'b0; $display("  -> jump mismatch: expected %0d, got %0d", exp_jump, jump); end
            if (alu_op     !== exp_alu_op)     begin ok = 1'b0; $display("  -> alu_op mismatch: expected %0d, got %0d", exp_alu_op, alu_op); end

            if (ok) begin
                $display("PASS: %0s", name);
            end else begin
                $display("FAIL: %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // =================================================================
        // "add x1, x2, x3" -- R-type, funct3=000, funct7_5=0
        // Expect: reg_write=1, alu_src=0, alu_op=ADD, everything else 0.
        // =================================================================
        opcode = OPC_RTYPE; funct3 = 3'b000; funct7_5 = 1'b0; #1;
        check_all("R-type add", 1,0,0,0,0,0,0, ALU_ADD);

        // =================================================================
        // "sub x1, x2, x3" -- R-type, funct3=000, funct7_5=1
        // Only difference from the test above is funct7_5, which should
        // flip the ALU op from ADD to SUB and nothing else.
        // =================================================================
        opcode = OPC_RTYPE; funct3 = 3'b000; funct7_5 = 1'b1; #1;
        check_all("R-type sub", 1,0,0,0,0,0,0, ALU_SUB);

        // =================================================================
        // "addi x1, x2, 10" -- I-type ALU, funct3=000
        // Same ALU op as R-type add, but alu_src should now be 1 (uses
        // the immediate, not rs2). This is the key distinction the test
        // is designed to catch.
        // =================================================================
        opcode = OPC_ITYPE; funct3 = 3'b000; funct7_5 = 1'b0; #1;
        check_all("I-type addi", 1,0,0,0,1,0,0, ALU_ADD);

        // =================================================================
        // "ori x1, x2, 5" -- I-type ALU, funct3=110
        // =================================================================
        opcode = OPC_ITYPE; funct3 = 3'b110; funct7_5 = 1'b0; #1;
        check_all("I-type ori", 1,0,0,0,1,0,0, ALU_OR);

        // =================================================================
        // "lw x1, 0(x2)" -- Load
        // Expect: reg_write=1, alu_src=1 (address = rs1+offset),
        // mem_read=1, mem_to_reg=1 (writeback comes from memory, not ALU).
        // =================================================================
        opcode = OPC_LOAD; funct3 = 3'b010; funct7_5 = 1'b0; #1;
        check_all("lw", 1,1,0,1,1,0,0, ALU_ADD);

        // =================================================================
        // "sw x1, 0(x2)" -- Store
        // Expect: reg_write=0 (stores never write a register!), alu_src=1,
        // mem_write=1.
        // =================================================================
        opcode = OPC_STYPE; funct3 = 3'b010; funct7_5 = 1'b0; #1;
        check_all("sw", 0,0,1,0,1,0,0, ALU_ADD);

        // =================================================================
        // "beq x1, x2, label" -- Branch if equal
        // Expect: branch=1, alu_src=0 (compares two registers),
        // alu_op=SUB (so downstream logic can check for a zero result),
        // reg_write=0 (branches never write a register).
        // =================================================================
        opcode = OPC_BTYPE; funct3 = 3'b000; funct7_5 = 1'b0; #1;
        check_all("beq", 0,0,0,0,0,1,0, ALU_SUB);

        // =================================================================
        // "blt x1, x2, label" -- Branch if less than (signed)
        // Expect: branch=1, alu_op=SLT so the ALU directly produces the
        // "is rs1 < rs2" result.
        // =================================================================
        opcode = OPC_BTYPE; funct3 = 3'b100; funct7_5 = 1'b0; #1;
        check_all("blt", 0,0,0,0,0,1,0, ALU_SLT);

        // =================================================================
        // "jal x1, label" -- Unconditional jump
        // Expect: reg_write=1 (writes return address), jump=1, and
        // everything else at default since no ALU computation is needed
        // for the jump itself in this module's scope.
        // =================================================================
        opcode = OPC_JAL; funct3 = 3'b000; funct7_5 = 1'b0; #1;
        check_all("jal", 1,0,0,0,0,0,1, ALU_ADD);

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
