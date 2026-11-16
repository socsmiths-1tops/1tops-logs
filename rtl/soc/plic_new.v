`timescale 1ns/1ps
// ============================================================
// plic.v  Simplified Platform Level Interrupt Controller
// 5 interrupt sources: Timer, GPIO, UART, SPI, I2C
// Single target: Machine External Interrupt (MEIP)
//
// Interrupt source IDs and priorities (hardcoded reset values,
// software can still override via priority registers):
//   ID 1 = Timer  → priority 4
//   ID 2 = GPIO   → priority 3
//   ID 3 = UART   → priority 7  (highest — silent data loss risk)
//   ID 4 = SPI    → priority 6  (fast bus, overrun risk)
//   ID 5 = I2C    → priority 5  (clock stretch buys time)
//
// NOTE: Threshold register is READ-ONLY (fixed at reset value 0).
//       Bare-metal usage — all interrupts above threshold=0 fire.
//
// Registers (base 0x0C00_0000):
//   0x000000 + 4*N  Priority[N]   (RW, N = 1..5)
//   0x001000        Pending[0]    (RO)
//   0x002000        Enable[0]     (RW)
//   0x200000        Threshold     (RO, fixed 0)
//   0x200004        Claim/Complete(RW)
// ============================================================
module plic_new (
    input         clk,
    input         rst,
    // AHB-Lite slave interface
    input  [31:0] HADDR,
    input  [31:0] HWDATA,
    input         HWRITE,
    input         HSEL,
    input         HREADY,
    output [31:0] HRDATA,
    output        HREADYOUT,
    // Interrupt sources (active high, level-sensitive)
    input         irq_timer_peri,
    input         irq_gpio,
    input         irq_uart,
    input         irq_spi,
    input         irq_i2c,
    // To CPU — Machine External Interrupt
    output        irq_extern
);

// -------------------------------------------------------
// Raw IRQ vector: bit 0=Timer, 1=GPIO, 2=UART, 3=SPI, 4=I2C
// -------------------------------------------------------
wire [4:0] raw_irq = {irq_i2c, irq_spi, irq_uart, irq_gpio, irq_timer_peri};

// -------------------------------------------------------
// Priority registers (3-bit, range 1–7; 0 = disabled)
// -------------------------------------------------------
reg [2:0] prio [1:5];

// -------------------------------------------------------
// Enable register — one bit per source (bit 0 = ID 1)
// -------------------------------------------------------
reg [4:0] enable;

// -------------------------------------------------------
// Threshold — fixed at 0 (read-only, no write path)
// Bare-metal: every enabled, pending interrupt fires.
// -------------------------------------------------------
wire [2:0] threshold = 3'd0;

// -------------------------------------------------------
// Claim tracking
// -------------------------------------------------------
reg [2:0] claimed_id;

// -------------------------------------------------------
// Pending register
//   SET   : hardware asserts raw_irq[k]
//   CLEAR : software writes source-ID to Claim/Complete reg
// -------------------------------------------------------
reg  [4:0] pending;
integer k;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        pending <= 5'b0;
    end else begin
        // Set pending on any active IRQ line
        for (k = 0; k < 5; k = k + 1) begin
            if (raw_irq[k])
                pending[k] <= 1'b1;
        end
        // Clear pending when software completes the interrupt
        // Write source ID (1–5) to address 0x200004
        if (HSEL && HWRITE && HREADY && (HADDR[21:0] == 22'h200004)) begin
            if (HWDATA[2:0] >= 3'd1 && HWDATA[2:0] <= 3'd5)
                pending[HWDATA[2:0] - 1] <= 1'b0;
        end
    end
end

// -------------------------------------------------------
// Priority arbitration — find highest-priority
// pending + enabled interrupt
// -------------------------------------------------------
reg [2:0] best_id;
reg [2:0] best_prio;
integer i;
always @(*) begin
    best_id   = 3'd0;
    best_prio = 3'd0;
    for (i = 1; i <= 5; i = i + 1) begin
        if (pending[i-1] && enable[i-1] && (prio[i] > best_prio)) begin
            best_prio = prio[i];
            best_id   = i[2:0];
        end
    end
end

// -------------------------------------------------------
// Interrupt output — fires when best priority > threshold
// threshold is fixed 0, so any priority ≥ 1 fires
// -------------------------------------------------------
assign irq_extern = (best_id != 3'd0) && (best_prio > threshold);

// -------------------------------------------------------
// Register write (synchronous)
// Priority registers : writable by software (bare-metal can tune)
// Enable register    : writable
// Threshold          : NOT writable (removed write path)
// Claim/Complete     : handled in pending block above
// -------------------------------------------------------
integer j;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        // Hardcoded reset priorities — tuned for bare-metal
        prio[1] <= 3'd4;   // Timer  — priority 4
        prio[2] <= 3'd3;   // GPIO   — priority 3
        prio[3] <= 3'd7;   // UART   — priority 7 (highest)
        prio[4] <= 3'd6;   // SPI    — priority 6
        prio[5] <= 3'd5;   // I2C    — priority 5
        enable    <= 5'b11111;  // All sources enabled at reset
    end else begin
        if (HSEL && HWRITE && HREADY) begin
            // Priority register write
            // Address: 0x000004*(N) for N in [1..5]
            // HADDR[13:2] gives the DWORD index
            if (HADDR[21:14] == 8'h00 &&
                HADDR[13:2] >= 12'd1  &&
                HADDR[13:2] <= 12'd5)
                prio[HADDR[13:2]] <= HWDATA[2:0];

            // Enable register write
            if (HADDR[21:0] == 22'h002000)
                enable <= HWDATA[4:0];

            // NOTE: Threshold (0x200000) write intentionally removed.
            //       Threshold is hardwired to 0 for bare-metal use.
        end
    end
end

// -------------------------------------------------------
// Register read (combinational)
// -------------------------------------------------------
reg [31:0] rdata;
always @(*) begin
    // Priority register read
    if (HADDR[21:14] == 8'h00 &&
        HADDR[13:2] >= 12'd1  &&
        HADDR[13:2] <= 12'd5)
        rdata = {29'b0, prio[HADDR[13:2]]};
    else
        case (HADDR[21:0])
            22'h001000: rdata = {27'b0, pending};
            22'h002000: rdata = {27'b0, enable};
            22'h200000: rdata = {29'b0, threshold};   // RO = 0
            22'h200004: rdata = {29'b0, best_id};     // Claim
            default:    rdata = 32'h0;
        endcase
end

assign HRDATA    = rdata;
assign HREADYOUT = 1'b1;

endmodule
