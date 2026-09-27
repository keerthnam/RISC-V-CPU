// =============================================================================
// regfile.v
//
// RV32I REGISTER FILE
//
// What this module is:
//   The register file is the CPU's small, fast scratchpad memory -- 32
//   general-purpose registers, each 32 bits wide, named x0 through x31.
//   Instructions read from and write to these registers constantly (almost
//   every instruction touches at least one).
//
// Why it needs TWO read ports and only ONE write port:
//   Most RV32I instructions have the form  rd = rs1 OP rs2
//   (e.g. add x1, x2, x3 means x1 = x2 + x3). That means an instruction
//   needs to read TWO source registers (rs1 and rs2) at the same time, but
//   only ever writes to ONE destination register (rd) per instruction.
//   So: 2 read ports, 1 write port.
//
// Why x0 is special:
//   The RISC-V spec hardwires register x0 to always equal zero. Reading it
//   always returns 0, and writing to it has no effect (the write is
//   silently discarded). This is useful in real code -- e.g. comparing a
//   register to zero can just use x0 as an operand instead of needing a
//   special "compare to zero" instruction.
// =============================================================================

module regfile (
    input  wire        clk,         // clock -- writes happen on its rising edge

    input  wire        we,          // "write enable": 1 = perform the write
                                     // this cycle, 0 = don't write anything

    input  wire [4:0]  rs1_addr,    // address (0-31) of the first source
                                     // register to read. 5 bits because
                                     // 2^5 = 32 possible registers.

    input  wire [4:0]  rs2_addr,    // address (0-31) of the second source
                                     // register to read

    input  wire [4:0]  rd_addr,     // address (0-31) of the destination
                                     // register to write to (only used if
                                     // we == 1)

    input  wire [31:0] rd_data,     // the 32-bit value to write into
                                     // rd_addr (only used if we == 1)

    output wire [31:0] rs1_data,    // the 32-bit value currently stored in
                                     // register rs1_addr

    output wire [31:0] rs2_data     // the 32-bit value currently stored in
                                     // register rs2_addr
);

    // -------------------------------------------------------------------
    // The actual storage: an array of 32 registers, each 32 bits wide.
    // Think of this as a small table: regs[0], regs[1], ..., regs[31].
    // In real hardware this becomes 32 x 32 = 1024 flip-flops.
    // -------------------------------------------------------------------
    reg [31:0] regs [0:31];

    // -------------------------------------------------------------------
    // READ LOGIC -- combinational (no "always @(posedge clk)" here).
    //
    // "Combinational" means: there is no clock involved. The output wire
    // updates immediately, within the same instant, whenever the input
    // address changes -- like a plain wire, not something that "waits"
    // for a clock tick. This models real hardware read ports, which are
    // just multiplexers (selector circuits), not clocked storage.
    //
    // Each line is a ternary (a ? b : c): "if condition, use b, else use c".
    //   - If the requested address is 0 (x0), always output 0, ignoring
    //     whatever regs[0] might actually contain.
    //   - Otherwise, output whatever is actually stored in that register.
    // -------------------------------------------------------------------
    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : regs[rs2_addr];

    // -------------------------------------------------------------------
    // WRITE LOGIC - synchronous ("always @(posedge clk)").
    //
    // Unlike reads, writes only happen at one specific moment: the rising
    // edge of the clock signal (the instant it transitions from 0 to 1).
    // This is what makes the register file act like real memory instead
    // of a value that could change unpredictably at any time -- it only
    // ever changes on a clock tick, and only when explicitly told to.
    //
    // The write only actually happens if BOTH:
    //   1) we == 1        (the rest of the CPU is asking for a write), AND
    //   2) rd_addr != 0    (we're not trying to write to x0)
    // This second condition is what permanently protects x0 from ever
    // being changed, on top of the read logic above always returning 0
    // for it regardless.
    // -------------------------------------------------------------------
    always @(posedge clk) begin
        if (we && rd_addr != 5'd0) begin
            regs[rd_addr] <= rd_data;
        end
    end

endmodule
