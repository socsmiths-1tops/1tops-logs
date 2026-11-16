`timescale 1ns/1ps
// ============================================================
// spi_flash_model.v  Behavioural SPI-NOR flash (SIMULATION ONLY)
//
// Supports READ (0x03) and FAST READ (0x0B, 8 dummy cycles), SPI
// mode 0, with continuous address auto-increment. SCLK may be paused
// at any point while CS is low. Memory is a byte array `mem[]` that
// testbenches preload (e.g. $readmemh of a byte-per-line image).
// Previous chatty version preserved in signoff/backup_wip/.
// ============================================================
module spi_flash_model #(
    parameter MEM_BYTES = 262144
)(
    input  wire clk,     // unused (kept for port compatibility)
    input  wire rst,
    input  wire sclk,
    input  wire mosi,
    output reg  miso,
    input  wire cs_n
);

localparam CMD_READ      = 8'h03;
localparam CMD_FAST_READ = 8'h0B;

reg [7:0]  mem [0:MEM_BYTES-1];

reg [7:0]  cmd;
reg [23:0] addr;          // start address of the current read
reg [31:0] nbits;         // rising edges seen since CS went low

wire [31:0] hdr_bits = (cmd == CMD_FAST_READ) ? 32'd40 : 32'd32;
wire [31:0] dbit     = nbits - hdr_bits;          // next data bit index
wire [31:0] byte_a   = {8'b0, addr} + (dbit >> 3);
wire        is_read  = (cmd == CMD_READ) || (cmd == CMD_FAST_READ);

// Rising edge: count bits, capture command and address from MOSI
always @(posedge sclk or posedge cs_n) begin
    if (cs_n) begin
        nbits <= 32'd0;
        cmd   <= 8'h00;
    end else begin
        nbits <= nbits + 32'd1;
        if (nbits < 32'd8)       cmd  <= {cmd[6:0], mosi};
        else if (nbits < 32'd32) addr <= {addr[22:0], mosi};
    end
end

// Falling edge: present the data bit the master samples next
always @(negedge sclk or posedge cs_n) begin
    if (cs_n)
        miso <= 1'b1;
    else if (is_read && nbits >= hdr_bits)
        miso <= (byte_a < MEM_BYTES) ? mem[byte_a][3'd7 - dbit[2:0]] : 1'b1;
end

integer i;
initial begin
    for (i = 0; i < MEM_BYTES; i = i + 1) mem[i] = 8'hFF;   // erased flash
end

endmodule
