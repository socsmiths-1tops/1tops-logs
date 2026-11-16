// ============================================================
// ascon_core.sv  -  ASCON-128 (v1.2) AEAD core, buffer based
//                   (ascon_updated)
//
// Operation
//   ENCRYPT : take a fresh key/nonce from chaos_core (never visible
//             outside this module), process AD + plaintext from the
//             input buffer, store ciphertext in ct_buf and the tag in
//             `tag`. The key/nonce stay latched for a later decrypt.
//   DECRYPT : with the SAME latched key/nonce, process the ciphertext
//             (stored ct_buf, or the input buffer when dec_ext=1),
//             write the recovered plaintext to pt_buf, recompute the
//             tag and compare it with tag_in, which the peripheral
//             loads with the encryption tag (read-only to software).
//             tag_ok = (decryption tag == encryption tag).
//             On mismatch the plaintext is zeroised (AEAD rule: never
//             release unauthenticated plaintext).
//
// Fixes vs. rtl/peripherals/ascon/ascon_core.sv
//   - tag check compared against a hard-wired 0          -> tag_in port
//   - decrypt overwrote the whole rate on a partial block -> only the
//     ciphertext bytes replace the rate, padding XORed (spec)
//   - extra "padding bit" flipped in x1 (state[64])      -> removed
//   - no padding block for 8/16/..-byte messages        -> length-driven
//   - AD fixed at DEADBEEFCAFEBABE, unpadded             -> 0..16 bytes,
//     padded, absent AD skips absorption (spec)
//   - one key/nonce for the whole power-on              -> fresh per encrypt
//
// Byte order: ASCON big-endian. Buffer byte i sits at
//   buf[BITS-1-8*i -: 8]; rate block j = buf[BITS-1-64*j -: 64].
//
// Permutation: iterative, 2 rounds per clock (p12 = 6 clocks,
// p6 = 3 clocks), one shared round unit.
// ============================================================
`timescale 1ns/1ps
`ifndef ASCON_CORE_SV
`define ASCON_CORE_SV

`include "config.sv"
`include "functions.sv"
`include "chaos_core.sv"

module ascon_core (
  input  logic         clk,
  input  logic         rst_n,        // hard reset
  input  logic         sw_rst,       // synchronous abort / status clear

  input  logic         start,
  input  logic         decrypt,      // 0 = encrypt, 1 = decrypt
  input  logic         dec_ext,      // decrypt the input buffer, not ct_buf
  input  logic [5:0]   msg_len,      // bytes, 0..32 (encrypt / dec_ext)
  input  logic [4:0]   ad_len,       // bytes, 0..16
  input  logic [255:0] din,          // input buffer  (PT or external CT)
  input  logic [127:0] ad,           // associated data
  input  logic [127:0] tag_in,       // expected tag for verification

  output logic [255:0] ct_buf,       // stored ciphertext
  output logic [5:0]   ct_len,
  output logic [255:0] pt_buf,       // recovered plaintext
  output logic [127:0] tag,          // tag computed by the last operation

  output logic         busy,
  output logic         done,         // sticky until next start / sw_rst
  output logic         enc_done,     // 1-cycle pulse: encryption finished
  output logic         ct_valid,
  output logic         tag_valid,
  output logic         tag_ok,
  output logic         pt_valid,
  output logic         key_loaded,   // a key/nonce pair is latched
  output logic         err,          // bad length / decrypt without key
  output logic         chaos_ready,
  output logic [3:0]   fsm_state_dbg
);

  import ascon_config::*;
  import ascon_functions::*;

  // ------------------------------------------------------------------
  // Chaos generator and internal key/nonce latch (never exported)
  // ------------------------------------------------------------------
  logic [127:0] w_key, w_nonce;
  logic         w_ready, take;
  logic [127:0] r_key, r_nonce;

  chaos_core u_chaos (
    .clk   (clk),
    .rst_n (rst_n),
    .take  (take),
    .key   (w_key),
    .nonce (w_nonce),
    .ready (w_ready)
  );

  assign chaos_ready = w_ready;

  logic [63:0] K0, K1;
  assign K0 = r_key[127:64];
  assign K1 = r_key[ 63: 0];

  // ------------------------------------------------------------------
  // FSM
  // ------------------------------------------------------------------
  typedef enum logic [3:0] {
    S_IDLE     = 4'd0,
    S_KEYWAIT  = 4'd1,
    S_INIT     = 4'd2,
    S_PERM     = 4'd3,
    S_INIT_FIN = 4'd4,
    S_AD       = 4'd5,
    S_AD_NEXT  = 4'd6,
    S_DOMSEP   = 4'd7,
    S_MSG      = 4'd8,
    S_MSG_NEXT = 4'd9,
    S_FINAL    = 4'd10,
    S_TAG      = 4'd11
  } state_t;

  state_t fsm, ret;
  assign fsm_state_dbg = fsm;

  // ASCON state words (x0 = rate)
  logic [63:0] x0, x1, x2, x3, x4;
  logic [3:0]  rnd;                  // next round index, 0..11

  // operation context latched at start
  logic        op_dec;
  logic [5:0]  op_len;
  logic [4:0]  op_adlen;
  logic [319:0] op_src;              // source data + one zero block
  logic [2:0]  blk;                  // block index

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------
  // mask keeping the first n bytes (big-endian) of a 64-bit block
  function automatic logic [63:0] keep_bytes(input logic [3:0] n);
    logic [63:0] m;
    m = '0;
    for (int i = 0; i < 8; i++)
      if (i < n) m[63-8*i -: 8] = 8'hFF;
    return m;
  endfunction

  // 0x80 padding byte at byte position n (n = 0..7)
  function automatic logic [63:0] pad_at(input logic [2:0] n);
    logic [63:0] p;
    p = '0;
    p[63-8*n -: 8] = 8'h80;
    return p;
  endfunction

  // two permutation rounds starting at round index r
  logic [319:0] perm_in, perm_out;
  assign perm_in = {x4, x3, x2, x1, x0};
  always_comb begin
    logic [319:0] s;
    s = perm_in;
    for (int k = 0; k < 2; k++)
      s = linear_layer(sub_bytes(add_constant(s, rnd + 4'(k))));
    perm_out = s;
  end

  // AD block j, padded
  logic [191:0] ad_ext;
  assign ad_ext = {ad, 64'h0};
  logic [63:0] ad_blk_raw, ad_blk;
  logic [4:0]  ad_rem;               // bytes of AD from this block on
  assign ad_blk_raw = ad_ext[191 - 64*blk -: 64];
  assign ad_rem     = op_adlen - 5'(8 * blk);
  assign ad_blk     = (ad_rem >= 5'd8) ? ad_blk_raw
                    : (ad_blk_raw & keep_bytes(ad_rem[3:0])) | pad_at(ad_rem[2:0]);
  logic [2:0] ad_nblk;               // number of padded AD blocks
  assign ad_nblk = 3'(op_adlen >> 3) + 3'd1;

  // message block j
  logic [63:0] src_blk;
  assign src_blk = op_src[319 - 64*blk -: 64];
  logic [2:0]  msg_nfull;            // full 8-byte blocks
  logic [2:0]  msg_last_n;           // bytes in final (partial) block
  assign msg_nfull  = 3'(op_len >> 3);
  assign msg_last_n = op_len[2:0];

  logic [63:0] lmask, lpad;
  assign lmask = keep_bytes({1'b0, msg_last_n});
  assign lpad  = pad_at(msg_last_n);

  // final-block values
  logic [63:0] last_in, last_out;     // masked input, masked output
  assign last_in  = src_blk & lmask;
  assign last_out = (x0 ^ src_blk) & lmask;

  // computed tag (valid in S_TAG)
  logic [127:0] tag_calc;
  assign tag_calc = {x3 ^ K0, x4 ^ K1};

  // write block j of a 256-bit buffer
  function automatic logic [255:0] put_blk(input logic [255:0] b,
                                           input logic [2:0] j,
                                           input logic [63:0] v);
    logic [255:0] r;
    r = b;
    if (j < 3'd4) r[255 - 64*j -: 64] = v;
    return r;
  endfunction

  // ------------------------------------------------------------------
  // Sequential
  // ------------------------------------------------------------------
  logic len_bad;
  assign len_bad = (ad_len > 5'(AD_MAX_BYTES)) ||
                   ((!decrypt || dec_ext) && (msg_len > 6'(MSG_MAX_BYTES)));

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fsm        <= S_IDLE;
      ret        <= S_IDLE;
      {x0, x1, x2, x3, x4} <= '0;
      rnd        <= '0;
      op_dec     <= 1'b0;
      op_len     <= '0;
      op_adlen   <= '0;
      op_src     <= '0;
      blk        <= '0;
      r_key      <= '0;
      r_nonce    <= '0;
      key_loaded <= 1'b0;
      ct_buf     <= '0;
      ct_len     <= '0;
      pt_buf     <= '0;
      tag        <= '0;
      busy       <= 1'b0;
      done       <= 1'b0;
      enc_done   <= 1'b0;
      ct_valid   <= 1'b0;
      tag_valid  <= 1'b0;
      tag_ok     <= 1'b0;
      pt_valid   <= 1'b0;
      err        <= 1'b0;
    end else if (sw_rst) begin
      // abort; keep key/nonce, stored CT and tag so a decrypt can follow
      // a completed encryption. An aborted encryption leaves ct_valid=0.
      fsm       <= S_IDLE;
      busy      <= 1'b0;
      done      <= 1'b0;
      enc_done  <= 1'b0;
      tag_ok    <= 1'b0;
      pt_valid  <= 1'b0;
      pt_buf    <= '0;
      err       <= 1'b0;
      if (busy && !op_dec) begin
        ct_valid  <= 1'b0;
        tag_valid <= 1'b0;
      end
    end else begin
      enc_done <= 1'b0;

      case (fsm)
        // --------------------------------------------------------------
        S_IDLE: begin
          if (start) begin
            done     <= 1'b0;
            err      <= 1'b0;
            tag_ok   <= 1'b0;
            pt_valid <= 1'b0;
            pt_buf   <= '0;
            op_dec   <= decrypt;
            op_adlen <= ad_len;
            if (len_bad || (decrypt && !dec_ext && !ct_valid) ||
                (decrypt && !key_loaded)) begin
              err  <= 1'b1;
              done <= 1'b1;
            end else begin
              busy <= 1'b1;
              if (decrypt) begin
                op_len <= dec_ext ? msg_len : ct_len;
                op_src <= {(dec_ext ? din : ct_buf), 64'h0};
                fsm    <= S_INIT;
              end else begin
                op_len    <= msg_len;
                op_src    <= {din, 64'h0};
                ct_valid  <= 1'b0;
                tag_valid <= 1'b0;
                ct_buf    <= '0;
                fsm       <= S_KEYWAIT;
              end
            end
          end
        end

        // fresh key/nonce for every encryption
        S_KEYWAIT: begin
          if (w_ready) begin
            r_key      <= w_key;
            r_nonce    <= w_nonce;
            key_loaded <= 1'b1;
            fsm        <= S_INIT;
          end
        end

        // S = IV || K || N ; p12
        S_INIT: begin
          x0  <= ASCON128_IV;
          x1  <= K0;
          x2  <= K1;
          x3  <= r_nonce[127:64];
          x4  <= r_nonce[ 63: 0];
          rnd <= 4'd0;
          ret <= S_INIT_FIN;
          fsm <= S_PERM;
        end

        S_PERM: begin
          {x4, x3, x2, x1, x0} <= perm_out;
          rnd <= rnd + 4'd2;
          if (rnd == 4'd10) fsm <= ret;
        end

        S_INIT_FIN: begin
          x3  <= x3 ^ K0;
          x4  <= x4 ^ K1;
          blk <= '0;
          fsm <= (op_adlen != 0) ? S_AD : S_DOMSEP;
        end

        S_AD: begin
          x0  <= x0 ^ ad_blk;
          rnd <= 4'd6;
          ret <= S_AD_NEXT;
          fsm <= S_PERM;
        end

        S_AD_NEXT: begin
          blk <= blk + 3'd1;
          fsm <= (blk + 3'd1 < ad_nblk) ? S_AD : S_DOMSEP;
        end

        S_DOMSEP: begin
          x4  <= x4 ^ 64'd1;
          blk <= '0;
          fsm <= S_MSG;
        end

        S_MSG: begin
          if (blk < msg_nfull) begin
            // full block
            if (op_dec) begin
              pt_buf <= put_blk(pt_buf, blk, x0 ^ src_blk);
              x0     <= src_blk;
            end else begin
              ct_buf <= put_blk(ct_buf, blk, x0 ^ src_blk);
              x0     <= x0 ^ src_blk;
            end
            rnd <= 4'd6;
            ret <= S_MSG_NEXT;
            fsm <= S_PERM;
          end else begin
            // final block (0..7 bytes) + padding, no permutation
            if (op_dec) begin
              pt_buf <= put_blk(pt_buf, blk, last_out);
              x0     <= x0 ^ last_out ^ lpad;
            end else begin
              ct_buf <= put_blk(ct_buf, blk, last_out);
              x0     <= x0 ^ last_in ^ lpad;
            end
            fsm <= S_FINAL;
          end
        end

        S_MSG_NEXT: begin
          blk <= blk + 3'd1;
          fsm <= S_MSG;
        end

        // x1 ^= K0, x2 ^= K1 ; p12
        S_FINAL: begin
          x1  <= x1 ^ K0;
          x2  <= x2 ^ K1;
          rnd <= 4'd0;
          ret <= S_TAG;
          fsm <= S_PERM;
        end

        S_TAG: begin
          tag       <= tag_calc;
          tag_valid <= 1'b1;
          if (op_dec) begin
            tag_ok   <= (tag_calc == tag_in);
            pt_valid <= (tag_calc == tag_in);
            if (tag_calc != tag_in) pt_buf <= '0;   // never release
          end else begin
            ct_valid <= 1'b1;
            ct_len   <= op_len;
            enc_done <= 1'b1;
          end
          busy <= 1'b0;
          done <= 1'b1;
          fsm  <= S_IDLE;
        end

        default: fsm <= S_IDLE;
      endcase
    end
  end

  assign take = (fsm == S_KEYWAIT) && w_ready && !sw_rst;

endmodule

`endif // ASCON_CORE_SV
