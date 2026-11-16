`timescale 1ns/1ps
// ============================================================
// t1c_riscv_soc.v  Top-level RV32IM MCU SoC
//
// Components:
//   - t1c_riscv_cpu (RV32IM + CSR)
//   - soc_sram      (64KB IMEM + 64KB DMEM, 8x SCL180 rd3_4096x32 dual-port macros)
//   - soc_interconnect
//   - ahb_apb_bridge
//   - apb_decoder
//   - clint
//   - plic
//   - apb_timer, apb_gpio, apb_uart, apb_spi, apb_i2c
// ============================================================
module t1c_riscv_soc (
    input  clk,
    input  rst,

    // GPIO
    input  [7:0]  gpio_in,
    output [7:0]  gpio_out,
    output [7:0]  gpio_oen,

    // UART
    input         uart_rxd,
    output        uart_txd,
    output        uart_txen,

    // SPI
    output        spi_sclk,
    output        spi_mosi,
    input         spi_miso,
    output [3:0]  spi_ss,
    // Boot Flash SPI (dedicated pins, separate from the general-
    // purpose SPI peripheral above)
    output        boot_spi_sclk,
    output        boot_spi_mosi,
    input         boot_spi_miso,
    output        boot_spi_cs_n,

    // I2C
    input         i2c_scl_i,
    output        i2c_scl_o,
    output        i2c_scl_oen,
    input         i2c_sda_i,
    output        i2c_sda_o,
    output        i2c_sda_oen
);

//  Reset synchronizer (async assert, sync release) 
wire rst_int;
reset_sync u_rst_sync (.clk(clk), .rst_async(rst), .rst_sync(rst_int));


wire dstall;

//  CPU signals 
wire [31:0] InstrAddr, InstrF, InstrAddrNext;
wire        MemWrite;
wire [31:0] WriteData, DataAdr, ReadData, DataAdrNext;
wire [1:0]  MemSize;
wire        MemUnsigned;
wire        irq_extern, irq_timer_cpu, irq_software;
wire [31:0] PCD, ResultW, InstrD;

//  Interconnect signals 
wire [31:0] imem_idata, imem_rdata, dmem_rdata;
wire [31:0] rom_iaddr, rom_idata, rom_daddr, rom_drdata, rom_dwdata;
wire        rom_dwe;
wire [3:0]  sram_dbe;
wire        dmem_we, imem_acc, imem_we, imem_resp;
wire [31:0] ahb_haddr, ahb_hwdata;
wire        ahb_hwrite;
wire [2:0]  ahb_hsize;
wire        ahb_hsel_apb, ahb_hsel_clint, ahb_hsel_plic;
wire [31:0] ahb_hrdata_apb, ahb_hrdata_clint, ahb_hrdata_plic;
wire        ahb_hsel_ascon;
wire        ahb_hready_ascon, apb_xfer_done;
wire        MemRead;
wire [31:0] ahb_hrdata_ascon;

//  APB bridge signals 
wire [31:0] PADDR, PWDATA, PRDATA_BUS;
wire        PWRITE, PENABLE, PSEL_BUS, PREADY_BUS;

//  APB peripheral selects + data 
wire        PSEL_TIMER, PSEL_GPIO, PSEL_UART, PSEL_SPI, PSEL_I2C, PSEL_BOOTFLASH;
wire [31:0] PRDATA_TIMER, PRDATA_GPIO, PRDATA_UART, PRDATA_SPI, PRDATA_I2C;
wire [31:0] PRDATA_BOOTFLASH;             // Bug #22: was undeclared (implicit 1-bit net)
wire        PREADY_BOOTFLASH;
wire        PREADY_TIMER, PREADY_GPIO, PREADY_UART, PREADY_SPI, PREADY_I2C;

//  Interrupt signals 
wire        irq_timer_peri, irq_gpio_comb;
wire        irq_uart, irq_spi, irq_i2c;
wire        uart_txint, uart_rxint;
wire        irq_timer_clint, irq_software_clint;

//////////////////////////////////////////////////
// CPU
//////////////////////////////////////////////////
t1c_riscv_cpu cpu (
    .clk          (clk),
    .reset        (rst_int),
    .InstrAddr    (InstrAddr),
    .InstrAddrNext(InstrAddrNext),
    .DataAdrNext  (DataAdrNext),
    .InstrF       (InstrF),
    .MemWrite     (MemWrite),
    .MemRead      (MemRead),
    .WriteData    (WriteData),
    .DataAdr      (DataAdr),
    .ReadData     (ReadData),
    .MemSize      (MemSize),
    .MemUnsigned  (MemUnsigned),
    .irq_extern   (irq_extern),
    .irq_timer    (irq_timer_clint),
    .irq_software (irq_software_clint),
    .PCD          (PCD),
    .ResultW      (ResultW),
    .InstrD       (InstrD),
    .MemStall     (dstall)
);

//////////////////////////////////////////////////
// INTERCONNECT
//////////////////////////////////////////////////
soc_interconnect intercon (
    .clk              (clk),
    .rst              (rst_int),
    .dstall           (dstall),
    .iaddr            (InstrAddr),
    .idata            (InstrF),
    .daddr            (DataAdr),
    .dwdata           (WriteData),
    .dwe              (MemWrite),
    .dre              (MemRead),
    .dsize            (MemSize),
    .drdata           (ReadData),
    .rom_iaddr        (rom_iaddr),
    .rom_idata        (rom_idata),
    .rom_daddr        (rom_daddr),
    .rom_drdata       (rom_drdata),
    .rom_dwdata       (rom_dwdata),
    .rom_dwe          (rom_dwe),
    .sram_dbe         (sram_dbe),
    .dmem_we          (dmem_we),
    .dmem_rdata       (dmem_rdata),
    .imem_acc         (imem_acc),
    .imem_we          (imem_we),
    .imem_resp        (imem_resp),
    .imem_rdata       (imem_rdata),
    .imem_idata       (imem_idata),
    .ahb_haddr        (ahb_haddr),
    .ahb_hwdata       (ahb_hwdata),
    .ahb_hwrite       (ahb_hwrite),
    .ahb_hsize        (ahb_hsize),
    .ahb_hsel_apb     (ahb_hsel_apb),
    .ahb_hsel_clint   (ahb_hsel_clint),
    .ahb_hsel_plic    (ahb_hsel_plic),
    .ahb_hrdata_apb   (ahb_hrdata_apb),
    .ahb_hrdata_clint (ahb_hrdata_clint),
    .ahb_hrdata_plic  (ahb_hrdata_plic),
    .ahb_hsel_ascon   (ahb_hsel_ascon),
    .ahb_hrdata_ascon (ahb_hrdata_ascon),
    .ahb_hready_ascon (ahb_hready_ascon),
    .apb_xfer_done    (apb_xfer_done)
);

//////////////////////////////////////////////////
// BOOT ROM
//////////////////////////////////////////////////
boot_rom #(.DEPTH(256)) bootrom (
    .clk    (clk),
    .rst    (rst_int),
    .iaddr  (rom_iaddr),
    .idata  (rom_idata),
    .daddr  (rom_daddr),
    .drdata (rom_drdata),
    .dwdata (rom_dwdata),
    .dwe    (rom_dwe)
);
//////////////////////////////////////////////////
// SRAM
//////////////////////////////////////////////////
soc_sram sram (
    .clk          (clk),
    .rst          (rst_int),
    .if_addr_next (InstrAddrNext),
    .if_rdata     (imem_idata),
    .d_raddr_next (DataAdrNext),
    .daddr        (DataAdr),
    .dwdata       (WriteData),
    .dbe          (sram_dbe),
    .dmem_we      (dmem_we),
    .dmem_rdata   (dmem_rdata),
    .imem_acc     (imem_acc),
    .imem_we      (imem_we),
    .imem_resp    (imem_resp),
    .imem_rdata   (imem_rdata)
);

//////////////////////////////////////////////////
// CLINT
//////////////////////////////////////////////////
clint clint_inst (
    .clk          (clk),
    .rst          (rst_int),
    .HADDR        (ahb_haddr),
    .HWDATA       (ahb_hwdata),
    .HWRITE       (ahb_hwrite),
    .HSEL         (ahb_hsel_clint),
    .HREADY       (1'b1),
    .HRDATA       (ahb_hrdata_clint),
    .HREADYOUT    (),
    .irq_timer    (irq_timer_clint),
    .irq_software (irq_software_clint)
);

//////////////////////////////////////////////////
// PLIC
//////////////////////////////////////////////////
plic_new plic_inst (
    .clk           (clk),
    .rst           (rst_int),
    .HADDR         (ahb_haddr),
    .HWDATA        (ahb_hwdata),
    .HWRITE        (ahb_hwrite),
    .HSEL          (ahb_hsel_plic),
    .HREADY        (1'b1),
    .HRDATA        (ahb_hrdata_plic),
    .HREADYOUT     (),
    .irq_timer_peri(irq_timer_peri),
    .irq_gpio      (irq_gpio_comb),
    .irq_uart      (irq_uart),
    .irq_spi       (irq_spi),
    .irq_i2c       (irq_i2c),
    .irq_extern    (irq_extern)
);

//////////////////////////////////////////////////
// AHB-APB BRIDGE
//////////////////////////////////////////////////
ahb_apb_bridge apb_bridge (
    .clk       (clk),
    .rst       (rst_int),
    .HADDR     (ahb_haddr),
    .HWDATA    (ahb_hwdata),
    .HWRITE    (ahb_hwrite),
    .HSIZE     (ahb_hsize),
    .HSEL      (ahb_hsel_apb),
    .HREADY    (1'b1),
    .HRDATA    (ahb_hrdata_apb),
    .HREADYOUT (),
    .xfer_done (apb_xfer_done),
    .PADDR     (PADDR),
    .PWDATA    (PWDATA),
    .PWRITE    (PWRITE),
    .PENABLE   (PENABLE),
    .PSEL      (PSEL_BUS),
    .PRDATA    (PRDATA_BUS),
    .PREADY    (PREADY_BUS),
    .PSLVERR   (1'b0)
);

//////////////////////////////////////////////////
// APB DECODER
//////////////////////////////////////////////////
apb_decoder apb_dec (
    .PADDR        (PADDR),
    .PWDATA       (PWDATA),
    .PWRITE       (PWRITE),
    .PENABLE      (PENABLE),
    .PSEL_IN      (PSEL_BUS),
    .PRDATA       (PRDATA_BUS),
    .PREADY       (PREADY_BUS),
    .PSLVERR      (),
    .PSEL_TIMER   (PSEL_TIMER),
    .PRDATA_TIMER (PRDATA_TIMER),
    .PREADY_TIMER (PREADY_TIMER),
    .PSEL_GPIO    (PSEL_GPIO),
    .PRDATA_GPIO  (PRDATA_GPIO),
    .PREADY_GPIO  (PREADY_GPIO),
    .PSEL_UART    (PSEL_UART),
    .PRDATA_UART  (PRDATA_UART),
    .PREADY_UART  (PREADY_UART),
    .PSEL_SPI     (PSEL_SPI),
    .PRDATA_SPI   (PRDATA_SPI),
    .PREADY_SPI   (PREADY_SPI),
    .PSEL_I2C     (PSEL_I2C),
    .PRDATA_I2C   (PRDATA_I2C),
    .PREADY_I2C   (PREADY_I2C),
    .PSEL_BOOTFLASH   (PSEL_BOOTFLASH),
    .PRDATA_BOOTFLASH (PRDATA_BOOTFLASH),
    .PREADY_BOOTFLASH (PREADY_BOOTFLASH)
);

//////////////////////////////////////////////////
// APB TIMER
//////////////////////////////////////////////////
apb_timer timer (
    .PCLK    (clk),
    .PRESETn (~rst_int),
    .PSEL    (PSEL_TIMER),
    .PADDR   (PADDR[7:2]),
    .PENABLE (PENABLE),
    .PWRITE  (PWRITE),
    .PWDATA  (PWDATA),
    .PRDATA  (PRDATA_TIMER),
    .PREADY  (PREADY_TIMER),
    .PSLVERR (),
    .EXTIN   (1'b0),
    .TIMERINT(irq_timer_peri)
);

//////////////////////////////////////////////////
// APB GPIO
//////////////////////////////////////////////////
apb_gpio #(.PortWidth(8)) gpio (
    .PCLK    (clk),
    .PRESETn (~rst_int),
    .PSEL    (PSEL_GPIO),
    .PADDR   (PADDR[7:2]),
    .PENABLE (PENABLE),
    .PWRITE  (PWRITE),
    .PWDATA  (PWDATA),
    .PRDATA  (PRDATA_GPIO),
    .PREADY  (PREADY_GPIO),
    .PSLVERR (),
    .PORTIN  (gpio_in),
    .PORTOUT (gpio_out),
    .PORTEN  (gpio_oen),
    .GPIOINT (),
    .COMBINT (irq_gpio_comb)
);

//////////////////////////////////////////////////
// APB UART
//////////////////////////////////////////////////
apb_uart uart (
    .PCLK    (clk),
    .PRESETn (~rst_int),
    .PSEL    (PSEL_UART),
    .PADDR   (PADDR[7:2]),
    .PENABLE (PENABLE),
    .PWRITE  (PWRITE),
    .PWDATA  (PWDATA),
    .PRDATA  (PRDATA_UART),
    .PREADY  (PREADY_UART),
    .PSLVERR (),
    .RXD     (uart_rxd),
    .TXD     (uart_txd),
    .TXEN    (uart_txen),
    .BAUDTICK(),
    .TXINT   (uart_txint),
    .RXINT   (uart_rxint)
);
// Bug #27: RXINT was left unconnected, so UART receive interrupts never
// reached the PLIC. One PLIC source for both; INTSTAT tells which fired.
assign irq_uart = uart_txint | uart_rxint;

//////////////////////////////////////////////////
// APB SPI
//////////////////////////////////////////////////
apb_spi spi (
    .PCLK    (clk),
    .PRESETn (~rst_int),
    .PSEL    (PSEL_SPI),
    .PENABLE (PENABLE),
    .PWRITE  (PWRITE),
    .PADDR   (PADDR[7:2]),
    .PWDATA  (PWDATA),
    .PRDATA  (PRDATA_SPI),
    .PREADY  (PREADY_SPI),
    .PSLVERR (),
    .SCLK    (spi_sclk),
    .MOSI    (spi_mosi),
    .MISO    (spi_miso),
    .SS      (spi_ss),
    .SPIINT  (irq_spi)
);

//////////////////////////////////////////////////
// APB I2C
//////////////////////////////////////////////////
apb_i2c #(.APB_ADDR_WIDTH(12)) i2c (
    .PCLK       (clk),
    .PRESETn    (~rst_int),
    .PADDR      (PADDR[11:0]),
    .PWDATA     (PWDATA),
    .PWRITE     (PWRITE),
    .PSEL       (PSEL_I2C),
    .PENABLE    (PENABLE),
    .PRDATA     (PRDATA_I2C),
    .PREADY     (PREADY_I2C),
    .PSLVERR    (),
    .interrupt_o(irq_i2c),
    .scl_pad_i  (i2c_scl_i),
    .scl_pad_o  (i2c_scl_o),
    .scl_padoen_o(i2c_scl_oen),
    .sda_pad_i  (i2c_sda_i),
    .sda_pad_o  (i2c_sda_o),
    .sda_padoen_o(i2c_sda_oen)
);


//////////////////////////////////////////////////
// BOOT FLASH CONTROLLER (dedicated, fixed-function)
//////////////////////////////////////////////////
assign PREADY_BOOTFLASH = 1'b1;
wire        bootflash_wr_en = PSEL_BOOTFLASH & PENABLE & PWRITE;
wire        bootflash_rd_en = PSEL_BOOTFLASH & PENABLE & ~PWRITE;

boot_flash_ctrl bootflash (
    .clk    (clk),
    .rst    (rst_int),
    .addr   (PADDR[4:0]),
    .wr_en  (bootflash_wr_en),
    .rd_en  (bootflash_rd_en),
    .wdata  (PWDATA),
    .rdata  (PRDATA_BOOTFLASH),
    .sclk_o (boot_spi_sclk),
    .mosi_o (boot_spi_mosi),
    .miso_i (boot_spi_miso),
    .cs_n_o (boot_spi_cs_n)
);

//////////////////////////////////////////////////
// ASCON ENGINE (AHB slave, direct -- 0x4000_6000)
//////////////////////////////////////////////////
ascon_ahb_wrapper ascon_eng (
    .clk              (clk),
    .rst_n            (~rst_int),
    .ahb_haddr        (ahb_haddr),
    .ahb_hwdata       (ahb_hwdata),
    .ahb_hwrite       (ahb_hwrite),
    .ahb_hsize        (ahb_hsize),
    .ahb_hsel_ascon   (ahb_hsel_ascon),
    .ahb_hrdata_ascon (ahb_hrdata_ascon),
    .ahb_hreadyout    (ahb_hready_ascon),
    .led_busy         (),
    .led_done         (),
    .led_chaos_ready  (),
    .led_tag_ok       (),
    .dbg_fsm          ()
);

endmodule
