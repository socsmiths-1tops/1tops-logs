`timescale 1ns/1ps
// ============================================================
// soc_sram.v  IMEM (64 KB) + DMEM (64 KB) built from SCL180 macros
//
//   IMEM 0x1000_0000 - 0x1000_FFFF   4 x rd3_4096x32 (16 KB each)
//   DMEM 0x1001_0000 - 0x1001_FFFF   4 x rd3_4096x32 (16 KB each)
//
// rd3_4096x32: true dual-port, synchronous read (address/controls
// sampled on CEx rising edge, data valid ~2.5-3.8 ns later at SS),
// word write only (no byte mask), CSBx/WEBx/OEBx active low.
// The model flags a read/write conflict combinationally whenever both
// ports are selected on the same address, so every CSB is asserted
// only in a cycle where that port is really used.
//
// IMEM
//   port A (1): instruction fetch. Address = PC the fetch stage will
//               hold next cycle (if_addr_next), so the word is valid
//               while PCF holds it -- same timing as the old array.
//   port B (2): data-side access (bootloader copy, constants, TB
//               markers). Wait-state slave: read = 2 cycles, full-word
//               write = 1 cycle, sub-word write = read-merge-write.
//               Port A is deselected while port B works (the pipeline
//               is frozen by dstall, so the fetch output just holds).
// DMEM (zero wait state)
//   port A (1): load read. Address = next Memory-stage address
//               (d_raddr_next, from Execute), data valid in Memory.
//   port B (2): store write in Memory. Sub-word stores merge into the
//               old word, which port A already read for the store.
//               Same-edge read of the word being written would be a
//               port conflict: port A is then deselected and the
//               merged write data is bypassed instead.
//
// Store data arrives lane-replicated (SB {4{b}}, SH {2{h}}), `dbe`
// selects the lanes.
// ============================================================
module soc_sram (
    input         clk,
    input         rst,

    // instruction fetch (IMEM port A)
    input  [31:0] if_addr_next,
    output [31:0] if_rdata,

    // DMEM, zero wait state
    input  [31:0] d_raddr_next,   // Memory-stage address for next cycle
    input  [31:0] daddr,          // current Memory-stage address
    input  [31:0] dwdata,         // lane-replicated store data
    input  [3:0]  dbe,            // byte lanes of the store
    input         dmem_we,        // store to DMEM in Memory stage
    output [31:0] dmem_rdata,     // word at daddr (Memory stage)

    // IMEM data-side wait-state slave (IMEM port B)
    input         imem_acc,       // load/store to IMEM in Memory stage
    input         imem_we,
    output reg    imem_resp,      // one-cycle completion, releases dstall
    output reg [31:0] imem_rdata
);

localparam DMEM_HI = 16'h1001;

// ---------------------------------------------------------------
// byte-lane merge
// ---------------------------------------------------------------
function [31:0] merge;
    input [31:0] old_w, new_w;
    input [3:0]  be;
    integer k;
    begin
        for (k = 0; k < 4; k = k + 1)
            merge[8*k +: 8] = be[k] ? new_w[8*k +: 8] : old_w[8*k +: 8];
    end
endfunction

// ===============================================================
// IMEM
// ===============================================================
wire [31:0] im_o1 [0:3];
wire [31:0] im_o2 [0:3];
reg  [1:0]  im_bank1_q, im_bank2_q;

// ---- data-side slave ----
localparam I_IDLE = 1'b0, I_RD = 1'b1;
reg        i_st;
wire       i_launch = (i_st == I_IDLE) & imem_acc & ~imem_resp;
wire       i_full   = (dbe == 4'b1111);
// port B operation this cycle (sampled at the coming edge)
wire       pb_read  = i_launch & ~(imem_we & i_full);
wire       pb_write = (i_launch & imem_we & i_full) | ((i_st == I_RD) & imem_we);
wire       pb_act   = pb_read | pb_write;
wire [31:0] im_old  = im_o2[im_bank2_q];
wire [31:0] pb_wdata = (i_st == I_RD) ? merge(im_old, dwdata, dbe) : dwdata;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        i_st       <= I_IDLE;
        imem_resp  <= 1'b0;
        imem_rdata <= 32'd0;
    end else begin
        imem_resp <= 1'b0;
        case (i_st)
            I_IDLE: if (i_launch) begin
                        if (imem_we & i_full) imem_resp <= 1'b1;   // written this edge
                        else                  i_st      <= I_RD;
                    end
            I_RD:   begin
                        if (!imem_we) imem_rdata <= im_old;
                        imem_resp <= 1'b1;                         // read done / merged write this edge
                        i_st      <= I_IDLE;
                    end
        endcase
    end
end

wire if_sel = (if_addr_next[31:16] == 16'h1000);

always @(posedge clk) begin
    if (if_sel & ~pb_act) im_bank1_q <= if_addr_next[15:14];
    if (pb_act)           im_bank2_q <= daddr[15:14];
end

assign if_rdata = im_o1[im_bank1_q];

genvar b;
generate for (b = 0; b < 4; b = b + 1) begin : g_imem
    rd3_4096x32 u_imem (
        .CE1  (clk),
        .CSB1 (~(if_sel & ~pb_act & (if_addr_next[15:14] == b))),
        .WEB1 (1'b1),
        .OEB1 (1'b0),
        .A1   (if_addr_next[13:2]),
        .I1   (32'd0),
        .O1   (im_o1[b]),
        .CE2  (clk),
        .CSB2 (~(pb_act & (daddr[15:14] == b))),
        .WEB2 (~pb_write),
        .OEB2 (1'b0),
        .A2   (daddr[13:2]),
        .I2   (pb_wdata),
        .O2   (im_o2[b])
    );
end endgenerate

// ===============================================================
// DMEM
// ===============================================================
wire [31:0] dm_o1 [0:3];
reg  [1:0]  dm_bank_q;
reg         byp_q;
reg  [31:0] byp_data_q;

wire        rd_sel   = (d_raddr_next[31:16] == DMEM_HI);
assign      dmem_rdata = byp_q ? byp_data_q : dm_o1[dm_bank_q];
wire [31:0] dm_wdata = merge(dmem_rdata, dwdata, dbe);
wire        conflict = dmem_we & rd_sel & (d_raddr_next[15:2] == daddr[15:2]);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        dm_bank_q  <= 2'd0;
        byp_q      <= 1'b0;
        byp_data_q <= 32'd0;
    end else begin
        dm_bank_q  <= d_raddr_next[15:14];
        byp_q      <= conflict;
        byp_data_q <= dm_wdata;
    end
end

generate for (b = 0; b < 4; b = b + 1) begin : g_dmem
    rd3_4096x32 u_dmem (
        .CE1  (clk),
        .CSB1 (~(rd_sel & ~conflict & (d_raddr_next[15:14] == b))),
        .WEB1 (1'b1),
        .OEB1 (1'b0),
        .A1   (d_raddr_next[13:2]),
        .I1   (32'd0),
        .O1   (dm_o1[b]),
        .CE2  (clk),
        .CSB2 (~(dmem_we & (daddr[15:14] == b))),
        .WEB2 (~dmem_we),
        .OEB2 (1'b0),
        .A2   (daddr[13:2]),
        .I2   (dm_wdata),
        .O2   ()
    );
end endgenerate

// ===============================================================
// Simulation-only back door (word index over 0x1000_0000..0x1001_FFFF:
// 0..16383 = IMEM, 16384..32767 = DMEM). Replaces the old soc.sram.mem[]
// array used by directed testbenches. Memories start zeroed in RTL sim
// (+SRAM_NO_INIT keeps the macro model's power-up X instead).
// ===============================================================
`ifndef SYNTHESIS
reg bd_inited = 1'b0;
task bd_init;                       // power-up contents, once
    integer i;
    begin
        if (!bd_inited) begin
            bd_inited = 1'b1;
            if (!$test$plusargs("SRAM_NO_INIT"))
                for (i = 0; i < 32768; i = i + 1) bd_poke(i, 32'd0);
        end
    end
endtask

task bd_write;
    input integer idx;
    input [31:0]  val;
    begin
        bd_init;
        bd_poke(idx, val);
    end
endtask

task bd_poke;
    input integer idx;
    input [31:0]  val;
    begin
        case ({idx[14], idx[13:12]})
            3'd0: g_imem[0].u_imem.rd3_4096x32_dualram.memory[idx[11:0]] = val;
            3'd1: g_imem[1].u_imem.rd3_4096x32_dualram.memory[idx[11:0]] = val;
            3'd2: g_imem[2].u_imem.rd3_4096x32_dualram.memory[idx[11:0]] = val;
            3'd3: g_imem[3].u_imem.rd3_4096x32_dualram.memory[idx[11:0]] = val;
            3'd4: g_dmem[0].u_dmem.rd3_4096x32_dualram.memory[idx[11:0]] = val;
            3'd5: g_dmem[1].u_dmem.rd3_4096x32_dualram.memory[idx[11:0]] = val;
            3'd6: g_dmem[2].u_dmem.rd3_4096x32_dualram.memory[idx[11:0]] = val;
            3'd7: g_dmem[3].u_dmem.rd3_4096x32_dualram.memory[idx[11:0]] = val;
        endcase
    end
endtask

function [31:0] bd_read;
    input integer idx;
    begin
        case ({idx[14], idx[13:12]})
            3'd0: bd_read = g_imem[0].u_imem.rd3_4096x32_dualram.memory[idx[11:0]];
            3'd1: bd_read = g_imem[1].u_imem.rd3_4096x32_dualram.memory[idx[11:0]];
            3'd2: bd_read = g_imem[2].u_imem.rd3_4096x32_dualram.memory[idx[11:0]];
            3'd3: bd_read = g_imem[3].u_imem.rd3_4096x32_dualram.memory[idx[11:0]];
            3'd4: bd_read = g_dmem[0].u_dmem.rd3_4096x32_dualram.memory[idx[11:0]];
            3'd5: bd_read = g_dmem[1].u_dmem.rd3_4096x32_dualram.memory[idx[11:0]];
            3'd6: bd_read = g_dmem[2].u_dmem.rd3_4096x32_dualram.memory[idx[11:0]];
            default: bd_read = g_dmem[3].u_dmem.rd3_4096x32_dualram.memory[idx[11:0]];
        endcase
    end
endfunction

// $readmemh image (word 0 = 0x1000_0000); only words present in the file
reg [31:0] bd_img [0:32767];
task bd_load;
    input [8*512-1:0] file;
    integer i;
    begin
        for (i = 0; i < 32768; i = i + 1) bd_img[i] = 32'bx;
        bd_init;
        $readmemh(file, bd_img);
        for (i = 0; i < 32768; i = i + 1)
            if (bd_img[i] !== 32'bx) bd_write(i, bd_img[i]);
    end
endtask

// whichever comes first at t=0 -- this or a TB preload -- zero-fills once
initial begin #0; bd_init; end
`endif

endmodule
