`timescale 1ns/1ps
// ============================================================
// boot_rom.v  1 KB mask ROM holding the first-stage bootloader.
//
// Contents come from rtl/soc/boot_rom_image.vh, generated from
// sw/boot/boot_loader.S by sw/boot/build_bootrom.sh. Synthesizes to
// constant logic, so silicon, RTL sim, GLS and LEC all see the same
// bootloader.
//
// BOOTROM_LEGACY_PRELOAD (simulation only): replaces the ROM with a
// writable array so older directed testbenches can still poke a
// jump-to-SRAM stub into soc.bootrom.mem[]. Never used for signoff.
// ============================================================
module boot_rom #(
    parameter DEPTH = 256
)(
    input         clk,
    input         rst,
    input  [31:0] iaddr,
    output [31:0] idata,
    input  [31:0] daddr,
    output [31:0] drdata,
    input  [31:0] dwdata,   // ROM: writes ignored
    input         dwe
);

`ifdef BOOTROM_LEGACY_PRELOAD
reg [31:0] mem [0:DEPTH-1];
integer i;
initial for (i = 0; i < DEPTH; i = i + 1) mem[i] = 32'h00000013;
assign idata  = (iaddr[31:2] < DEPTH) ? mem[iaddr[31:2]] : 32'h00000013;
assign drdata = (daddr[31:2] < DEPTH) ? mem[daddr[31:2]] : 32'h00000000;
`else
`include "boot_rom_image.vh"
assign idata  = (iaddr[31:10] == 22'd0) ? bootrom_word(iaddr[9:2]) : 32'h00000013;
assign drdata = (daddr[31:10] == 22'd0) ? bootrom_word(daddr[9:2]) : 32'h00000000;
`endif

endmodule
