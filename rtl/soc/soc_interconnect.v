`timescale 1ns/1ps
// ============================================================
// soc_interconnect.v  SoC Address Decoder and Data Mux
//
// Memory Map:
//   0x0000_0000 - 0x0000_03FF  Boot ROM   (1KB,  read-only)
//   0x1000_0000 - 0x1000_FFFF  IMEM       (64KB, SCL180 macros; fetch + data wait-state)
//   0x1001_0000 - 0x1001_FFFF  DMEM       (64KB, SCL180 macros; zero wait state)
//   0x0200_0000 - 0x0200_FFFF  CLINT
//   0x0C00_0000 - 0x0C00_1FFF  PLIC
//   0x4000_0000 - 0x4000_4FFF  APB peripherals (timer/gpio/uart/spi/i2c)
//
//   0x4000_5000 - 0x4000_5FFF  Boot flash controller (APB)
//   0x4000_6000 - 0x4000_6FFF  ASCON (direct AHB slave)
//
// APB and ASCON accesses stall the CPU (dstall) until the slave
// completes; see "Slave handshake" below.
// ============================================================
module soc_interconnect (
    input         clk,
    input         rst,

    input  [31:0] iaddr,
    output [31:0] idata,

    input  [31:0] daddr,
    input  [31:0] dwdata,
    input         dwe,
    input         dre,       // load in Memory stage
    input  [1:0]  dsize,
    output [31:0] drdata,

    output        dstall,    // NEW: stall the CPU while an APB read is outstanding

    output [31:0] rom_iaddr,
    input  [31:0] rom_idata,
    output [31:0] rom_daddr,
    input  [31:0] rom_drdata,
    output [31:0] rom_dwdata,
    output        rom_dwe,

    // IMEM / DMEM (soc_sram)
    output [3:0]  sram_dbe,        // byte lanes of the Memory-stage store
    output        dmem_we,
    input  [31:0] dmem_rdata,
    output        imem_acc,
    output        imem_we,
    input         imem_resp,
    input  [31:0] imem_rdata,
    input  [31:0] imem_idata,

    output [31:0] ahb_haddr,
    output [31:0] ahb_hwdata,
    output        ahb_hwrite,
    output [2:0]  ahb_hsize,
    output        ahb_hsel_apb,
    output        ahb_hsel_clint,
    output        ahb_hsel_plic,
    input  [31:0] ahb_hrdata_apb,
    input  [31:0] ahb_hrdata_clint,
    input  [31:0] ahb_hrdata_plic,

    // ASCON Engine (AHB slave, direct) -- 0x4000_6000-0x4000_6FFF
    output        ahb_hsel_ascon,
    input  [31:0] ahb_hrdata_ascon,
    input         ahb_hready_ascon, // ASCON data phase accepted
    input         apb_xfer_done     // bridge ENABLE & PREADY
);

wire dsel_rom   = (daddr[31:16] == 16'h0000);
wire dsel_imem  = (daddr[31:16] == 16'h1000);
wire dsel_dmem  = (daddr[31:16] == 16'h1001);
wire dsel_clint = (daddr[31:16] == 16'h0200);
wire dsel_plic  = (daddr[31:26] == 6'b000011);
wire dsel_apb   = (daddr[31:16] == 16'h4000) && (daddr[15:12] <= 4'h5);  // incl. boot flash @0x4000_5000 (Bug #21)
wire dsel_ascon = (daddr[31:12] == 20'h40006);  // 0x4000_6000-0x4000_6FFF

wire isel_rom   = (iaddr[31:16] == 16'h0000);
wire isel_imem  = (iaddr[31:16] == 16'h1000);

reg [3:0] byte_we;
always @(*) begin
    case (dsize)
        2'b00:
            case (daddr[1:0])
                2'b00: byte_we = 4'b0001;
                2'b01: byte_we = 4'b0010;
                2'b10: byte_we = 4'b0100;
                2'b11: byte_we = 4'b1000;
            endcase
        2'b01:
            byte_we = daddr[1] ? 4'b1100 : 4'b0011;
        default:
            byte_we = 4'b1111;
    endcase
end

assign rom_iaddr  = iaddr;
assign rom_daddr  = daddr;
assign rom_dwdata = dwdata;
assign rom_dwe    = dsel_rom & dwe;

assign sram_dbe  = byte_we;

`ifndef SYNTHESIS
// simulation-only: old unified-SRAM probe names used by directed TB monitors
wire [3:0]  sram_dwe    = ((dsel_imem | dsel_dmem) & dwe) ? byte_we : 4'b0000;
wire [31:0] sram_daddr  = daddr & 32'h0FFFFFFF;
wire [31:0] sram_dwdata = dwdata;
`endif
assign dmem_we   = dsel_dmem & dwe;

// fetch: Boot ROM or IMEM; anything else is not executable -> NOP
assign idata = isel_rom  ? rom_idata  :
               isel_imem ? imem_idata : 32'h00000013;

assign ahb_haddr      = daddr;
assign ahb_hwdata     = dwdata;
assign ahb_hwrite     = dwe;
assign ahb_hsize      = {1'b0, dsize};
// ------------------------------------------------------------
// Slave handshake (rewritten for RTL signoff, Bug #18/#19)
//
// Old scheme bugs:
//  #18 reads were qualified only by ~dwe, so ANY instruction whose
//      ALU result fell in a peripheral window (e.g. lui s5,0x40003)
//      launched a phantom read (FIFO-pop side effects possible).
//  #19 apb_read_done stayed 1 after a read, so dstall was 0 in the
//      first cycle of the NEXT read -- the CPU consumed the previous
//      read's data. APB writes did not stall either, so a transfer
//      issued while the bridge was still in SETUP was dropped, and
//      PREADY wait states were ignored (fixed 2-cycle capture).
//
// New scheme (same for APB and ASCON): an access (dre|dwe) to the
// slave launches exactly one transfer and freezes the pipeline until
// the slave completes; completion registers the read data and raises
// a one-cycle `resp` which releases the stall. The CPU's Memory stage
// advances on that cycle, so `resp` also blocks a relaunch of the
// transfer that just finished.
// ------------------------------------------------------------
wire acc_en = dwe | dre;

// IMEM data side: wait-state slave inside soc_sram (IMEM port B)
wire imem_dacc = dsel_imem & acc_en;
assign imem_acc = imem_dacc;
assign imem_we  = dwe;

assign ahb_hsel_clint = dsel_clint & acc_en;
assign ahb_hsel_plic  = dsel_plic  & acc_en;

//  APB (via ahb_apb_bridge) 
wire apb_acc = dsel_apb & acc_en;
reg  apb_busy, apb_resp;
reg  [31:0] apb_rdata_r;
wire apb_launch = apb_acc & ~apb_busy & ~apb_resp;
assign ahb_hsel_apb = apb_launch;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        apb_busy    <= 1'b0;
        apb_resp    <= 1'b0;
        apb_rdata_r <= 32'b0;
    end else begin
        apb_resp <= 1'b0;
        if (apb_launch)
            apb_busy <= 1'b1;
        else if (apb_busy && apb_xfer_done) begin
            apb_busy    <= 1'b0;
            apb_resp    <= 1'b1;
            apb_rdata_r <= ahb_hrdata_apb;
        end
    end
end

//  ASCON (direct AHB slave, registered address/data phase) 
localparam A_IDLE = 2'd0, A_DATA = 2'd1, A_RDAT = 2'd2;
wire ascon_acc = dsel_ascon & acc_en;
reg  [1:0]  a_state;
reg         ascon_resp;
reg  [31:0] ascon_rdata_r;
wire ascon_launch = (a_state == A_IDLE) & ascon_acc & ~ascon_resp;
// Re-issue the address phase while the data phase is back-pressured.
assign ahb_hsel_ascon = ascon_launch | ((a_state == A_DATA) & ~ahb_hready_ascon);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        a_state       <= A_IDLE;
        ascon_resp    <= 1'b0;
        ascon_rdata_r <= 32'b0;
    end else begin
        ascon_resp <= 1'b0;
        case (a_state)
            A_IDLE: if (ascon_launch) a_state <= A_DATA;
            A_DATA: if (ahb_hready_ascon) begin
                        if (dwe) begin a_state <= A_IDLE; ascon_resp <= 1'b1; end
                        else           a_state <= A_RDAT;
                    end
            A_RDAT: begin
                        ascon_rdata_r <= ahb_hrdata_ascon;
                        ascon_resp    <= 1'b1;
                        a_state       <= A_IDLE;
                    end
            default: a_state <= A_IDLE;
        endcase
    end
end

assign dstall = (apb_acc & ~apb_resp) | (ascon_acc & ~ascon_resp) | (imem_dacc & ~imem_resp);

assign drdata = dsel_rom   ? rom_drdata        :
                dsel_dmem  ? dmem_rdata        :
                dsel_imem  ? imem_rdata        :
                dsel_clint ? ahb_hrdata_clint  :
                dsel_plic  ? ahb_hrdata_plic   :
                dsel_apb   ? apb_rdata_r       :
                dsel_ascon ? ascon_rdata_r     :
                             32'h00000000;

endmodule
