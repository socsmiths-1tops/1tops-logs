`timescale 1ns/1ps
// ============================================================
// ascon_ahb_wrapper.sv
//
// AHB-Lite slave wrapper around ascon_peripheral.
//
// Maps the SoC interconnect's AHB master signals to the
// ascon_peripheral's simple valid/ready bus interface.
//
// Address range : 0x4000_6000 - 0x4000_6FFF (from block diagram)
// Base offset   : bits [7:2] select the register word (ascon_updated:
//                 widened from [5:2] for the buffer registers)
//
// AHB signals used (matching soc_interconnect port names):
//   ahb_haddr   [31:0]  - byte address
//   ahb_hwdata  [31:0]  - write data
//   ahb_hwrite          - write enable
//   ahb_hsize   [2:0]   - transfer size (unused, word assumed)
//   ahb_hsel_ascon      - this slave is selected
//   ahb_hrdata_ascon    - read data back to interconnect
//
// Protocol:
//   AHB address phase : HSEL=1, HADDR valid
//   AHB data  phase   : HWDATA valid (one cycle later)
//   We register the address phase and generate bus_valid/strobe
//   on the data phase — single-cycle response (HREADYOUT=1 always,
//   since ascon_peripheral.bus_ready handles its own stalls).
// ============================================================

`ifndef ASCON_AHB_WRAPPER_SV
`define ASCON_AHB_WRAPPER_SV

module ascon_ahb_wrapper (
    input  logic        clk,
    input  logic        rst_n,          // active-low reset

    // ── AHB-Lite slave port (matches soc_interconnect signal names) ──
    input  logic [31:0] ahb_haddr,
    input  logic [31:0] ahb_hwdata,
    input  logic        ahb_hwrite,
    input  logic [2:0]  ahb_hsize,      // accepted, not used
    input  logic        ahb_hsel_ascon, // select this slave
    output logic [31:0] ahb_hrdata_ascon,
    output logic        ahb_hreadyout,  // always 1 (no stall to AHB master)
                                        // ascon_peripheral stalls internally

    // ── Peripheral I/O (pass-through from ascon_peripheral) ──
    output logic        led_busy,
    output logic        led_done,
    output logic        led_chaos_ready,
    output logic        led_tag_ok,
    output logic [3:0]  dbg_fsm         // key/nonce/tag debug ports removed
);

    // ----------------------------------------------------------------
    // AHB address-phase pipeline register
    // Sample address, write, sel on every AHB address phase.
    // AHB data phase arrives one cycle later.
    // ----------------------------------------------------------------
    logic        ahb_hsel_d;    // registered select
    logic        ahb_hwrite_d;  // registered write
    logic [31:0] ahb_hwdata_d;
    logic [5:0]  ahb_haddr_d;
    logic        bus_valid;
    logic        bus_ready;
    logic [5:0]  bus_addr;
    logic [31:0] bus_wdata;
    logic [3:0]  bus_wstrb;
    logic [31:0] bus_rdata;


always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ahb_hsel_d    <= 1'b0;
        ahb_hwrite_d  <= 1'b0;
        ahb_haddr_d   <= 6'h0;
        ahb_hwdata_d  <= 32'h0;      // add this
    end else begin
        ahb_hsel_d    <= ahb_hsel_ascon;
        ahb_hwrite_d  <= ahb_hwrite;
        ahb_haddr_d   <= ahb_haddr[7:2];
        ahb_hwdata_d  <= ahb_hwdata;  // add this
    end
end

assign bus_wdata = ahb_hwdata_d;   // was: ahb_hwdata

    // ----------------------------------------------------------------
    // Generate ascon_peripheral bus signals
    //
    // bus_valid  : high when AHB data phase is active for this slave
    // bus_addr   : word register select from pipelined address
    // bus_wdata  : direct from AHB HWDATA (available in data phase)
    // bus_wstrb  : 4'hF for writes, 4'h0 for reads
    // ----------------------------------------------------------------

    assign bus_valid = ahb_hsel_d;
    assign bus_addr  = ahb_haddr_d;
    assign bus_wstrb = (ahb_hsel_d && ahb_hwrite_d) ? 4'hF : 4'h0;

    // ----------------------------------------------------------------
    // AHB response
    // HREADYOUT: tie to 1 — ascon_peripheral handles internal stalls
    // via bus_ready. The AHB master sees a 1-cycle response always.
    // bus_ready going low (stall_datacnt) makes bus_valid stay high
    // until the peripheral is ready — the master must re-issue.
    // For a single AHB master (CPU) this is safe since the
    // interconnect doesn't pipeline transactions.
    // ----------------------------------------------------------------
    // Data phase accepted when the peripheral is ready (stall_datacnt
    // back-pressure). The interconnect re-issues the transfer until then.
    assign ahb_hreadyout     = ~ahb_hsel_d | bus_ready;
    assign ahb_hrdata_ascon  = bus_rdata;

    // ----------------------------------------------------------------
    // ascon_peripheral instantiation
    // ----------------------------------------------------------------
    ascon_peripheral #(
        .ADDR_BITS (6)
    ) u_ascon_periph (
        .clk            (clk),
        .rst_n          (rst_n),
        .bus_valid      (bus_valid),
        .bus_ready      (bus_ready),
        .bus_addr       (bus_addr),
        .bus_wdata      (bus_wdata),
        .bus_wstrb      (bus_wstrb),
        .bus_rdata      (bus_rdata),
        .led_busy       (led_busy),
        .led_done       (led_done),
        .led_chaos_ready(led_chaos_ready),
        .led_tag_ok     (led_tag_ok),
        .dbg_fsm        (dbg_fsm)
    );

endmodule

`endif // ASCON_AHB_WRAPPER_SV
// ============================================================
// End of ascon_ahb_wrapper.sv
