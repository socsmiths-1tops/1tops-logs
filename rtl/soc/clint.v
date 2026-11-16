`timescale 1ns/1ps
// ============================================================
// clint.v  Core Local Interrupt Controller
// Implements RISC-V CLINT spec:
//   0x0000 msip       machine software interrupt pending (RW)
//   0x4000 mtimecmp   timer compare register (RW, 64-bit)
//   0xBFF8 mtime      real-time counter (RO, 64-bit)
//
// Base address: 0x0200_0000
// ============================================================
module clint (
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

    // Interrupt outputs to CPU
    output        irq_timer,    // mtime >= mtimecmp
    output        irq_software  // msip[0]
);

//  Registers 
reg [63:0] mtime;
reg [63:0] mtimecmp;
reg        msip;

//  mtime counter  increments every cycle 
always @(posedge clk or posedge rst) begin
    if (rst) mtime <= 64'b0;
    else     mtime <= mtime + 64'd1;
end

//  AHB register write (registered address phase) 
reg [31:0] addr_r;
reg        write_r;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        addr_r    <= 32'b0;
        write_r   <= 1'b0;
        msip      <= 1'b0;
        mtimecmp  <= 64'hFFFF_FFFF_FFFF_FFFF; // disabled by default
    end
    else if (HSEL && HWRITE && HREADY) begin
        case (HADDR[15:0])
            16'h0000: msip            <= HWDATA[0];
            16'h4000: mtimecmp[31:0]  <= HWDATA;
            16'h4004: mtimecmp[63:32] <= HWDATA;
        endcase
    end
end

//  AHB register read 
reg [31:0] rdata;
always @(*) begin
    case (HADDR[15:0])
        16'h0000: rdata = {31'b0, msip};
        16'h4000: rdata = mtimecmp[31:0];
        16'h4004: rdata = mtimecmp[63:32];
        16'hBFF8: rdata = mtime[31:0];
        16'hBFFC: rdata = mtime[63:32];
        default:  rdata = 32'h0;
    endcase
end

assign HRDATA    = rdata;
assign HREADYOUT = 1'b1;

//  Interrupt generation 
assign irq_timer    = (mtime >= mtimecmp);
assign irq_software = msip;

endmodule
