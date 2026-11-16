// ============================================================
// config.sv  -  ASCON-128 global parameters (ascon_updated)
//
// Changes vs. rtl/peripherals/ascon/config.sv
//   - HARDCODED_AD removed: associated data is now software-written
//     (AD0..AD3 registers, 0..16 bytes).
//   - MODE_* encodings removed (core takes a 1-bit decrypt flag).
//   - MSG_MAX_BYTES / AD_MAX_BYTES size the internal buffers.
// ============================================================
`timescale 1ns/1ps
`ifndef ASCON_CONFIG_SV
`define ASCON_CONFIG_SV

package ascon_config;

  parameter int KEY_LEN   = 128;
  parameter int NONCE_LEN = 128;
  parameter int TAG_LEN   = 128;
  parameter int STATE_LEN = 320;
  parameter int RATE      = 64;

  parameter int PA = 12;
  parameter int PB = 6;

  // ASCON-128 v1.2 IV: k=128, r=64, a=12, b=6
  parameter logic [63:0] ASCON128_IV = 64'h80400c0600000000;

  // Internal buffer sizes (bytes). Message buffer = 4 rate blocks.
  parameter int MSG_MAX_BYTES = 32;
  parameter int AD_MAX_BYTES  = 16;

  // Chaotic Key/Nonce Generator
  // MU = 3.99 in 2.62 fixed-point
  parameter logic [63:0] CHAOS_MU_FP = 64'hFF3851EB851EB852;

  // Warm-up iterations before the first key/nonce is released
  parameter int CHAOS_WARMUP = 64;

  // Base seeds for the two independent logistic-map streams (63-bit).
  parameter logic [62:0] CHAOS_SEED_A = 63'h2A5A5A5A5A5A5A5A;
  parameter logic [62:0] CHAOS_SEED_B = 63'h15A5A5A5A5A5A5A5;

endpackage

`endif // ASCON_CONFIG_SV
