# 2. Folder structure

```
rv32im/
├── README.md                    project overview + quick start
├── docs/                        this documentation (start at docs/README.md)
├── rtl_soc.f                    RTL file list (compile order) for the SoC
│
├── rtl/                         synthesizable design
│   ├── core/                    RV32IM pipeline (fetch, decode, execute, mdu, csr, ...)
│   ├── soc/                     SoC top, interconnect, SRAM wrapper, boot ROM, CLINT, PLIC, bridge
│   ├── peripherals/             timer, gpio, uart, spi, i2c, boot_flash, ascon
│   └── chip/chip_top.v          SoC + SCL180 CIO250 pad ring (top for physical design)
│
├── sw/                          bare-metal software
│   ├── Makefile                 make APP=<app> [sim|gls]  -> sw/build/<app>/
│   ├── bsp/include/             soc.h (all registers), bsp.h, driver headers
│   ├── bsp/src/                 crt0.S, irq, uart, printf, gpio, timer, clint, spi, i2c, ascon, libc
│   ├── bsp/linker/soc.ld        IMEM/DMEM layout
│   ├── apps/                    example programs (hello, blinky, uart_echo, irq_demo)
│   ├── tests/                   self-checking C tests (t_cpu, t_irq, t_uart, ...)
│   ├── boot/                    Boot ROM bootloader (boot_loader.S) + ROM image generator
│   ├── tools/mkimage.py         .bin -> SPI flash image (header + CRC)
│   └── build/                   generated (git-ignored)
│
├── sim/                         system simulation for C programs
│   ├── tb/tb_soc_app.v          100 MHz board model: flash, UART console, GPIO/SPI/I2C
│   ├── models/i2c_slave_mem.v   I2C slave model
│   ├── run_app.sh               boot one built app (rtl | gls)
│   ├── run_sw_tests.sh          all sw/tests -> sim/reports/
│   └── build/                   simulator snapshots (generated)
│
├── tb/                          block / SoC testbenches (RTL verification)
│   ├── unit/ core/ peripherals/ soc/   unit, core, peripheral and SoC testbenches
│   └── baremetal/               assembly tests used by the SoC regression
│
├── signoff/                     RTL signoff flows and results
│   ├── env.sh                   tool environment (source this first)
│   ├── STATUS.md                live signoff checklist
│   ├── scripts/                 run_all, compliance, bm regression, integration,
│   │                            standalone, lint, coverage, gls
│   ├── reports/                 regression summary, lint, coverage
│   ├── tb/                      GLS testbench, monitors
│   └── docs/BOOT_FLOW.md        boot ROM protocol
│
├── gate_level_netlist/          synthesis (Genus) of the SoC core (no pads)
│   ├── scripts/genus_soc.tcl    netlist, sdc, sdf, reports, innovus/, lec/
│   └── chip/                    synthesis of chip_top (with pads) -> used by pd/
│       ├── scripts/genus_chip.tcl, constraints/chip_top.sdc
│       └── chip_top_netlist.v, chip_top.sdc, chip_top.sdf, reports/, lec/, innovus/
│
├── pd/                          physical-design preparation (Innovus)
│   ├── chip_top.io              pad ring order
│   ├── scripts/                 mmmc, init, floorplan, powerplan, run_fp.tcl
│   └── reports/                 floorplan/power reports, screenshots
│
├── scripts/                     helpers used by flows (elf2mem.py, link*.ld, clean_workdir.sh)
└── legacy/                      superseded files, kept for reference
```

## Generated files

`sw/build/`, `sim/build/`, `signoff/build/`, `signoff/logs/`, the large
synthesis outputs (`*.sdf`, `*.db`) and older tool scratch files in the top
directory are not version-controlled. `scripts/clean_workdir.sh` lists
(and with `--yes` deletes) leftover scratch files from older flows.
