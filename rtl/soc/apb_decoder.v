`timescale 1ns/1ps
// ============================================================
// apb_decoder.v  APB Decoder for 5 Peripheral Slaves
//
// Address map (within APB region 0x4000_0000):
//   0x4000_0000 - 0x4000_0FFF  Timer
//   0x4000_1000 - 0x4000_1FFF  GPIO
//   0x4000_2000 - 0x4000_2FFF  UART
//   0x4000_3000 - 0x4000_3FFF  SPI
//   0x4000_4000 - 0x4000_4FFF  I2C
// ============================================================
module apb_decoder (
    // From AHB-APB bridge
    input  [31:0] PADDR,
    input  [31:0] PWDATA,
    input         PWRITE,
    input         PENABLE,
    input         PSEL_IN,   // bridge asserts this for APB region

    // To each peripheral
    output [31:0] PRDATA,
    output        PREADY,
    output        PSLVERR,

    // Timer
    output        PSEL_TIMER,
    input  [31:0] PRDATA_TIMER,
    input         PREADY_TIMER,

    // GPIO
    output        PSEL_GPIO,
    input  [31:0] PRDATA_GPIO,
    input         PREADY_GPIO,

    // UART
    output        PSEL_UART,
    input  [31:0] PRDATA_UART,
    input         PREADY_UART,

    // SPI
    output        PSEL_SPI,
    input  [31:0] PRDATA_SPI,
    input         PREADY_SPI,

    // I2C
    output        PSEL_I2C,
    input  [31:0] PRDATA_I2C,
    input         PREADY_I2C,
    // Boot Flash Controller
    output        PSEL_BOOTFLASH,
    input  [31:0] PRDATA_BOOTFLASH,
    input         PREADY_BOOTFLASH
);

//  Peripheral select decode 
wire [2:0] psel_idx = PADDR[14:12]; // bits[14:12] select peripheral

assign PSEL_TIMER = PSEL_IN && (psel_idx == 3'h0);
assign PSEL_GPIO  = PSEL_IN && (psel_idx == 3'h1);
assign PSEL_UART  = PSEL_IN && (psel_idx == 3'h2);
assign PSEL_SPI   = PSEL_IN && (psel_idx == 3'h3);
assign PSEL_I2C   = PSEL_IN && (psel_idx == 3'h4);
assign PSEL_BOOTFLASH = PSEL_IN && (psel_idx == 3'h5);

//  Read data mux 
assign PRDATA = PSEL_TIMER ? PRDATA_TIMER :
                PSEL_GPIO  ? PRDATA_GPIO  :
                PSEL_UART  ? PRDATA_UART  :
                PSEL_SPI   ? PRDATA_SPI   :
                PSEL_I2C   ? PRDATA_I2C   :
                PSEL_BOOTFLASH ? PRDATA_BOOTFLASH :
                             32'h00000000;

assign PREADY  = PSEL_TIMER ? PREADY_TIMER :
                 PSEL_GPIO  ? PREADY_GPIO  :
                 PSEL_UART  ? PREADY_UART  :
                 PSEL_SPI   ? PREADY_SPI   :
                 PSEL_I2C   ? PREADY_I2C   :
                 PSEL_BOOTFLASH ? PREADY_BOOTFLASH :
                              1'b1;

assign PSLVERR = 1'b0;

endmodule
