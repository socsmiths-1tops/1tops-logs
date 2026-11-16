`timescale 1ns/1ps

module apb_spi (
    input  wire        PCLK,
    input  wire        PRESETn,

    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:2]  PADDR,
    input  wire [31:0] PWDATA,

    output reg  [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    output wire        SCLK,
    output wire        MOSI,
    input  wire        MISO,
    output wire [3:0]  SS,

    output wire        SPIINT
);

    localparam ADDR_CTRL    = 6'h00;
    localparam ADDR_STATUS  = 6'h01;
    localparam ADDR_TXDATA  = 6'h02;
    localparam ADDR_RXDATA  = 6'h03;
    localparam ADDR_BAUD    = 6'h04;
    localparam ADDR_MODE    = 6'h05;
    localparam ADDR_INTCLR  = 6'h06;
    localparam ADDR_RXHOLD  = 6'h07; // non-destructive rx data read

    reg [31:0] ctrl_reg;
    reg [15:0] baud_reg;
    reg [1:0]  mode_reg;
    reg [7:0]  cs_delay_reg;
    reg [5:0]  data_bits_reg;

    reg done_sticky;
    reg [31:0] rx_data_hold; // holds rx_fifo_data stable for ENABLE phase
    reg tx_overflow;
    reg rx_overflow;
    reg irq_reg;

    wire enable_bit     = ctrl_reg[0];
    wire tx_enable_bit  = ctrl_reg[1];
    wire rx_enable_bit  = ctrl_reg[2];
    wire cs_enable_bit  = ctrl_reg[3];
    wire loopback_bit   = ctrl_reg[4];
    wire lsb_first_bit  = ctrl_reg[5];
    wire irq_enable_bit = ctrl_reg[6];
    wire [1:0] slave_select = ctrl_reg[9:8];
    wire hold_cs_bit    = ctrl_reg[10];

    wire [31:0] tx_fifo_data;
    wire [31:0] rx_fifo_data;
    wire [4:0]  tx_fifo_level;
    wire [4:0]  rx_fifo_level;
    wire        tx_fifo_full;
    wire        tx_fifo_empty;
    wire        rx_fifo_full;
    wire        rx_fifo_empty;

    reg tx_fifo_wr;
    reg tx_fifo_rd;
    reg rx_fifo_wr;
    reg rx_fifo_rd;

    wire [31:0] spi_rx_data;
    wire        spi_rx_valid;
    wire        spi_busy;
    wire        spi_done;
    wire        spi_tx_ready;
    wire        spi_start_valid;
    wire        cs_active;

    wire write_enable;
    wire rx_read_access;

    assign write_enable = PSEL & (~PENABLE) & PWRITE;
    assign rx_read_access = PSEL & (~PWRITE) & (~PENABLE) & (PADDR == ADDR_RXDATA);

    assign spi_start_valid = enable_bit & tx_enable_bit & (~tx_fifo_empty) & spi_tx_ready;

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    assign SS = (cs_active && cs_enable_bit) ? ~(4'b0001 << slave_select) : 4'b1111;
    assign SPIINT = irq_reg;

    spi_fifo tx_fifo (
        .clk     (PCLK),
        .resetn  (PRESETn),
        .wr_en   (tx_fifo_wr),
        .rd_en   (tx_fifo_rd),
        .wr_data (PWDATA),
        .rd_data (tx_fifo_data),
        .full    (tx_fifo_full),
        .empty   (tx_fifo_empty),
        .level   (tx_fifo_level)
    );

    spi_fifo rx_fifo (
        .clk     (PCLK),
        .resetn  (PRESETn),
        .wr_en   (rx_fifo_wr),
        .rd_en   (rx_fifo_rd),
        .wr_data (spi_rx_data),
        .rd_data (rx_fifo_data),
        .full    (rx_fifo_full),
        .empty   (rx_fifo_empty),
        .level   (rx_fifo_level)
    );

    spi_protocol_engine engine (
        .clk          (PCLK),
        .resetn       (PRESETn),
        .enable_i     (enable_bit),
        .tx_enable_i  (tx_enable_bit),
        .rx_enable_i  (rx_enable_bit),
        .cs_enable_i  (cs_enable_bit),
        .hold_cs_i    (hold_cs_bit),
        .loopback_i   (loopback_bit),
        .mode_i       (mode_reg),
        .baud_div_i   (baud_reg),
        .cs_delay_i   (cs_delay_reg),
        .data_bits_i  (data_bits_reg),
        .lsb_first_i  (lsb_first_bit),
        .tx_data_i    (tx_fifo_data),
        .tx_valid_i   (spi_start_valid),
        .tx_ready_o   (spi_tx_ready),
        .rx_data_o    (spi_rx_data),
        .rx_valid_o   (spi_rx_valid),
        .spi_clk_o    (SCLK),
        .spi_mosi_o   (MOSI),
        .spi_miso_i   (MISO),
        .cs_active_o  (cs_active),
        .busy_o       (spi_busy),
        .done_o       (spi_done)
    );

    always @(posedge PCLK or negedge PRESETn)
    begin
        if (!PRESETn)
        begin
            ctrl_reg      <= 32'd0;
            baud_reg      <= 16'd2;
            mode_reg      <= 2'd0;
            cs_delay_reg  <= 8'd0;
            data_bits_reg <= 6'd8;
        end
        else if (write_enable)
        begin
            case (PADDR)
                ADDR_CTRL:
                    ctrl_reg <= PWDATA;

                ADDR_BAUD:
                    baud_reg <= PWDATA[15:0];

                ADDR_MODE:
                begin
                    mode_reg     <= PWDATA[1:0];
                    cs_delay_reg <= PWDATA[15:8];

                    if (PWDATA[21:16] == 6'd8 ||
                        PWDATA[21:16] == 6'd16 ||
                        PWDATA[21:16] == 6'd32)
                        data_bits_reg <= PWDATA[21:16];
                end
                default: ;
            endcase
        end
    end

    always @(*)
    begin
        tx_fifo_wr = 1'b0;
        tx_fifo_rd = 1'b0;
        rx_fifo_wr = 1'b0;
        rx_fifo_rd = 1'b0;

        if (write_enable && (PADDR == ADDR_TXDATA) && !tx_fifo_full)
            tx_fifo_wr = 1'b1;

        if (spi_start_valid)
            tx_fifo_rd = 1'b1;

        if (spi_rx_valid && !rx_fifo_full)
            rx_fifo_wr = 1'b1;

        if (rx_read_access && !rx_fifo_empty)
            rx_fifo_rd = 1'b1;
    end

    always @(posedge PCLK or negedge PRESETn)
    begin
        if (!PRESETn)
        begin
            done_sticky  <= 1'b0;
            tx_overflow  <= 1'b0;
            rx_overflow  <= 1'b0;
            irq_reg      <= 1'b0;
            rx_data_hold <= 32'b0;
        end
        else
        begin
            // Hold rx_fifo_data stable through ENABLE phase
            if (rx_read_access && !rx_fifo_empty)
                rx_data_hold <= rx_fifo_data;
            if (spi_done)
                done_sticky <= 1'b1;

            if (write_enable && (PADDR == ADDR_TXDATA) && tx_fifo_full)
                tx_overflow <= 1'b1;

            if (spi_rx_valid && rx_fifo_full)
                rx_overflow <= 1'b1;

            if (write_enable && (PADDR == ADDR_INTCLR))
            begin
                if (PWDATA[0]) done_sticky <= 1'b0;
                if (PWDATA[1]) tx_overflow <= 1'b0;
                if (PWDATA[2]) rx_overflow <= 1'b0;
                if (PWDATA[3]) irq_reg     <= 1'b0;
            end
            else if (irq_enable_bit && (spi_done || tx_overflow || rx_overflow))
            begin
                irq_reg <= 1'b1;
            end
        end
    end

    always @(*)
    begin
        case (PADDR)
            ADDR_CTRL:
                PRDATA = ctrl_reg;

            ADDR_STATUS:
                PRDATA = {
                    8'd0,
                    rx_fifo_level,
                    tx_fifo_level,
                    5'd0,
                    irq_reg,
                    rx_overflow,
                    tx_overflow,
                    done_sticky,
                    spi_busy,
                    rx_fifo_empty,
                    rx_fifo_full,
                    tx_fifo_empty,
                    tx_fifo_full
                };

            ADDR_TXDATA:
                PRDATA = tx_fifo_data;

            ADDR_RXDATA:
                PRDATA = rx_data_hold; // stable through ENABLE

            ADDR_BAUD:
                PRDATA = {16'd0, baud_reg};

            ADDR_MODE:
                PRDATA = {10'd0, data_bits_reg, cs_delay_reg, 6'd0, mode_reg};

            ADDR_INTCLR:
                PRDATA = {28'd0, irq_reg, rx_overflow, tx_overflow, done_sticky};
            ADDR_RXHOLD:
                PRDATA = rx_data_hold; // non-destructive, no FIFO pop

            default:
                PRDATA = 32'd0;
        endcase
    end

endmodule

