`timescale 1ns/1ps
// ============================================================================
// chip_top.v -- t1c_riscv_soc with its SCL180 CIO250 pad ring
//
//   Core 1.8 V (VDD/VSS), I/O 3.3 V (VDDO/VSSO), 40 bonded pads:
//   26 signal pads + 4 VDD + 4 VSS + 3 VDDO + 3 VSSO.
//   Corner (pfrelr) and filler (pfeed*) cells are physical-only and are
//   inserted by Innovus (pd/scripts/02_floorplan.tcl).
//
//   Pad cells (tsl18cio250, 65 x 250 um):
//     pc3d01  CMOS input                     pc3d21d/u  Schmitt input, pull-down/up
//     pc3d01d/u CMOS input, pull-down/up      pc3o03     output 8 mA
//     pc3b03  bidir 8 mA (OEN active-low)     pc3b03u    bidir 8 mA + pull-up
//     pvdi/pv0i core VDD/VSS                  pvda/pv0a  I/O VDDO/VSSO
//   Pin order around the die: docs/06_pinout_and_die.md, pd/chip_top.io
// ============================================================================
module chip_top (
    input        CLK,
    input        RST,
    inout  [7:0] GPIO,
    input        UART_RXD,
    output       UART_TXD,
    output       UART_TXEN,
    output       SPI_SCLK,
    output       SPI_MOSI,
    input        SPI_MISO,
    output [3:0] SPI_SS_N,
    output       FLASH_SCLK,
    output       FLASH_MOSI,
    input        FLASH_MISO,
    output       FLASH_CS_N,
    inout        I2C_SCL,
    inout        I2C_SDA
);
    // core-side nets
    wire       clk, rst;
    wire [7:0] gpio_in, gpio_out, gpio_oen;
    wire       uart_rxd, uart_txd, uart_txen;
    wire       spi_sclk, spi_mosi, spi_miso;
    wire [3:0] spi_ss;
    wire       bf_sclk, bf_mosi, bf_miso, bf_cs_n;
    wire       scl_i, scl_o, scl_oen, sda_i, sda_o, sda_oen;

    t1c_riscv_soc u_soc (
        .clk(clk), .rst(rst),
        .gpio_in(gpio_in), .gpio_out(gpio_out), .gpio_oen(gpio_oen),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd), .uart_txen(uart_txen),
        .spi_sclk(spi_sclk), .spi_mosi(spi_mosi), .spi_miso(spi_miso), .spi_ss(spi_ss),
        .boot_spi_sclk(bf_sclk), .boot_spi_mosi(bf_mosi), .boot_spi_miso(bf_miso), .boot_spi_cs_n(bf_cs_n),
        .i2c_scl_i(scl_i), .i2c_scl_o(scl_o), .i2c_scl_oen(scl_oen),
        .i2c_sda_i(sda_i), .i2c_sda_o(sda_o), .i2c_sda_oen(sda_oen)
    );

    // ------------------------------------------------------------ inputs
    pc3d01  pad_clk        (.PAD(CLK),        .CIN(clk));
    pc3d21d pad_rst        (.PAD(RST),        .CIN(rst));       // Schmitt, pulled low
    pc3d21u pad_uart_rxd   (.PAD(UART_RXD),   .CIN(uart_rxd));  // idle high
    pc3d01d pad_spi_miso   (.PAD(SPI_MISO),   .CIN(spi_miso));
    pc3d01u pad_flash_miso (.PAD(FLASH_MISO), .CIN(bf_miso));

    // ----------------------------------------------------------- outputs
    pc3o03 pad_uart_txd   (.PAD(UART_TXD),   .I(uart_txd));
    pc3o03 pad_uart_txen  (.PAD(UART_TXEN),  .I(uart_txen));
    pc3o03 pad_spi_sclk   (.PAD(SPI_SCLK),   .I(spi_sclk));
    pc3o03 pad_spi_mosi   (.PAD(SPI_MOSI),   .I(spi_mosi));
    pc3o03 pad_spi_ss0    (.PAD(SPI_SS_N[0]), .I(spi_ss[0]));
    pc3o03 pad_spi_ss1    (.PAD(SPI_SS_N[1]), .I(spi_ss[1]));
    pc3o03 pad_spi_ss2    (.PAD(SPI_SS_N[2]), .I(spi_ss[2]));
    pc3o03 pad_spi_ss3    (.PAD(SPI_SS_N[3]), .I(spi_ss[3]));
    pc3o03 pad_flash_sclk (.PAD(FLASH_SCLK), .I(bf_sclk));
    pc3o03 pad_flash_mosi (.PAD(FLASH_MOSI), .I(bf_mosi));
    pc3o03 pad_flash_cs_n (.PAD(FLASH_CS_N), .I(bf_cs_n));

    // ------------------------------------------- GPIO (OEN active low)
    pc3b03 pad_gpio0 (.PAD(GPIO[0]), .I(gpio_out[0]), .OEN(~gpio_oen[0]), .CIN(gpio_in[0]));
    pc3b03 pad_gpio1 (.PAD(GPIO[1]), .I(gpio_out[1]), .OEN(~gpio_oen[1]), .CIN(gpio_in[1]));
    pc3b03 pad_gpio2 (.PAD(GPIO[2]), .I(gpio_out[2]), .OEN(~gpio_oen[2]), .CIN(gpio_in[2]));
    pc3b03 pad_gpio3 (.PAD(GPIO[3]), .I(gpio_out[3]), .OEN(~gpio_oen[3]), .CIN(gpio_in[3]));
    pc3b03 pad_gpio4 (.PAD(GPIO[4]), .I(gpio_out[4]), .OEN(~gpio_oen[4]), .CIN(gpio_in[4]));
    pc3b03 pad_gpio5 (.PAD(GPIO[5]), .I(gpio_out[5]), .OEN(~gpio_oen[5]), .CIN(gpio_in[5]));
    pc3b03 pad_gpio6 (.PAD(GPIO[6]), .I(gpio_out[6]), .OEN(~gpio_oen[6]), .CIN(gpio_in[6]));
    pc3b03 pad_gpio7 (.PAD(GPIO[7]), .I(gpio_out[7]), .OEN(~gpio_oen[7]), .CIN(gpio_in[7]));

    // ------------------- I2C open drain: drive I=o (0) when padoen=0
    pc3b03u pad_i2c_scl (.PAD(I2C_SCL), .I(scl_o), .OEN(scl_oen), .CIN(scl_i));
    pc3b03u pad_i2c_sda (.PAD(I2C_SDA), .I(sda_o), .OEN(sda_oen), .CIN(sda_i));

    // ------------------------------------------------- power / ground
    // Supply connectivity is made by Innovus global-net connections;
    // the cells are instantiated here so they are part of the netlist.
    pvdi pad_vdd_n  (.VDD());   pv0i pad_vss_n  (.VSS());
    pvdi pad_vdd_e  (.VDD());   pv0i pad_vss_e  (.VSS());
    pvdi pad_vdd_s  (.VDD());   pv0i pad_vss_s  (.VSS());
    pvdi pad_vdd_w  (.VDD());   pv0i pad_vss_w  (.VSS());
    pvda pad_vddo_n (.VDDO());  pv0a pad_vsso_n (.VSSO());
    pvda pad_vddo_e (.VDDO());  pv0a pad_vsso_e (.VSSO());
    pvda pad_vddo_s (.VDDO());  pv0a pad_vsso_s (.VSSO());
endmodule
