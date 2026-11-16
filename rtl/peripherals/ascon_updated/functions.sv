// ============================================================
// functions.sv  -  ASCON permutation helper functions
// ============================================================
`timescale 1ns/1ps
`ifndef ASCON_FUNCTIONS_SV
`define ASCON_FUNCTIONS_SV

package ascon_functions;

  // Round constants (indexed 0..11)
  function automatic logic [7:0] round_const (input logic [3:0] r);
    return {(4'hf - r), r};
  endfunction

  // add_constant: XOR round constant into x[2] (bits [191:128])
  // State layout: [319:0] = {x4, x3, x2, x1, x0}
  function automatic logic [319:0] add_constant (
    input logic [319:0] s,
    input logic [3:0]   round
  );
    logic [319:0] s_out;
    s_out          = s;
    s_out[135:128] = s[135:128] ^ round_const(round);  // BUG FIX: LSByte of x2, not MSByte
    return s_out;
  endfunction

  // sub_bytes: bitsliced ASCON Sbox over 64 parallel 5-bit words
  function automatic logic [319:0] sub_bytes (input logic [319:0] s);
    logic [63:0] x0, x1, x2, x3, x4;
    logic [63:0] t0, t1, t2, t3, t4;

    x0 = s[ 63:  0];
    x1 = s[127: 64];
    x2 = s[191:128];
    x3 = s[255:192];
    x4 = s[319:256];

    x0 ^= x4;  x4 ^= x3;  x2 ^= x1;
    t0 = x0; t1 = x1; t2 = x2; t3 = x3; t4 = x4;

    x0 = t0 ^ (~t1 & t2);
    x1 = t1 ^ (~t2 & t3);
    x2 = t2 ^ (~t3 & t4);
    x3 = t3 ^ (~t4 & t0);
    x4 = t4 ^ (~t0 & t1);

    x1 ^= x0;  x0 ^= x4;  x3 ^= x2;  x2 = ~x2;

    return {x4, x3, x2, x1, x0};
  endfunction

  // ror64: right-rotate 64-bit word by n positions.
  //
  // BUG FIX: Changed `input int n` to `input int unsigned n`.
  // The original `int` is 32-bit SIGNED. If a negative value were
  // passed (e.g. from a signed expression), n[5:0] would extract the
  // wrong bits for shr/shl, producing a corrupt rotation silently.
  // `int unsigned` keeps the 32-bit width (compatible with constant
  // elaboration in Vivado) while making sign semantics explicit and safe.
  //
  // Uses explicit two's-complement negation to avoid the Vivado
  // constant-truncation warning that occurs with 6'd64.
  // For n in [1,63]: shl = ~n[5:0]+1 = 64-n (correct complement).
  // For n=0:         shl = ~0+1 = 0 (mod 64) -> identity. Correct.
  function automatic logic [63:0] ror64 (
    input logic [63:0]  x,
    input int unsigned  n       // <<< FIX: was `int` (signed)
  );
    logic [5:0] shr, shl;
    shr = n[5:0];
    shl = (~n[5:0]) + 6'd1;    // 6-bit two's complement: 64 - n
    return (x >> shr) | (x << shl);
  endfunction

  // linear_layer: sigma diffusion on each of the 5 64-bit words
  // sigma0(x) = x ^ ror(x,19) ^ ror(x,28)
  // sigma1(x) = x ^ ror(x,61) ^ ror(x,39)
  // sigma2(x) = x ^ ror(x, 1) ^ ror(x, 6)
  // sigma3(x) = x ^ ror(x,10) ^ ror(x,17)
  // sigma4(x) = x ^ ror(x, 7) ^ ror(x,41)
  function automatic logic [319:0] linear_layer (input logic [319:0] s);
    logic [63:0] x0, x1, x2, x3, x4;

    x0 = s[ 63:  0];
    x1 = s[127: 64];
    x2 = s[191:128];
    x3 = s[255:192];
    x4 = s[319:256];

    x0 ^= ror64(x0, 19) ^ ror64(x0, 28);
    x1 ^= ror64(x1, 61) ^ ror64(x1, 39);
    x2 ^= ror64(x2,  1) ^ ror64(x2,  6);
    x3 ^= ror64(x3, 10) ^ ror64(x3, 17);
    x4 ^= ror64(x4,  7) ^ ror64(x4, 41);

    return {x4, x3, x2, x1, x0};
  endfunction

endpackage

`endif // ASCON_FUNCTIONS_SV
