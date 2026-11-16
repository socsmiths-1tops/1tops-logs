// ============================================================
// chaos_core.sv  -  Chaotic key / nonce generator (ascon_updated)
//
// Algorithm : fixed-point logistic map  x_{n+1} = MU * x_n * (1 - x_n)
//   x stored in 1.63 unsigned fixed point, MU = 3.99 in 2.62.
//   Two independent streams: A -> key, B -> nonce.
//   Each iteration contributes the top 32 bits of x (bits [62:31]);
//   4 iterations give one 128-bit key and one 128-bit nonce.
//
// Changes vs. rtl/peripherals/ascon/chaos_core.sv
//
//   1. FRESH KEY/NONCE PER OPERATION (new). The old generator produced
//      ONE key/nonce after reset and then stopped (CS_READY held it),
//      so every encryption used the same key AND the same nonce -
//      nonce reuse breaks ASCON's confidentiality and integrity.
//      Now the map keeps iterating after warm-up. `take` hands the
//      consumer the current 128-bit key/nonce and `ready` drops until
//      4 completely new iterations have been shifted in, so no key or
//      nonce word is ever handed out twice.
//
//   2. REPEATED-WORD BUG FIXED. The old FSM read the 2-stage multiplier
//      pipeline every cycle while it only holds a new result every
//      2-3 cycles, so the same sample was captured several times:
//      key = W W W X, nonce = V V V Y (seen in Vivado as
//      981f19d4_981f19d4_981f19d4_ec500d96). The iteration is now
//      paced by a phase counter: x is updated only when the pipeline
//      output belongs to the current x (one iteration every 3 clocks).
//
//   3. Key/nonce never leave the ASCON block: no debug ports.
//
// Seeding: base constants XOR a power-on counter value latched once
// after reset release (as before). This is deterministic for a given
// reset-release timing; for silicon, a true entropy source (ring
// oscillator TRNG) should feed the seed - see README_ascon_updated.txt.
// ============================================================
`ifndef CHAOS_CORE_SV
`define CHAOS_CORE_SV

`include "config.sv"

module chaos_core #(
  parameter int WARMUP = ascon_config::CHAOS_WARMUP
)(
  input  logic         clk,
  input  logic         rst_n,

  input  logic         take,    // consumer latches key/nonce this cycle
  output logic [127:0] key,
  output logic [127:0] nonce,
  output logic         ready    // key/nonce are fresh (never handed out)
);

  import ascon_config::*;

  localparam logic [63:0] MU    = CHAOS_MU_FP;
  localparam logic [62:0] X_MIN = 63'h0000_0000_0000_0010;
  localparam logic [62:0] X_MAX = 63'h7FFF_FFFF_FFFF_FFF0;

  // ------------------------------------------------------------------
  // Power-on counter, sampled once into the map state after reset
  // ------------------------------------------------------------------
  logic [31:0] pon_ctr;
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) pon_ctr <= 32'b0;
    else        pon_ctr <= pon_ctr + 1'b1;

  logic        seeded;

  logic [31:0] pon_seed_rev;
  always_comb begin : gen_seed_rev
    for (int i = 0; i < 32; i++) pon_seed_rev[i] = pon_ctr[31 - i];
  end

  // ------------------------------------------------------------------
  // Two-stage pipelined multiplier (free running)
  //   stage 0: X * (1 - X)      stage 1: MU * (...), clamp
  // ------------------------------------------------------------------
  logic [62:0] xa, xb;
  logic [63:0] pipe0_mid_a, pipe0_mid_b;
  logic [62:0] xa_piped, xb_piped;

  logic [63:0]  c0_xa64, c0_xb64, c0_om_a, c0_om_b;
  logic [127:0] c0_prod_a, c0_prod_b;
  always_comb begin
    c0_xa64   = {1'b0, xa};
    c0_xb64   = {1'b0, xb};
    c0_om_a   = 64'h8000_0000_0000_0000 - c0_xa64;
    c0_om_b   = 64'h8000_0000_0000_0000 - c0_xb64;
    c0_prod_a = c0_xa64 * c0_om_a;
    c0_prod_b = c0_xb64 * c0_om_b;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pipe0_mid_a <= '0;
      pipe0_mid_b <= '0;
    end else begin
      pipe0_mid_a <= c0_prod_a[125:62];
      pipe0_mid_b <= c0_prod_b[125:62];
    end
  end

  logic [127:0] c1_prod_a, c1_prod_b;
  logic [62:0]  c1_out_a,  c1_out_b;
  always_comb begin
    c1_prod_a = MU * pipe0_mid_a;
    c1_prod_b = MU * pipe0_mid_b;
    c1_out_a  = c1_prod_a[124:62];
    c1_out_b  = c1_prod_b[124:62];
    if      (c1_out_a < X_MIN) c1_out_a = X_MIN;
    else if (c1_out_a > X_MAX) c1_out_a = X_MAX;
    if      (c1_out_b < X_MIN) c1_out_b = X_MIN;
    else if (c1_out_b > X_MAX) c1_out_b = X_MAX;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      xa_piped <= CHAOS_SEED_A;
      xb_piped <= CHAOS_SEED_B;
    end else begin
      xa_piped <= c1_out_a;
      xb_piped <= c1_out_b;
    end
  end

  // ------------------------------------------------------------------
  // Iteration pacing: x changes at the end of phase 2; the pipeline
  // registers then need phases 0 and 1 to compute f(x), so in phase 2
  // xa_piped/xb_piped hold exactly f(xa)/f(xb).
  // ------------------------------------------------------------------
  logic [1:0] phase;
  logic       iter;                  // x advances this cycle
  assign iter = seeded && (phase == 2'd2);

  logic [$clog2(WARMUP+1)-1:0] wu_cnt;
  logic        warm;                 // warm-up finished
  logic [2:0]  fresh_cnt;            // new samples since last take (sat. 4)
  logic [127:0] key_sr, nonce_sr;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      seeded    <= 1'b0;
      phase     <= 2'd0;
      xa        <= CHAOS_SEED_A;
      xb        <= CHAOS_SEED_B;
      wu_cnt    <= '0;
      warm      <= 1'b0;
      fresh_cnt <= '0;
      key_sr    <= '0;
      nonce_sr  <= '0;
    end else begin
      if (!seeded) begin
        // one-shot seed: spread the counter over all 63 bits
        xa       <= (CHAOS_SEED_A ^ {pon_seed_rev[30:0], pon_ctr}) | X_MIN;
        xb       <= (CHAOS_SEED_B ^ {pon_ctr[30:0], pon_seed_rev}) | X_MIN;
        seeded   <= 1'b1;
        phase    <= 2'd0;
      end else begin
        phase <= (phase == 2'd2) ? 2'd0 : phase + 2'd1;
      end

      if (iter) begin
        xa <= xa_piped;
        xb <= xb_piped;
        if (!warm) begin
          wu_cnt <= wu_cnt + 1'b1;
          if (wu_cnt == ($bits(wu_cnt))'(WARMUP - 1)) warm <= 1'b1;
        end else begin
          key_sr   <= {key_sr[95:0],   xa_piped[62:31]};
          nonce_sr <= {nonce_sr[95:0], xb_piped[62:31]};
        end
      end

      // freshness: a take restarts the count (a sample shifted in the
      // same cycle belongs to the next key, so not counting it is safe)
      if (take)
        fresh_cnt <= '0;
      else if (iter && warm && fresh_cnt != 3'd4)
        fresh_cnt <= fresh_cnt + 3'd1;
    end
  end

  assign key   = key_sr;
  assign nonce = nonce_sr;
  assign ready = warm && (fresh_cnt == 3'd4);

endmodule

`endif // CHAOS_CORE_SV
