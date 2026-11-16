// ============================================================
// ascon_peripheral.sv  -  ASCON-128 bus peripheral (ascon_updated)
//
// Register map: see ascon_regs_pkg.sv.
//
// Typical use
//   Encrypt : write AD0..3/ADLEN, DIN0..7/MSGLEN, CTRL = 0x1, poll
//             STATUS.done -> read CT0..7 (CTLEN bytes) and TAG0..3.
//             TAGIN0..3 now hold the same tag.
//   Decrypt : CTRL = 0x3 (stored ciphertext) or CTRL = 0xB (ciphertext
//             written to DIN0..7/MSGLEN), poll STATUS.done ->
//             STATUS.tag_ok, DOUT0..7. The expected tag is always the
//             encryption tag in TAGIN0..3 (read-only, hardware-loaded).
//
// Bus: same simple valid/ready interface as the original peripheral
// (zero-wait, read data registered one cycle after the request).
// Buffer/length writes are ignored while busy. TAGIN is never writable.
// ============================================================
`timescale 1ns/1ps
`ifndef ASCON_PERIPHERAL_SV
`define ASCON_PERIPHERAL_SV

`include "config.sv"
`include "ascon_regs_pkg.sv"
`include "ascon_core.sv"

module ascon_peripheral #(
  parameter int ADDR_BITS = 6
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        bus_valid,
  output logic        bus_ready,
  input  logic [ADDR_BITS-1:0] bus_addr,
  input  logic [31:0] bus_wdata,
  input  logic [3:0]  bus_wstrb,
  output logic [31:0] bus_rdata,

  output logic        led_busy,
  output logic        led_done,
  output logic        led_chaos_ready,
  output logic        led_tag_ok,
  output logic [3:0]  dbg_fsm
);

  import ascon_regs_pkg::*;

  // ----------------------------------------------------------------
  // Software-visible registers
  // ----------------------------------------------------------------
  logic         r_mode, r_dec_ext, r_start, r_sw_rst;
  logic [5:0]   r_msg_len;
  logic [4:0]   r_ad_len;
  logic [31:0]  r_din   [0:7];
  logic [31:0]  r_ad    [0:3];
  logic [31:0]  r_tagin [0:3];

  // core outputs
  logic [255:0] c_ct, c_pt;
  logic [127:0] c_tag;
  logic [5:0]   c_ct_len;
  logic         c_busy, c_done, c_enc_done, c_ct_valid, c_tag_valid,
                c_tag_ok, c_pt_valid, c_key_loaded, c_err, c_chaos_ready;

  logic [255:0] din_flat;
  logic [127:0] ad_flat, tagin_flat;
  always_comb begin
    for (int i = 0; i < 8; i++) din_flat[255-32*i -: 32] = r_din[i];
    for (int i = 0; i < 4; i++) begin
      ad_flat   [127-32*i -: 32] = r_ad[i];
      tagin_flat[127-32*i -: 32] = r_tagin[i];
    end
  end

  ascon_core u_core (
    .clk          (clk),
    .rst_n        (rst_n),
    .sw_rst       (r_sw_rst),
    .start        (r_start),
    .decrypt      (r_mode),
    .dec_ext      (r_dec_ext),
    .msg_len      (r_msg_len),
    .ad_len       (r_ad_len),
    .din          (din_flat),
    .ad           (ad_flat),
    .tag_in       (tagin_flat),
    .ct_buf       (c_ct),
    .ct_len       (c_ct_len),
    .pt_buf       (c_pt),
    .tag          (c_tag),
    .busy         (c_busy),
    .done         (c_done),
    .enc_done     (c_enc_done),
    .ct_valid     (c_ct_valid),
    .tag_valid    (c_tag_valid),
    .tag_ok       (c_tag_ok),
    .pt_valid     (c_pt_valid),
    .key_loaded   (c_key_loaded),
    .err          (c_err),
    .chaos_ready  (c_chaos_ready),
    .fsm_state_dbg(dbg_fsm)
  );

  // ----------------------------------------------------------------
  // Bus writes
  // ----------------------------------------------------------------
  logic is_write, wr;
  assign is_write  = |bus_wstrb;
  assign bus_ready = bus_valid;
  assign wr        = bus_valid && is_write;

  function automatic logic [31:0] merge(input logic [31:0] old,
                                        input logic [31:0] d,
                                        input logic [3:0]  be);
    for (int b = 0; b < 4; b++) if (be[b]) old[8*b +: 8] = d[8*b +: 8];
    return old;
  endfunction

  logic locked;                  // buffers frozen while an operation runs
  assign locked = c_busy;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      r_mode    <= 1'b0;
      r_dec_ext <= 1'b0;
      r_start   <= 1'b0;
      r_sw_rst  <= 1'b0;
      r_msg_len <= '0;
      r_ad_len  <= '0;
      for (int i = 0; i < 8; i++) r_din[i] <= '0;
      for (int i = 0; i < 4; i++) begin
        r_ad[i]    <= '0;
        r_tagin[i] <= '0;
      end
    end else begin
      r_start  <= 1'b0;
      r_sw_rst <= 1'b0;

      // encryption result: expected tag for the next decrypt
      // (the only write path to TAGIN)
      if (c_enc_done)
        for (int i = 0; i < 4; i++) r_tagin[i] <= c_tag[127-32*i -: 32];

      if (wr) begin
        if (bus_addr == ADDR_BITS'(REG_CTRL) && bus_wstrb[0]) begin
          r_mode    <= bus_wdata[CTRL_MODE];
          r_dec_ext <= bus_wdata[CTRL_DEC_EXT];
          r_sw_rst  <= bus_wdata[CTRL_SWRST];
          r_start   <= bus_wdata[CTRL_START] && !bus_wdata[CTRL_SWRST] && !c_busy;
        end
        if (!locked) begin
          if (bus_addr == ADDR_BITS'(REG_MSGLEN) && bus_wstrb[0]) r_msg_len <= bus_wdata[5:0];
          if (bus_addr == ADDR_BITS'(REG_ADLEN)  && bus_wstrb[0]) r_ad_len  <= bus_wdata[4:0];
          for (int i = 0; i < 8; i++)
            if (bus_addr == ADDR_BITS'(REG_DIN0 + i)) r_din[i] <= merge(r_din[i], bus_wdata, bus_wstrb);
          for (int i = 0; i < 4; i++)
            if (bus_addr == ADDR_BITS'(REG_AD0 + i)) r_ad[i] <= merge(r_ad[i], bus_wdata, bus_wstrb);
          // TAGIN0..3: no bus write path - loaded only by c_enc_done
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // Bus reads (registered, as in the original peripheral)
  // ----------------------------------------------------------------
  logic [31:0] status;
  assign status = {23'h0, c_err, c_key_loaded, c_pt_valid, c_tag_ok,
                   c_tag_valid, c_ct_valid, c_chaos_ready, c_done, c_busy};

  logic [31:0] rmux;
  always_comb begin
    rmux = 32'hDEAD_BEEF;
    if (bus_addr == ADDR_BITS'(REG_CTRL))   rmux = {28'h0, r_dec_ext, 1'b0, r_mode, 1'b0};
    if (bus_addr == ADDR_BITS'(REG_STATUS)) rmux = status;
    if (bus_addr == ADDR_BITS'(REG_MSGLEN)) rmux = {26'h0, r_msg_len};
    if (bus_addr == ADDR_BITS'(REG_ADLEN))  rmux = {27'h0, r_ad_len};
    if (bus_addr == ADDR_BITS'(REG_CTLEN))  rmux = {26'h0, c_ct_len};
    for (int i = 0; i < 8; i++) begin
      if (bus_addr == ADDR_BITS'(REG_DIN0 + i))  rmux = r_din[i];
      if (bus_addr == ADDR_BITS'(REG_CT0 + i))   rmux = c_ct[255-32*i -: 32];
      if (bus_addr == ADDR_BITS'(REG_DOUT0 + i)) rmux = c_pt[255-32*i -: 32];
    end
    for (int i = 0; i < 4; i++) begin
      if (bus_addr == ADDR_BITS'(REG_AD0 + i))    rmux = r_ad[i];
      if (bus_addr == ADDR_BITS'(REG_TAG0 + i))   rmux = c_tag[127-32*i -: 32];
      if (bus_addr == ADDR_BITS'(REG_TAGIN0 + i)) rmux = r_tagin[i];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n)                       bus_rdata <= '0;
    else if (bus_valid && !is_write)  bus_rdata <= rmux;
  end

  // ----------------------------------------------------------------
  // LEDs
  // ----------------------------------------------------------------
  assign led_busy        = c_busy;
  assign led_done        = c_done;
  assign led_chaos_ready = c_chaos_ready;
  assign led_tag_ok      = c_tag_ok;

endmodule

`endif // ASCON_PERIPHERAL_SV
