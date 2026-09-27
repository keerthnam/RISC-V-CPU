// =============================================================================
// regfile_tb.v
//
// TESTBENCH for regfile.v
//
// How to run this (in Terminal):
//   iverilog -o regfile_tb.out regfile.v regfile_tb.v
//   vvp regfile_tb.out
// =============================================================================

module regfile_tb;

    // ---------------------------------------------------------------
    // Testbench-side signals. These "reg" signals are things WE drive
    // (we set their values); "wire" signals are things the DUT drives
    // (we only read them).
    // ---------------------------------------------------------------
    reg         clk;
    reg         we;
    reg  [4:0]  rs1_addr, rs2_addr, rd_addr;
    reg  [31:0] rd_data;
    wire [31:0] rs1_data, rs2_data;

    // Running count of failed checks. Stays 0 if everything passes.
    integer errors = 0;

    // ---------------------------------------------------------------
    // Instantiate the actual register file module we're testing.
    // This is called "dut" (Device Under Test) by convention.
    // Each ".port_name(signal)" connects a port on regfile.v to a
    // signal declared above.
    // ---------------------------------------------------------------
    regfile dut (
        .clk(clk),
        .we(we),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    // ---------------------------------------------------------------
    // Clock generator: toggles clk every 5 simulated nanoseconds,
    // giving a clock period of 10ns (5ns low, 5ns high). This runs
    // continuously for the whole simulation once started.
    // ---------------------------------------------------------------
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Reusable check: compares an actual value against an expected
    // value and prints a clearly labeled PASS or FAIL line.
    // "name" is just a text label so the printed output is readable
    // (e.g. "write x5=42, read via rs1") instead of cryptic numbers.
    // ---------------------------------------------------------------
    task check(input [255:0] name, input [31:0] actual, input [31:0] expected);
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s -- expected %0d, got %0d", name, expected, actual);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s -- got %0d as expected", name, actual);
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Main test sequence. "initial" blocks in a testbench run once,
    // starting at time 0 -- this is where we script the actual test.
    // ---------------------------------------------------------------
    initial begin
        // Start every signal at a known, safe value before testing.
        clk = 0;
        we  = 0;
        rs1_addr = 0; rs2_addr = 0; rd_addr = 0; rd_data = 0;

        // =================================================================
        // TEST 1: Write the value 42 into register x5, then read it back
        // through the rs1 read port. Confirms basic write-then-read works.
        // =================================================================
        @(negedge clk);              // wait for a falling clock edge (a safe
                                      // moment to change inputs without racing
                                      // the next rising edge)
        we = 1; rd_addr = 5'd5; rd_data = 32'd42;
        @(posedge clk);               // wait for the rising edge -- this is
                                       // the exact instant the write happens
        #1;                            // let the write fully settle
        we = 0;
        rs1_addr = 5'd5;
        #1;
        check("write x5=42, read via rs1", rs1_data, 32'd42);

        // =================================================================
        // TEST 2: Same idea, but through the OTHER read port (rs2), and a
        // different register (x10). Confirms both read ports independently
        // work, not just one.
        // =================================================================
        @(negedge clk);
        we = 1; rd_addr = 5'd10; rd_data = 32'd99;
        @(posedge clk);
        #1;
        we = 0;
        rs2_addr = 5'd10;
        #1;
        check("write x10=99, read via rs2", rs2_data, 32'd99);

        // =================================================================
        // TEST 3: The most important RISC-V-specific check. Try to write
        // a nonzero value (0xDEADBEEF -- a classic "obviously wrong if it
        // shows up" placeholder value) into x0, then confirm x0 STILL
        // reads back as zero. If this fails, the x0-hardwired-to-zero
        // guarantee is broken, which would silently corrupt real programs.
        // =================================================================
        @(negedge clk);
        we = 1; rd_addr = 5'd0; rd_data = 32'hDEADBEEF;
        @(posedge clk);
        #1;
        we = 0;
        rs1_addr = 5'd0;
        #1;
        check("x0 stays zero after write attempt", rs1_data, 32'd0);

        // =================================================================
        // TEST 4: Read BOTH ports simultaneously from two DIFFERENT
        // registers written in earlier tests (x5 from test 1, x7 written
        // fresh here). Confirms the two read ports work independently and
        // at the same time, which is exactly what happens for real when
        // an instruction like "add x1, x5, x7" reads two operands at once.
        // =================================================================
        @(negedge clk);
        we = 1; rd_addr = 5'd7; rd_data = 32'd7;
        @(posedge clk);
        #1;
        we = 0;
        rs1_addr = 5'd5;   // still holds 42 from test 1
        rs2_addr = 5'd7;   // just written above
        #1;
        check("dual-port read: rs1=x5", rs1_data, 32'd42);
        check("dual-port read: rs2=x7", rs2_data, 32'd7);

        // ---------------------------------------------------------------
        // Final summary: one line that makes it obvious at a glance
        // whether the whole run passed.
        // ---------------------------------------------------------------
        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;   // ends the simulation
    end

endmodule
