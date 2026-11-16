`timescale 1ns/1ps

module spi_protocol_engine (
    input  wire        clk,
    input  wire        resetn,

    input  wire        enable_i,
    input  wire        tx_enable_i,
    input  wire        rx_enable_i,
    input  wire        cs_enable_i,
    input  wire        hold_cs_i,
    input  wire        loopback_i,
    input  wire [1:0]  mode_i,
    input  wire [15:0] baud_div_i,
    input  wire [7:0]  cs_delay_i,
    input  wire [5:0]  data_bits_i,
    input  wire        lsb_first_i,

    input  wire [31:0] tx_data_i,
    input  wire        tx_valid_i,
    output wire        tx_ready_o,

    output reg  [31:0] rx_data_o,
    output reg         rx_valid_o,

    output reg         spi_clk_o,
    output reg         spi_mosi_o,
    input  wire        spi_miso_i,

    output reg         cs_active_o,
    output wire        busy_o,
    output reg         done_o
);

    localparam ST_IDLE     = 3'd0;
    localparam ST_CS_DELAY = 3'd1;
    localparam ST_TRANSFER = 3'd2;
    localparam ST_DONE     = 3'd3;

    reg [2:0]  state;
    reg [15:0] clk_counter;
    reg [7:0]  cs_counter;
    reg [5:0]  bit_counter;
    reg [5:0]  bits_total;
    reg        edge_phase;

    reg [31:0] tx_latch;
    reg [31:0] rx_shift_reg;
    reg [31:0] rx_next;

    wire cpol;
    wire cpha;
    wire baud_tick;
    wire sample_edge;
    wire shift_edge;
    wire sample_bit;
    reg  spi_miso_sync;

    assign cpol = mode_i[1];
    assign cpha = mode_i[0];

    assign baud_tick = (clk_counter >= ((baud_div_i == 16'd0) ? 16'd1 : baud_div_i));

    assign sample_edge = (cpha == 1'b0) ? (edge_phase == 1'b0) : (edge_phase == 1'b1);
    assign shift_edge  = (cpha == 1'b0) ? (edge_phase == 1'b1) : (edge_phase == 1'b0);

    assign tx_ready_o = (state == ST_IDLE);
    assign busy_o     = (state != ST_IDLE);

    function get_bit;
        input [31:0] data;
        input [5:0]  total_bits;
        input [5:0]  index;
        input        lsb_first;
        integer pos;
        begin
            if (lsb_first)
                pos = index;
            else
                pos = total_bits - 1 - index;

            get_bit = data[pos];
        end
    endfunction

    function [31:0] put_bit;
        input [31:0] old_data;
        input [5:0]  total_bits;
        input [5:0]  index;
        input        lsb_first;
        input        bit_value;
        integer pos;
        begin
            put_bit = old_data;

            if (lsb_first)
                pos = index;
            else
                pos = total_bits - 1 - index;

            put_bit[pos] = bit_value;
        end
    endfunction

    // spi_miso_i is an external, asynchronous-looking pin with no
    // registering of its own (it is a real chip's pin in real silicon).
    // Register it on the fast system clock before use, so the sample
    // taken on a given sclk edge always reflects a fully-settled value
    // rather than racing the same-cycle update of spi_clk_o itself.
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            spi_miso_sync <= 1'b0;
        else
            spi_miso_sync <= spi_miso_i;
    end

    assign sample_bit = loopback_i ? get_bit(tx_latch, bits_total, bit_counter, lsb_first_i) : spi_miso_sync;

    always @(posedge clk or negedge resetn)
    begin
        if (!resetn)
        begin
            state        <= ST_IDLE;
            clk_counter  <= 16'd0;
            cs_counter   <= 8'd0;
            bit_counter  <= 6'd0;
            bits_total   <= 6'd8;
            edge_phase   <= 1'b0;
            tx_latch     <= 32'd0;
            rx_shift_reg <= 32'd0;
            rx_data_o    <= 32'd0;
            rx_valid_o   <= 1'b0;
            spi_clk_o    <= 1'b0;
            spi_mosi_o   <= 1'b0;
            cs_active_o  <= 1'b0;
            done_o       <= 1'b0;
        end
        else
        begin
            rx_valid_o <= 1'b0;
            done_o     <= 1'b0;

            case (state)
                ST_IDLE:
                begin
                    clk_counter <= 16'd0;
                    cs_counter  <= 8'd0;
                    bit_counter <= 6'd0;
                    edge_phase  <= 1'b0;
                    spi_clk_o   <= cpol;
                    if (!hold_cs_i)
                        cs_active_o <= 1'b0;

                    if (enable_i && tx_enable_i && tx_valid_i)
                    begin
                        tx_latch     <= tx_data_i;
                        rx_shift_reg <= 32'd0;

                        if (data_bits_i == 6'd8 || data_bits_i == 6'd16 || data_bits_i == 6'd32)
                            bits_total <= data_bits_i;
                        else
                            bits_total <= 6'd8;

                        spi_mosi_o <= get_bit(
                            tx_data_i,
                            (data_bits_i == 6'd8 || data_bits_i == 6'd16 || data_bits_i == 6'd32) ? data_bits_i : 6'd8,
                            6'd0,
                            lsb_first_i
                        );

                        if (cs_enable_i)
                            cs_active_o <= 1'b1;

                        if (cs_delay_i == 8'd0)
                            state <= ST_TRANSFER;
                        else
                            state <= ST_CS_DELAY;
                    end
                end

                ST_CS_DELAY:
                begin
                    spi_clk_o <= cpol;

                    if (cs_counter >= cs_delay_i)
                    begin
                        cs_counter <= 8'd0;
                        state <= ST_TRANSFER;
                    end
                    else
                    begin
                        cs_counter <= cs_counter + 8'd1;
                    end
                end

                ST_TRANSFER:
                begin
                    if (baud_tick)
                    begin
                        clk_counter <= 16'd0;
                        spi_clk_o   <= ~spi_clk_o;
                        edge_phase  <= ~edge_phase;

                        if (sample_edge)
                        begin
                            rx_next = put_bit(rx_shift_reg, bits_total, bit_counter, lsb_first_i, sample_bit);

                            if (rx_enable_i)
                                rx_shift_reg <= rx_next;

                            if (bit_counter == bits_total - 1'b1)
                            begin
                                rx_data_o  <= rx_enable_i ? rx_next : 32'd0;
                                rx_valid_o <= rx_enable_i;
                                done_o     <= 1'b1;
                                // NOTE: do NOT force spi_clk_o <= cpol here --
                                // that truncates the final bit's clock pulse to
                                // a half-cycle instead of the full cycle every
                                // other bit gets, which can corrupt the last
                                // bit sampled by a real external SPI slave.
                                // Let the normal ~spi_clk_o toggle (already
                                // issued above, unconditionally, for every
                                // baud_tick) complete the pulse naturally;
                                // ST_DONE's own clause sets spi_clk_o <= cpol
                                // afterward, which is sufficient.
                                state      <= ST_DONE;
                            end
                            else
                            begin
                                bit_counter <= bit_counter + 6'd1;
                            end
                        end

                        if (shift_edge)
                        begin
                            // Bug #26: was `bit_counter < bits_total-1`, so the
                            // final bit of every frame was never driven on MOSI
                            // (it kept the previous bit). Internal loopback hid
                            // it because it reads tx_latch directly.
                            if (tx_enable_i && bit_counter <= bits_total - 1'b1)
                                spi_mosi_o <= get_bit(tx_latch, bits_total, bit_counter, lsb_first_i);
                        end
                    end
                    else
                    begin
                        clk_counter <= clk_counter + 16'd1;
                    end
                end

                ST_DONE:
                begin
                    spi_clk_o   <= cpol;
                    if (!hold_cs_i)
                        cs_active_o <= 1'b0;
                    state       <= ST_IDLE;
                end

                default:
                begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
