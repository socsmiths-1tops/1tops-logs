// ============================================================
// ascon_regs_pkg.sv  -  Register map of ascon_peripheral (ascon_updated)
//
// Word-addressed (bus_addr = byte offset >> 2), ADDR_BITS = 6.
// Byte order in every buffer register: the first byte of the data is
// bits [31:24] of the lowest-numbered register (big-endian, as ASCON).
//
//   0x00  CTRL     RW  [0]=start (W1, self-clearing)  [1]=mode (0 enc, 1 dec)
//                      [2]=sw_rst (W1, self-clearing) [3]=dec_src (0 = stored
//                      ciphertext CT0..7, 1 = external ciphertext in DIN0..7)
//   0x04  STATUS   RO  [0]=busy [1]=done [2]=chaos_ready [3]=ct_valid
//                      [4]=tag_valid [5]=tag_ok [6]=pt_valid [7]=key_loaded
//                      [8]=err
//   0x08  MSGLEN   RW  [5:0] message length in bytes (0..32), used by encrypt
//                      and by external decrypt
//   0x0C  ADLEN    RW  [4:0] associated-data length in bytes (0..16)
//   0x10  CTLEN    RO  [5:0] length of the stored ciphertext
//   0x20-0x3C DIN0..7   RW  input buffer: plaintext (encrypt) or external
//                           ciphertext (decrypt with dec_src=1)
//   0x40-0x4C AD0..3    RW  associated data
//   0x50-0x6C CT0..7    RO  stored ciphertext of the last encryption
//   0x70-0x8C DOUT0..7  RO  recovered plaintext (zero unless tag_ok)
//   0x90-0x9C TAG0..3   RO  tag computed by the last operation
//   0xA0-0xAC TAGIN0..3 RO  expected tag for decrypt = tag of the last
//                           encryption, loaded by hardware only
//   others: read 0xDEAD_BEEF, writes ignored
//
// The key and nonce are generated internally by the chaos generator
// for every encryption and are not readable or writable over the bus.
// ============================================================
`timescale 1ns/1ps
`ifndef ASCON_REGS_PKG_SV
`define ASCON_REGS_PKG_SV

package ascon_regs_pkg;

  localparam int REG_CTRL    = 6'h00;   // 0x00
  localparam int REG_STATUS  = 6'h01;   // 0x04
  localparam int REG_MSGLEN  = 6'h02;   // 0x08
  localparam int REG_ADLEN   = 6'h03;   // 0x0C
  localparam int REG_CTLEN   = 6'h04;   // 0x10
  localparam int REG_DIN0    = 6'h08;   // 0x20 .. 0x3C (8 words)
  localparam int REG_AD0     = 6'h10;   // 0x40 .. 0x4C (4 words)
  localparam int REG_CT0     = 6'h14;   // 0x50 .. 0x6C (8 words)
  localparam int REG_DOUT0   = 6'h1C;   // 0x70 .. 0x8C (8 words)
  localparam int REG_TAG0    = 6'h24;   // 0x90 .. 0x9C (4 words)
  localparam int REG_TAGIN0  = 6'h28;   // 0xA0 .. 0xAC (4 words)

  // CTRL bits
  localparam int CTRL_START   = 0;
  localparam int CTRL_MODE    = 1;      // 0 = encrypt, 1 = decrypt
  localparam int CTRL_SWRST   = 2;
  localparam int CTRL_DEC_EXT = 3;

  // STATUS bits
  localparam int STAT_BUSY       = 0;
  localparam int STAT_DONE       = 1;
  localparam int STAT_CHAOS_RDY  = 2;
  localparam int STAT_CT_VALID   = 3;
  localparam int STAT_TAG_VALID  = 4;
  localparam int STAT_TAG_OK     = 5;
  localparam int STAT_PT_VALID   = 6;
  localparam int STAT_KEY_LOADED = 7;
  localparam int STAT_ERR        = 8;

endpackage

`endif // ASCON_REGS_PKG_SV
