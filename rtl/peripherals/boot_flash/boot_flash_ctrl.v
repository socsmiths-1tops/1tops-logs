`timescale 1ns/1ps
// ============================================================
// boot_flash_ctrl.v  Streaming SPI-NOR read controller (boot path)
//
// One READ (0x03) command streams NBYTES bytes from flash address
// ADDR. Bytes are packed little-endian into 32-bit words; when a word
// is complete (or the stream ends) it is presented in DATA with
// STATUS.rx_valid=1 and SCLK is paused (held low, CS kept asserted)
// until software reads DATA. No FIFO, no overrun possible.
//
// SPI mode 0: MOSI driven on SCLK falling edge, MISO sampled on rising.
//
// Register map (APB offset):
//   0x00 CMD    W   0x03 = start READ (ignored while busy or NBYTES=0)
//                   0x00 = abort (CS high, clears rx_valid)
//   0x04 ADDR   RW  [23:0] flash byte address   (write only when idle)
//   0x08 NBYTES RW  [23:0] bytes to read        (write only when idle)
//   0x0C STATUS R   [0] busy  [1] rx_valid  [15:8] last byte received
//   0x10 DATA   R   received word; read pops it (rx_valid=0, SCLK resumes)
//   0x14 CLKDIV RW  [15:0] SCLK half-period in clk cycles (min 1, reset 4)
// ============================================================
module boot_flash_ctrl (
    input         clk,
    input         rst,

    input  [4:0]  addr,
    input         wr_en,
    input         rd_en,
    input  [31:0] wdata,
    output reg [31:0] rdata,

    output        sclk_o,
    output        mosi_o,
    input         miso_i,
    output        cs_n_o
);

localparam REG_CMD    = 5'h00;
localparam REG_ADDR   = 5'h04;
localparam REG_NBYTES = 5'h08;
localparam REG_STATUS = 5'h0C;
localparam REG_DATA   = 5'h10;
localparam REG_CLKDIV = 5'h14;

localparam CMD_READ   = 8'h03;

localparam S_IDLE = 2'd0, S_XFER = 2'd1, S_HOLD = 2'd2;

reg [1:0]  st;
reg [23:0] addr_r, nbytes_r;
reg [15:0] clkdiv_r, divcnt;
reg        sclk_r, cs_n_r, mosi_r;

reg        data_phase;   // 0: command/address out, 1: data in
reg [5:0]  cmd_bits;     // rising edges seen in command phase
reg [31:0] tx_sh;
reg [7:0]  byte_sh;
reg [2:0]  bit_idx;      // bits received in current byte
reg [1:0]  lane;         // byte lane within current word
reg [31:0] word_sh;
reg [23:0] remaining;    // bytes still to receive
reg        word_done;    // word completed on last rising edge

reg [31:0] rx_word;
reg        rx_valid;
reg [7:0]  last_byte;

assign sclk_o = sclk_r;
assign mosi_o = mosi_r;
assign cs_n_o = cs_n_r;

wire busy = (st != S_IDLE);
wire pop  = rd_en && (addr == REG_DATA) && rx_valid;
wire tick = (divcnt == clkdiv_r - 16'd1);
wire [7:0] byte_next = {byte_sh[6:0], miso_i};

always @(*) begin
    case (addr)
        REG_ADDR:   rdata = {8'b0, addr_r};
        REG_NBYTES: rdata = {8'b0, nbytes_r};
        REG_STATUS: rdata = {16'b0, last_byte, 6'b0, rx_valid, busy};
        REG_DATA:   rdata = rx_word;
        REG_CLKDIV: rdata = {16'b0, clkdiv_r};
        default:    rdata = 32'b0;
    endcase
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        st         <= S_IDLE;
        addr_r     <= 24'd0;
        nbytes_r   <= 24'd0;
        clkdiv_r   <= 16'd4;
        divcnt     <= 16'd0;
        sclk_r     <= 1'b0;
        cs_n_r     <= 1'b1;
        mosi_r     <= 1'b0;
        data_phase <= 1'b0;
        cmd_bits   <= 6'd0;
        tx_sh      <= 32'd0;
        byte_sh    <= 8'd0;
        bit_idx    <= 3'd0;
        lane       <= 2'd0;
        word_sh    <= 32'd0;
        remaining  <= 24'd0;
        word_done  <= 1'b0;
        rx_word    <= 32'd0;
        rx_valid   <= 1'b0;
        last_byte  <= 8'd0;
    end else begin
        // ---- register writes ----
        if (wr_en) begin
            case (addr)
                REG_ADDR:   if (!busy) addr_r   <= wdata[23:0];
                REG_NBYTES: if (!busy) nbytes_r <= wdata[23:0];
                REG_CLKDIV: if (!busy) clkdiv_r <= (wdata[15:0] == 16'd0) ? 16'd1 : wdata[15:0];
                REG_CMD: begin
                    if (wdata[7:0] == CMD_READ && !busy && nbytes_r != 24'd0) begin
                        st         <= S_XFER;
                        cs_n_r     <= 1'b0;
                        sclk_r     <= 1'b0;
                        divcnt     <= 16'd0;
                        tx_sh      <= {CMD_READ, addr_r};
                        mosi_r     <= CMD_READ[7];
                        data_phase <= 1'b0;
                        cmd_bits   <= 6'd0;
                        bit_idx    <= 3'd0;
                        lane       <= 2'd0;
                        word_sh    <= 32'd0;
                        remaining  <= nbytes_r;
                        word_done  <= 1'b0;
                        rx_valid   <= 1'b0;
                    end else if (wdata[7:0] == 8'h00) begin
                        st       <= S_IDLE;
                        cs_n_r   <= 1'b1;
                        sclk_r   <= 1'b0;
                        mosi_r   <= 1'b0;
                        rx_valid <= 1'b0;
                    end
                end
                default: ;
            endcase
        end

        // ---- DATA pop ----
        if (pop) begin
            rx_valid <= 1'b0;
            if (st == S_HOLD) begin
                st     <= S_XFER;
                divcnt <= 16'd0;
            end
        end

        // ---- SPI engine ----
        if (st == S_XFER && !(wr_en && addr == REG_CMD)) begin
            if (!tick) begin
                divcnt <= divcnt + 16'd1;
            end else begin
                divcnt <= 16'd0;
                if (!sclk_r) begin
                    // rising edge
                    sclk_r <= 1'b1;
                    if (!data_phase) begin
                        cmd_bits <= cmd_bits + 6'd1;
                    end else begin
                        byte_sh <= byte_next;
                        bit_idx <= bit_idx + 3'd1;
                        if (bit_idx == 3'd7) begin
                            last_byte <= byte_next;
                            remaining <= remaining - 24'd1;
                            lane      <= lane + 2'd1;
                            case (lane)
                                2'd0: word_sh[7:0]   <= byte_next;
                                2'd1: word_sh[15:8]  <= byte_next;
                                2'd2: word_sh[23:16] <= byte_next;
                                2'd3: word_sh[31:24] <= byte_next;
                            endcase
                            if (lane == 2'd3 || remaining == 24'd1) begin
                                rx_word <= (lane == 2'd0) ? {24'b0, byte_next} :
                                           (lane == 2'd1) ? {16'b0, byte_next, word_sh[7:0]} :
                                           (lane == 2'd2) ? {8'b0, byte_next, word_sh[15:0]} :
                                                            {byte_next, word_sh[23:0]};
                                rx_valid  <= 1'b1;
                                word_done <= 1'b1;
                                word_sh   <= 32'd0;
                                lane      <= 2'd0;
                            end
                        end
                    end
                end else begin
                    // falling edge
                    sclk_r <= 1'b0;
                    if (!data_phase) begin
                        if (cmd_bits == 6'd32) begin
                            data_phase <= 1'b1;
                            mosi_r     <= 1'b0;
                        end else begin
                            tx_sh  <= {tx_sh[30:0], 1'b0};
                            mosi_r <= tx_sh[30];
                        end
                    end else if (word_done) begin
                        word_done <= 1'b0;
                        if (remaining == 24'd0) begin
                            st     <= S_IDLE;
                            cs_n_r <= 1'b1;
                        end else if (rx_valid && !pop) begin
                            st <= S_HOLD;
                        end
                    end
                end
            end
        end
    end
end

endmodule
