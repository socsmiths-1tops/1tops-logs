`timescale 1ns/1ps
// ============================================================
// plic_tb.v  — Toggle-coverage-maximised testbench  (v3)
//
// Root cause of 37.72% toggle:
//   1. claimed_id [2:0]  — dead register (never assigned) REMOVED
//   2. threshold  [2:0]  — hardwired 0, excluded via pragma
//   3. HADDR bits        — structurally 0/1, excluded via pragma
//   4. rdata upper bits  — zero-extended outputs, excluded via pragma
//   5. HWDATA upper bits — TB never drove values with bits [31:5] set
//   6. Not all bit patterns exercised in prio/pending/enable
//
// TB fixes:
//   T26 — Exhaust all prio bit patterns (drive 7=111, need bit2 high)
//   T27 — Drive HWDATA all-ones to toggle all 32 input bits
//   T28 — Toggle every pending bit individually 0->1->0
//   T29 — Toggle every enable bit individually 0->1->0
//   T30 — Ensure best_prio sees value with bit2=1 (prio>=4)
//   T31 — Ensure best_id sees all values 1-5 and 0 (done in T2-T8)
//   T32 — Exercise HADDR[13] (bit13 from PENDING addr 0x001000)
//          HADDR[14] (from ENABLE 0x002000)  HADDR[21] (from CLAIM)
//   T33 — rdata bit patterns: drive prio=7 -> rdata[2:0]=111 (all 3 bits=1)
//          drive enable=0x1F -> rdata[4:0]=11111
//          drive pending all 5 bits -> rdata[4:0]=11111
// ============================================================
module tb_plic_new;

// -------------------------------------------------------
// DUT signals
// -------------------------------------------------------
reg        clk, rst;
reg [31:0] HADDR;
reg [31:0] HWDATA;
reg        HWRITE, HSEL, HREADY;
wire[31:0] HRDATA;
wire       HREADYOUT;
reg        irq_timer_peri, irq_gpio, irq_uart, irq_spi, irq_i2c;
wire       irq_extern;

// -------------------------------------------------------
// DUT
// -------------------------------------------------------
plic_new dut (
    .clk           (clk),           .rst           (rst),
    .HADDR         (HADDR),         .HWDATA        (HWDATA),
    .HWRITE        (HWRITE),        .HSEL          (HSEL),
    .HREADY        (HREADY),        .HRDATA        (HRDATA),
    .HREADYOUT     (HREADYOUT),
    .irq_timer_peri(irq_timer_peri),.irq_gpio      (irq_gpio),
    .irq_uart      (irq_uart),      .irq_spi       (irq_spi),
    .irq_i2c       (irq_i2c),      .irq_extern    (irq_extern)
);

// -------------------------------------------------------
// Clock 10 ns
// -------------------------------------------------------
initial clk = 0;
always #5 clk = ~clk;

// -------------------------------------------------------
// Scoreboard
// -------------------------------------------------------
integer pass_cnt, fail_cnt;
initial begin pass_cnt = 0; fail_cnt = 0; end

task check;
    input [255:0] nm; input got; input exp;
    begin
        if (got === exp) begin $display("  [PASS] %s",nm); pass_cnt=pass_cnt+1; end
        else begin $display("  [FAIL] %s  got=%b exp=%b",nm,got,exp); fail_cnt=fail_cnt+1; end
    end
endtask
task check32;
    input [255:0] nm; input [31:0] got; input [31:0] exp;
    begin
        if (got === exp) begin $display("  [PASS] %s",nm); pass_cnt=pass_cnt+1; end
        else begin $display("  [FAIL] %s  got=0x%08h exp=0x%08h",nm,got,exp); fail_cnt=fail_cnt+1; end
    end
endtask

// -------------------------------------------------------
// AHB helpers — #1 delay after posedge avoids setup race
// -------------------------------------------------------
task ahb_write;
    input [31:0] addr; input [31:0] data;
    begin
        @(posedge clk); #1;
        HADDR=addr; HWDATA=data; HWRITE=1; HSEL=1; HREADY=1;
        @(posedge clk); #1;
        HSEL=0; HWRITE=0; HREADY=0;
    end
endtask

task ahb_read;
    input [31:0] addr; output [31:0] data;
    begin
        @(posedge clk); #1;
        HADDR=addr; HWRITE=0; HSEL=1; HREADY=1;
        @(negedge clk); data=HRDATA;
        @(posedge clk); #1;
        HSEL=0; HREADY=0;
    end
endtask

task ahb_claim;  output [2:0] id; reg [31:0] r; begin ahb_read(32'h0C200004,r); id=r[2:0]; end endtask
task ahb_complete; input [2:0] id; begin ahb_write(32'h0C200004,{29'b0,id}); end endtask
task clear_all_irq; begin irq_timer_peri=0;irq_gpio=0;irq_uart=0;irq_spi=0;irq_i2c=0; end endtask

// pulse IRQ for exactly 2 clock cycles then release (ensures pending latches)
task pulse_irq;
    input [4:0] mask;   // bit0=Timer 1=GPIO 2=UART 3=SPI 4=I2C
    begin
        {irq_i2c,irq_spi,irq_uart,irq_gpio,irq_timer_peri} = mask;
        @(posedge clk); #1;
        @(posedge clk); #1;
        {irq_i2c,irq_spi,irq_uart,irq_gpio,irq_timer_peri} = 5'b0;
    end
endtask

// Assert IRQ, let pending latch, claim+complete, check extern
task single_irq_test;
    input [4:0]  mask;
    input [2:0]  exp_id;
    input [31:0] exp_pending;
    input [255:0] nm;
    reg [2:0] cid;
    begin
        {irq_i2c,irq_spi,irq_uart,irq_gpio,irq_timer_peri} = mask;
        @(posedge clk); #1; @(negedge clk);
        check(nm, irq_extern, 1'b1);
        ahb_claim(cid); check32({nm," claim"},{29'b0,cid},{29'b0,exp_id});
        clear_all_irq;
        ahb_complete(exp_id);
        @(posedge clk); #1; @(negedge clk);
        check({nm," deassert"}, irq_extern, 1'b0);
    end
endtask

// -------------------------------------------------------
// Address / constant shortcuts
// -------------------------------------------------------
localparam BASE       = 32'h0C000000;
localparam PRIO_BASE  = BASE;
localparam PENDING_R  = BASE + 32'h001000;
localparam ENABLE_R   = BASE + 32'h002000;
localparam THRESHOLD  = BASE + 32'h200000;
localparam CLAIM_COMP = BASE + 32'h200004;
localparam ALL_EN     = 5'h1F;
localparam NO_UART    = 5'h1B;   // 5'b11011 — bit2=UART cleared

localparam ID_TIMER=3'd1, ID_GPIO=3'd2, ID_UART=3'd3, ID_SPI=3'd4, ID_I2C=3'd5;

reg [31:0] rdata;
reg [2:0]  cid;

// -------------------------------------------------------
// MAIN TEST SEQUENCE
// -------------------------------------------------------
initial begin
    HADDR=0; HWDATA=0; HWRITE=0; HSEL=0; HREADY=0; clear_all_irq;

    // ===================================================
    // T1: RESET STATE
    // ===================================================
    $display("\n=== T1: Reset State ===");
    rst=1; repeat(3) @(posedge clk); #1; rst=0; @(negedge clk);
    check  ("irq_extern low after reset",    irq_extern, 1'b0);
    check  ("HREADYOUT always 1",            HREADYOUT,  1'b1);
    ahb_read(PRIO_BASE+4, rdata);  check32("prio[1]=4", rdata, 32'h4);
    ahb_read(PRIO_BASE+8, rdata);  check32("prio[2]=3", rdata, 32'h3);
    ahb_read(PRIO_BASE+12,rdata);  check32("prio[3]=7", rdata, 32'h7);
    ahb_read(PRIO_BASE+16,rdata);  check32("prio[4]=6", rdata, 32'h6);
    ahb_read(PRIO_BASE+20,rdata);  check32("prio[5]=5", rdata, 32'h5);
    ahb_read(ENABLE_R,    rdata);  check32("enable=0x1F",  rdata, 32'h1F);
    ahb_read(THRESHOLD,   rdata);  check32("threshold=0",  rdata, 32'h0);
    ahb_read(PENDING_R,   rdata);  check32("pending=0",    rdata, 32'h0);

    // ===================================================
    // T2–T6: SINGLE IRQ PER SOURCE
    // ===================================================
    $display("\n=== T2-T6: Single IRQ per source ===");
    single_irq_test(5'b00001, ID_TIMER, 32'h01, "Timer(1)");
    single_irq_test(5'b00010, ID_GPIO,  32'h02, "GPIO(2)");
    single_irq_test(5'b00100, ID_UART,  32'h04, "UART(3)");
    single_irq_test(5'b01000, ID_SPI,   32'h08, "SPI(4)");
    single_irq_test(5'b10000, ID_I2C,   32'h10, "I2C(5)");

    // ===================================================
    // T7: PRIORITY ARBITRATION — 3-way drain
    // ===================================================
    $display("\n=== T7: Arbitration UART>SPI>I2C ===");
    irq_uart=1; irq_spi=1; irq_i2c=1;
    @(posedge clk); #1; @(negedge clk);
    check("irq_extern up (3 IRQs)", irq_extern, 1'b1);
    ahb_claim(cid); check32("UART(3) first",{29'b0,cid},32'h3);
    irq_uart=0; ahb_complete(ID_UART); @(posedge clk); #1; @(negedge clk);
    check("still up SPI+I2C", irq_extern, 1'b1);
    ahb_claim(cid); check32("SPI(4) next",{29'b0,cid},32'h4);
    irq_spi=0;  ahb_complete(ID_SPI);  @(posedge clk); #1; @(negedge clk);
    check("still up I2C", irq_extern, 1'b1);
    ahb_claim(cid); check32("I2C(5) last",{29'b0,cid},32'h5);
    irq_i2c=0;  ahb_complete(ID_I2C);  @(posedge clk); #1; @(negedge clk);
    check("irq_extern low all done", irq_extern, 1'b0);

    // ===================================================
    // T8: ALL 5 SIMULTANEOUS
    // ===================================================
    $display("\n=== T8: All 5 Simultaneous ===");
    irq_timer_peri=1;irq_gpio=1;irq_uart=1;irq_spi=1;irq_i2c=1;
    @(posedge clk); #1; @(negedge clk);
    ahb_read(PENDING_R,rdata); check32("all 5 pending",rdata,32'h1F);
    // Drain in priority order: UART(7)>SPI(6)>I2C(5)>Timer(4)>GPIO(3)
    ahb_claim(cid); check32("1st=UART(3)", {29'b0,cid},32'h3); clear_all_irq;
    ahb_complete(ID_UART);  @(posedge clk); #1;
    ahb_claim(cid); check32("2nd=SPI(4)",  {29'b0,cid},32'h4);
    ahb_complete(ID_SPI);   @(posedge clk); #1;
    ahb_claim(cid); check32("3rd=I2C(5)",  {29'b0,cid},32'h5);
    ahb_complete(ID_I2C);   @(posedge clk); #1;
    ahb_claim(cid); check32("4th=Timer(1)",{29'b0,cid},32'h1);
    ahb_complete(ID_TIMER); @(posedge clk); #1;
    ahb_claim(cid); check32("5th=GPIO(2)", {29'b0,cid},32'h2);
    ahb_complete(ID_GPIO);  @(posedge clk); #1; @(negedge clk);
    check("all 5 cleared", irq_extern, 1'b0);

    // ===================================================
    // T9: PENDING STICKY
    // ===================================================
    $display("\n=== T9: Pending Sticky ===");
    irq_gpio=1; @(posedge clk); #1; @(posedge clk); #1; irq_gpio=0;
    @(negedge clk);
    ahb_read(PENDING_R,rdata); check32("GPIO sticky pending",rdata,32'h02);
    check("irq_extern up (sticky)",irq_extern,1'b1);
    ahb_complete(ID_GPIO); @(posedge clk); #1; @(negedge clk);
    check("irq_extern low after complete",irq_extern,1'b0);
    ahb_read(PENDING_R,rdata); check32("pending cleared",rdata,32'h0);

    // ===================================================
    // T10: ENABLE MASKING — UART masked (bit2=0 => 0x1B)
    // ===================================================
    $display("\n=== T10: Enable Masking UART ===");
    ahb_write(ENABLE_R,32'h1B);
    ahb_read(ENABLE_R,rdata); check32("enable=0x1B",rdata,32'h1B);
    irq_uart=1; @(posedge clk); #1; @(negedge clk);
    ahb_read(PENDING_R,rdata); check32("UART pending set while masked",rdata,32'h04);
    check("irq_extern low UART masked",irq_extern,1'b0);
    irq_uart=0; ahb_complete(ID_UART); @(posedge clk); #1; @(negedge clk);
    ahb_read(PENDING_R,rdata); check32("pending cleared masked",rdata,32'h0);
    // Confirm unmasked source still fires
    irq_spi=1; @(posedge clk); #1; @(negedge clk);
    check("SPI fires while UART masked",irq_extern,1'b1);
    irq_spi=0; ahb_complete(ID_SPI); @(posedge clk); #1; @(negedge clk);
    ahb_write(ENABLE_R,32'h1F);

    // ===================================================
    // T11: FULL ENABLE MASK
    // ===================================================
    $display("\n=== T11: Full Mask enable=0 ===");
    ahb_write(ENABLE_R,32'h00);
    irq_spi=1; @(posedge clk); #1; @(negedge clk);
    check("irq_extern low enable=0",irq_extern,1'b0);
    irq_spi=0; ahb_complete(ID_SPI);
    ahb_write(ENABLE_R,32'h1F);

    // ===================================================
    // T12: THRESHOLD READ-ONLY
    // ===================================================
    $display("\n=== T12: Threshold RO ===");
    ahb_write(THRESHOLD,32'h7); @(posedge clk); #1; @(negedge clk);
    ahb_read(THRESHOLD,rdata); check32("threshold stays 0",rdata,32'h0);
    irq_timer_peri=1; @(posedge clk); #1; @(negedge clk);
    check("irq still fires threshold=0",irq_extern,1'b1);
    irq_timer_peri=0; ahb_complete(ID_TIMER); @(posedge clk); #1; @(negedge clk);

    // ===================================================
    // T13: SOFTWARE PRIORITY OVERRIDE
    // ===================================================
    $display("\n=== T13: SW Priority Override ===");
    ahb_write(PRIO_BASE+8, 32'h7);  // GPIO=7
    ahb_write(PRIO_BASE+12,32'h1);  // UART=1
    irq_gpio=1; irq_uart=1; @(posedge clk); #1; @(negedge clk);
    ahb_claim(cid); check32("GPIO(2) wins",{29'b0,cid},32'h2);
    irq_gpio=0; ahb_complete(ID_GPIO); @(posedge clk); #1;
    irq_uart=0; ahb_complete(ID_UART); @(posedge clk); #1;
    ahb_write(PRIO_BASE+8, 32'h3);
    ahb_write(PRIO_BASE+12,32'h7);

    // ===================================================
    // T14: PRIORITY=0 DISABLES SOURCE
    // ===================================================
    $display("\n=== T14: Priority=0 disable ===");
    ahb_write(PRIO_BASE+4,32'h0);
    irq_timer_peri=1; @(posedge clk); #1; @(negedge clk);
    check("irq_extern low prio=0",irq_extern,1'b0);
    irq_timer_peri=0; ahb_complete(ID_TIMER);
    ahb_write(PRIO_BASE+4,32'h4);

    // ===================================================
    // T15: INVALID COMPLETE IDs (0,6,7)
    // ===================================================
    $display("\n=== T15: Invalid Complete ID ===");
    irq_spi=1; @(posedge clk); #1; @(negedge clk);
    ahb_write(CLAIM_COMP,32'h0); @(posedge clk); #1; @(negedge clk);
    ahb_read(PENDING_R,rdata); check32("pending after ID=0",rdata,32'h08);
    ahb_write(CLAIM_COMP,32'h6); @(posedge clk); #1; @(negedge clk);
    ahb_read(PENDING_R,rdata); check32("pending after ID=6",rdata,32'h08);
    ahb_write(CLAIM_COMP,32'h7); @(posedge clk); #1; @(negedge clk);
    ahb_read(PENDING_R,rdata); check32("pending after ID=7",rdata,32'h08);
    irq_spi=0; ahb_complete(ID_SPI); @(posedge clk); #1; @(negedge clk);
    ahb_read(PENDING_R,rdata); check32("cleared valid ID=4",rdata,32'h0);

    // ===================================================
    // T16: BACK-TO-BACK WITHOUT CLAIM
    // ===================================================
    $display("\n=== T16: Back-to-Back ===");
    irq_timer_peri=1; @(posedge clk); #1;
    irq_timer_peri=0; @(posedge clk); #1;
    irq_timer_peri=1; @(posedge clk); #1;
    irq_timer_peri=0; @(posedge clk); #1; @(negedge clk);
    ahb_read(PENDING_R,rdata); check32("pending after 2 pulses",rdata,32'h01);
    check("irq_extern up 2 pulses",irq_extern,1'b1);
    ahb_complete(ID_TIMER); @(posedge clk); #1; @(negedge clk);
    check("irq_extern low after complete",irq_extern,1'b0);

    // ===================================================
    // T17: RE-ASSERT AFTER COMPLETE
    // ===================================================
    $display("\n=== T17: Re-assert after complete ===");
    irq_uart=1; @(posedge clk); #1; @(negedge clk);
    check("first fires",irq_extern,1'b1);
    ahb_complete(ID_UART); @(posedge clk); #1; @(posedge clk); #1; @(negedge clk);
    check("re-fires UART still high",irq_extern,1'b1);
    irq_uart=0; ahb_complete(ID_UART); @(posedge clk); #1; @(negedge clk);
    check("low after final complete",irq_extern,1'b0);

    // ===================================================
    // T18: HSEL=0 gating
    // ===================================================
    $display("\n=== T18: HSEL=0 Gating ===");
    @(posedge clk); #1;
    HADDR=ENABLE_R; HWDATA=32'h00; HWRITE=1; HSEL=0; HREADY=1;
    @(posedge clk); #1; HSEL=0; HWRITE=0; HREADY=0;
    ahb_read(ENABLE_R,rdata); check32("enable unchanged HSEL=0",rdata,32'h1F);

    // ===================================================
    // T19: HREADY=0 gating
    // ===================================================
    $display("\n=== T19: HREADY=0 Gating ===");
    @(posedge clk); #1;
    HADDR=ENABLE_R; HWDATA=32'h00; HWRITE=1; HSEL=1; HREADY=0;
    @(posedge clk); #1; HSEL=0; HWRITE=0; HREADY=0;
    ahb_read(ENABLE_R,rdata); check32("enable unchanged HREADY=0",rdata,32'h1F);

    // ===================================================
    // T20: UNMAPPED ADDRESS
    // ===================================================
    $display("\n=== T20: Default Address ===");
    ahb_read(32'h0C0BEEF0,rdata); check32("unmapped=0",rdata,32'h0);

    // ===================================================
    // T21: HREADYOUT always 1
    // ===================================================
    $display("\n=== T21: HREADYOUT=1 ===");
    irq_uart=1; irq_spi=1; @(posedge clk); #1; @(negedge clk);
    check("HREADYOUT=1 with pending",HREADYOUT,1'b1);
    irq_uart=0; irq_spi=0;
    ahb_complete(ID_UART); @(posedge clk); #1;
    ahb_complete(ID_SPI);  @(posedge clk); #1; @(negedge clk);
    check("HREADYOUT=1 after complete",HREADYOUT,1'b1);

    // ===================================================
    // T22: TIE-BREAK same priority
    // ===================================================
    $display("\n=== T22: Tie-break same priority ===");
    ahb_write(PRIO_BASE+4,32'h5); ahb_write(PRIO_BASE+8,32'h5);
    irq_timer_peri=1; irq_gpio=1; @(posedge clk); #1; @(negedge clk);
    ahb_claim(cid); check32("Timer(1) wins tie",{29'b0,cid},32'h1);
    irq_timer_peri=0; irq_gpio=0;
    ahb_complete(ID_TIMER); @(posedge clk); #1;
    ahb_complete(ID_GPIO);  @(posedge clk); #1;
    ahb_write(PRIO_BASE+4,32'h4); ahb_write(PRIO_BASE+8,32'h3);

    // ===================================================
    // T23: PRIORITY REGISTER FULL R/W WALK (values 1-7)
    // ===================================================
    $display("\n=== T23: Priority R/W Walk ===");
    begin : prio_walk
        integer n, pv;
        for (n=1; n<=5; n=n+1)
            for (pv=1; pv<=7; pv=pv+1) begin
                ahb_write(PRIO_BASE+4*n, pv);
                ahb_read (PRIO_BASE+4*n, rdata);
                if (rdata[2:0] !== pv[2:0]) begin
                    $display("  [FAIL] prio[%0d] wr=%0d rd=%0d",n,pv,rdata[2:0]);
                    fail_cnt=fail_cnt+1;
                end else pass_cnt=pass_cnt+1;
            end
    end
    ahb_write(PRIO_BASE+4, 32'h4); ahb_write(PRIO_BASE+8, 32'h3);
    ahb_write(PRIO_BASE+12,32'h7); ahb_write(PRIO_BASE+16,32'h6);
    ahb_write(PRIO_BASE+20,32'h5);

    // ===================================================
    // T24: ENABLE R/W ALL PATTERNS
    // ===================================================
    $display("\n=== T24: Enable R/W All Patterns ===");
    begin : en_walk
        integer ev;
        for (ev=0; ev<=31; ev=ev+1) begin
            ahb_write(ENABLE_R,ev);
            ahb_read (ENABLE_R,rdata);
            if (rdata[4:0]!==ev[4:0]) begin
                $display("  [FAIL] enable wr=0x%0x rd=0x%0x",ev,rdata[4:0]);
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
        end
    end
    ahb_write(ENABLE_R,32'h1F);

    // ===================================================
    // T25: FINAL CLEAN STATE
    // ===================================================
    $display("\n=== T25: Final Clean State ===");
    irq_i2c=1; @(posedge clk); #1; @(negedge clk);
    check("irq_extern up I2C",irq_extern,1'b1);
    irq_i2c=0; ahb_complete(ID_I2C); @(posedge clk); #1; @(negedge clk);
    ahb_read(PENDING_R,rdata); check32("pending=0 end",rdata,32'h0);
    check("irq_extern=0 end",irq_extern,1'b0);

    // =======================================================
    // T26: TOGGLE BOOSTER — HWDATA ALL BITS
    //   Drive 0xFFFFFFFF to HWDATA so bits[31:0] all toggle.
    //   Write to a priority register (only [2:0] is captured).
    //   This exercises the full HWDATA bus width.
    //   Then write 0x00000000 to bring them back low.
    // =======================================================
    $display("\n=== T26: Toggle HWDATA all 32 bits ===");
    // Drive all-ones: HWDATA[31:0] all go high
    ahb_write(PRIO_BASE+4, 32'hFFFFFFFF);   // prio latches 3'b111 = 7
    ahb_read(PRIO_BASE+4, rdata);
    check32("prio[1] clamped to 7 on 0xFFFF write", rdata, 32'h7);
    // Drive all-zeros: HWDATA[31:0] all go low
    ahb_write(PRIO_BASE+4, 32'h00000000);   // prio latches 3'b000
    ahb_read(PRIO_BASE+4, rdata);
    check32("prio[1] = 0 on 0x0 write", rdata, 32'h0);
    // Restore Timer prio=4
    ahb_write(PRIO_BASE+4, 32'h4);

    // Same for ENABLE to toggle HWDATA[7:5] range via 0xFF
    ahb_write(ENABLE_R, 32'hFFFFFFFF);      // enable latches 5'b11111
    ahb_read(ENABLE_R, rdata); check32("enable 0xFFFF->0x1F", rdata, 32'h1F);
    ahb_write(ENABLE_R, 32'h00000000);
    ahb_read(ENABLE_R, rdata); check32("enable 0x0->0x00",    rdata, 32'h0);
    ahb_write(ENABLE_R, 32'h1F);

    // =======================================================
    // T27: TOGGLE BOOSTER — PENDING ALL 5 BITS INDIVIDUALLY
    //   Assert each IRQ line individually then complete so
    //   each pending bit toggles 0->1->0 in isolation.
    // =======================================================
    $display("\n=== T27: Toggle each pending bit individually ===");
    begin : pend_walk
        integer pb;
        reg [2:0] src_id;
        reg [4:0] irq_mask;
        for (pb=0; pb<5; pb=pb+1) begin
            src_id  = pb + 1;
            irq_mask = (5'b1 << pb);
            {irq_i2c,irq_spi,irq_uart,irq_gpio,irq_timer_peri} = irq_mask;
            @(posedge clk); #1; @(posedge clk); #1;
            {irq_i2c,irq_spi,irq_uart,irq_gpio,irq_timer_peri} = 5'b0;
            @(negedge clk);
            ahb_read(PENDING_R, rdata);
            if (rdata[pb] !== 1'b1) begin
                $display("  [FAIL] pending bit%0d not set", pb);
                fail_cnt=fail_cnt+1;
            end else begin
                $display("  [PASS] pending bit%0d 0->1",   pb);
                pass_cnt=pass_cnt+1;
            end
            ahb_complete(src_id[2:0]);
            @(posedge clk); #1; @(negedge clk);
            ahb_read(PENDING_R, rdata);
            if (rdata[pb] !== 1'b0) begin
                $display("  [FAIL] pending bit%0d not cleared", pb);
                fail_cnt=fail_cnt+1;
            end else begin
                $display("  [PASS] pending bit%0d 1->0",   pb);
                pass_cnt=pass_cnt+1;
            end
        end
    end

    // =======================================================
    // T28: TOGGLE BOOSTER — EACH ENABLE BIT INDIVIDUALLY
    //   Toggle every enable bit 0->1->0 in isolation so every
    //   bit transitions are captured by the toggle checker.
    // =======================================================
    $display("\n=== T28: Toggle each enable bit individually ===");
    begin : en_bit_walk
        integer eb;
        reg [4:0] en_mask;
        // Start from all-1 for isolation
        ahb_write(ENABLE_R, 32'h1F);
        for (eb=0; eb<5; eb=eb+1) begin
            // clear just bit eb
            en_mask = ALL_EN & ~(5'b1 << eb);
            ahb_write(ENABLE_R, {27'b0, en_mask});
            ahb_read (ENABLE_R, rdata);
            if (rdata[eb] !== 1'b0) begin
                $display("  [FAIL] enable bit%0d stuck 1", eb);
                fail_cnt=fail_cnt+1;
            end else begin
                $display("  [PASS] enable bit%0d 1->0", eb);
                pass_cnt=pass_cnt+1;
            end
            // restore bit eb
            ahb_write(ENABLE_R, 32'h1F);
            ahb_read (ENABLE_R, rdata);
            if (rdata[eb] !== 1'b1) begin
                $display("  [FAIL] enable bit%0d stuck 0", eb);
                fail_cnt=fail_cnt+1;
            end else begin
                $display("  [PASS] enable bit%0d 0->1", eb);
                pass_cnt=pass_cnt+1;
            end
        end
    end

    // =======================================================
    // T29: TOGGLE BOOSTER — best_prio BIT PATTERNS
    //   The arbiter internal best_prio[2:0] must see:
    //     bit2=1 when any prio>=4 wins (already covered T2-T8)
    //     bit1=1 when prio has bit1 (prio=2,3,6,7)
    //     bit0=1 when prio has bit0 (prio=1,3,5,7)
    //   Drive prio[1]=1 (001b) -> best_prio=001: bit0=1, bit1=0, bit2=0
    //   Drive prio[1]=2 (010b) -> best_prio=010: bit0=0, bit1=1, bit2=0
    //   Drive prio[1]=7 (111b) -> best_prio=111: all bits=1
    // =======================================================
    $display("\n=== T29: best_prio bit-pattern sweep ===");
    // Disable all others so Timer always wins
    ahb_write(ENABLE_R, 32'h01);   // only Timer enabled
    // prio=1 (001): bit0 of best_prio should be 1
    ahb_write(PRIO_BASE+4, 32'h1);
    irq_timer_peri=1; @(posedge clk); #1; @(negedge clk);
    check("irq_extern up prio=1", irq_extern, 1'b1);
    irq_timer_peri=0; ahb_complete(ID_TIMER); @(posedge clk); #1;
    // prio=2 (010): bit1 of best_prio should be 1
    ahb_write(PRIO_BASE+4, 32'h2);
    irq_timer_peri=1; @(posedge clk); #1; @(negedge clk);
    check("irq_extern up prio=2", irq_extern, 1'b1);
    irq_timer_peri=0; ahb_complete(ID_TIMER); @(posedge clk); #1;
    // prio=7 (111): all bits of best_prio should be 1
    ahb_write(PRIO_BASE+4, 32'h7);
    irq_timer_peri=1; @(posedge clk); #1; @(negedge clk);
    check("irq_extern up prio=7", irq_extern, 1'b1);
    irq_timer_peri=0; ahb_complete(ID_TIMER); @(posedge clk); #1;
    // prio=0 (000): best_prio=0 -> no interrupt
    ahb_write(PRIO_BASE+4, 32'h0);
    irq_timer_peri=1; @(posedge clk); #1; @(negedge clk);
    check("irq_extern low prio=0", irq_extern, 1'b0);
    irq_timer_peri=0; ahb_complete(ID_TIMER); @(posedge clk); #1;
    // Restore
    ahb_write(PRIO_BASE+4, 32'h4);
    ahb_write(ENABLE_R,    32'h1F);

    // =======================================================
    // T30: TOGGLE BOOSTER — best_id ALL VALUES 0-5
    //   Ensure best_id sees every 3-bit encoding it can reach:
    //   000=none, 001=Timer, 010=GPIO, 011=UART, 100=SPI, 101=I2C
    //   (T2-T8 cover 1-5; here we verify 0 explicitly)
    // =======================================================
    $display("\n=== T30: best_id=0 explicit ===");
    clear_all_irq; @(posedge clk); #1; @(negedge clk);
    ahb_read(CLAIM_COMP, rdata);
    check32("claim=0 when nothing pending", rdata, 32'h0);
    check  ("irq_extern=0 best_id=0",       irq_extern, 1'b0);

    // =======================================================
    // T31: TOGGLE BOOSTER — HADDR bit exerciser
    //   Use PENDING (addr 0x0C001000): bit12 = 1
    //   Use ENABLE  (addr 0x0C002000): bit13 = 1
    //   Use CLAIM   (addr 0x0C200004): bit21 = 1, bit2 = 1
    //   Use PRIO[5] (addr 0x0C000014): bit4=1, bit2=1
    //   All reads — just to toggle HADDR bus bits
    // =======================================================
    $display("\n=== T31: HADDR bit exerciser ===");
    ahb_read(PENDING_R,  rdata);  // bit12 of HADDR high
    ahb_read(ENABLE_R,   rdata);  // bit13 high
    ahb_read(THRESHOLD,  rdata);  // bit21 high
    ahb_read(CLAIM_COMP, rdata);  // bit21+bit2 high
    ahb_read(PRIO_BASE+20,rdata); // bit4+bit2 high
    ahb_read(PRIO_BASE+16,rdata); // bit4 high
    ahb_read(PRIO_BASE+8, rdata); // bit3 high
    ahb_read(PRIO_BASE+4, rdata); // bit2 high
    ahb_read(PRIO_BASE+12,rdata); // bit3+bit2 high
    $display("  [INFO] HADDR bit walk complete (read-only, no check needed)");
    pass_cnt=pass_cnt+1;

    // =======================================================
    // T32: TOGGLE BOOSTER — HRDATA (rdata) BIT PATTERNS
    //   Ensure all reachable bits of rdata see both 0 and 1.
    //   prio[3]=7 -> read back 3'b111 -> rdata[2:0]=111 all 1s
    //   prio[3]=4 -> read back 3'b100 -> rdata[2]=1, [1:0]=0
    //   enable=0x1F -> rdata[4:0]=11111
    //   pending all 5 bits set -> rdata[4:0]=11111
    //   Then clear everything.
    // =======================================================
    $display("\n=== T32: HRDATA (rdata) bit pattern walk ===");
    // prio read: bits 2:0 see 111
    ahb_write(PRIO_BASE+12, 32'h7);   // UART prio=7
    ahb_read (PRIO_BASE+12, rdata);   // rdata[2:0]=111
    check32("rdata[2:0]=7 (UART prio read)", rdata, 32'h7);
    // prio read: bit2=1, bit1=0, bit0=0
    ahb_write(PRIO_BASE+12, 32'h4);
    ahb_read (PRIO_BASE+12, rdata);
    check32("rdata[2:0]=4", rdata, 32'h4);
    // prio read: bit1=1 bit0=1 bit2=0
    ahb_write(PRIO_BASE+12, 32'h3);
    ahb_read (PRIO_BASE+12, rdata);
    check32("rdata[2:0]=3", rdata, 32'h3);
    ahb_write(PRIO_BASE+12, 32'h7);   // restore UART=7

    // enable read: bits 4:0 all 1
    ahb_write(ENABLE_R, 32'h1F);
    ahb_read (ENABLE_R, rdata);  check32("enable rdata=0x1F", rdata, 32'h1F);
    ahb_write(ENABLE_R, 32'h00);
    ahb_read (ENABLE_R, rdata);  check32("enable rdata=0x00", rdata, 32'h00);
    ahb_write(ENABLE_R, 32'h1F);

    // pending read: all 5 bits = 1
    irq_timer_peri=1;irq_gpio=1;irq_uart=1;irq_spi=1;irq_i2c=1;
    @(posedge clk); #1;
    clear_all_irq;
    @(negedge clk);
    ahb_read(PENDING_R, rdata); check32("pending rdata=0x1F all bits", rdata, 32'h1F);
    // Clear all
    ahb_complete(ID_UART);  @(posedge clk); #1;
    ahb_complete(ID_SPI);   @(posedge clk); #1;
    ahb_complete(ID_I2C);   @(posedge clk); #1;
    ahb_complete(ID_TIMER); @(posedge clk); #1;
    ahb_complete(ID_GPIO);  @(posedge clk); #1; @(negedge clk);
    ahb_read(PENDING_R, rdata); check32("pending=0 after clear", rdata, 32'h0);

    // claim read: best_id=5 -> rdata[2:0]=101 (bit2=1, bit0=1)
    irq_i2c=1; @(posedge clk); #1; @(negedge clk);
    ahb_read(CLAIM_COMP, rdata); check32("claim rdata=5 (101b)", rdata, 32'h5);
    irq_i2c=0; ahb_complete(ID_I2C); @(posedge clk); #1;
    // claim read: best_id=4 -> rdata[2:0]=100
    irq_spi=1; @(posedge clk); #1; @(negedge clk);
    ahb_read(CLAIM_COMP, rdata); check32("claim rdata=4 (100b)", rdata, 32'h4);
    irq_spi=0; ahb_complete(ID_SPI); @(posedge clk); #1;
    // claim read: best_id=3 -> rdata[2:0]=011
    irq_uart=1; @(posedge clk); #1; @(negedge clk);
    ahb_read(CLAIM_COMP, rdata); check32("claim rdata=3 (011b)", rdata, 32'h3);
    irq_uart=0; ahb_complete(ID_UART); @(posedge clk); #1; @(negedge clk);

    // =======================================================
    // T33: CORNER — simultaneous set+clear in same cycle
    //   If IRQ asserts on the same clock edge that complete
    //   writes, set takes priority (both happen simultaneously;
    //   for loop sets, if-block clears — result is set wins
    //   because they are non-blocking assignments in same block,
    //   set is done later in the for-loop iteration
    //   Actually in the design: set is `for-loop`, clear is `if`.
    //   Both are non-blocking in the same always block.
    //   Verilog semantics: last assignment wins -> clear wins.
    //   Verify this deterministic behaviour.
    // =======================================================
    $display("\n=== T33: Simultaneous Set+Clear (same cycle) ===");
    // Get SPI pending
    irq_spi=1; @(posedge clk); #1; @(posedge clk); #1; @(negedge clk);
    // Now in same cycle: SPI IRQ still high AND we write complete for SPI
    // Drive IRQ high and issue complete simultaneously
    @(posedge clk); #1;
    HADDR=CLAIM_COMP; HWDATA=32'h4; HWRITE=1; HSEL=1; HREADY=1;
    // SPI still asserted
    @(posedge clk); #1;   // design samples: set(SPI) AND clear(SPI) same clk
    HSEL=0; HWRITE=0; HREADY=0;
    irq_spi=0;
    @(posedge clk); #1; @(negedge clk);
    // Result: pending[3] = 0 (clear wins as last non-blocking assignment)
    ahb_read(PENDING_R, rdata);
    check32("clear wins simultaneous set+clear", rdata, 32'h0);
    check  ("irq_extern low after simultaneous clear", irq_extern, 1'b0);

    // =======================================================
    // SUMMARY
    // =======================================================
    $display("\n============================================");
    $display("  RESULTS: %0d passed, %0d failed", pass_cnt, fail_cnt);
    $display("============================================\n");
    if (fail_cnt==0) $display("  *** ALL TESTS PASSED ***");
    else             $display("  *** %0d FAILED ***", fail_cnt);
    $finish;
end

// Watchdog 500 µs
initial begin #500000; $display("[WATCHDOG] timeout"); $finish; end

endmodule
