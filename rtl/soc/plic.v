`timescale 1ns/1ps
// ============================================================
// plic.v  Simplified Platform Level Interrupt Controller
// 5 interrupt sources: Timer, GPIO, UART, SPI, I2C
// Single target: Machine External Interrupt (MEIP)
//
// FIXED PRIORITY by source ID (1=highest ... 5=lowest). The
// priority[] and threshold registers are KEPT for software/
// register-map compatibility (readable/writable, matching the
// original design) but are architecturally INERT for the actual
// arbitration decision in this simplified version -- arbitration
// is a simple, fully registered fixed-priority encoder with no
// combinational path from raw_irq to irq_extern at all. This
// removes an entire class of priority-comparison complexity and
// any combinational-glitch risk into the CPU's trap_taken logic,
// in favor of a simpler, easier-to-verify interrupt source.
//
// Registers (base 0x0C00_0000):
//   0x000000 + 4*N  Priority[N]   (RW)  stored, not used for arbitration
//   0x001000        Pending[0]    (RO)  pending bits
//   0x002000        Enable[0]     (RW)  enable bits
//   0x200000        Threshold     (RW)  stored, not used for arbitration
//   0x200004        Claim/Complete(RW)  claim = read, complete = write
// ============================================================
module plic (
    input         clk,
    input         rst,

    input  [31:0] HADDR,
    input  [31:0] HWDATA,
    input         HWRITE,
    input         HSEL,
    input         HREADY,
    output [31:0] HRDATA,
    output        HREADYOUT,

    input         irq_timer_peri,
    input         irq_gpio,
    input         irq_uart,
    input         irq_spi,
    input         irq_i2c,

    output        irq_extern
);

// ID 1=Timer 2=GPIO 3=UART 4=SPI 5=I2C
wire [4:0] raw_irq = {irq_i2c, irq_spi, irq_uart, irq_gpio, irq_timer_peri};

reg [2:0]  prio [1:5];
reg [4:0]  enable;
reg [2:0]  threshold;

reg [4:0] pending;
integer k;
always @(posedge clk or posedge rst) begin
    if (rst) pending <= 5'b0;
    else begin
        for (k=0; k<5; k=k+1) begin
            if (raw_irq[k]) pending[k] <= 1'b1;
        end
        if (HSEL && HWRITE && (HADDR[21:0] == 22'h200004)) begin
            if (HWDATA[2:0] >= 3'd1 && HWDATA[2:0] <= 3'd5)
                pending[HWDATA[2:0]-1] <= 1'b0;
        end
    end
end

// Fixed-priority arbitration: lowest source ID wins, fully
// registered, single clean decision per cycle. No priority/
// threshold comparison at all -- simple, predictable precedence.
reg [2:0] claim_id;
reg       irq_extern_r;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        claim_id     <= 3'd0;
        irq_extern_r <= 1'b0;
    end else begin
        if (pending[0] && enable[0]) begin
            claim_id <= 3'd1;
        end else if (pending[1] && enable[1]) begin
            claim_id <= 3'd2;
        end else if (pending[2] && enable[2]) begin
            claim_id <= 3'd3;
        end else if (pending[3] && enable[3]) begin
            claim_id <= 3'd4;
        end else if (pending[4] && enable[4]) begin
            claim_id <= 3'd5;
        end else begin
            claim_id <= 3'd0;
        end
        irq_extern_r <= (pending & enable) != 5'b0;
    end
end

assign irq_extern = irq_extern_r;

reg [31:0] addr_r;
reg        write_r;
integer j;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        for (j=1; j<=5; j=j+1) prio[j] <= 3'd1;
        enable    <= 5'b11111;
        threshold <= 3'd0;
        addr_r    <= 32'b0;
        write_r   <= 1'b0;
    end
    else begin
        if (HSEL && HWRITE && HREADY) begin
            if (HADDR[21:14] == 8'h00 && HADDR[13:2] >= 12'd1
                && HADDR[13:2] <= 12'd5)
                prio[HADDR[13:2]] <= HWDATA[2:0];
            if (HADDR[21:0] == 22'h002000)
                enable <= HWDATA[4:0];
            if (HADDR[21:0] == 22'h200000)
                threshold <= HWDATA[2:0];
        end
    end
end

reg [31:0] rdata;
always @(*) begin
    if (HADDR[21:14] == 8'h00 && HADDR[13:2] >= 12'd1
        && HADDR[13:2] <= 12'd5)
        rdata = {29'b0, prio[HADDR[13:2]]};
    else case (HADDR[21:0])
        22'h001000: rdata = {27'b0, pending};
        22'h002000: rdata = {27'b0, enable};
        22'h200000: rdata = {29'b0, threshold};
        22'h200004: rdata = {29'b0, claim_id};  // claim
        default:    rdata = 32'h0;
    endcase
end

assign HRDATA    = rdata;
assign HREADYOUT = 1'b1;

endmodule
