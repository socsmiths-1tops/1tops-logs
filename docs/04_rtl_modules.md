# 4. RTL module reference

Every synthesizable file (`rtl_soc.f` lists them in compile order), what it
does, and how software sees it. Offsets are byte offsets from the block
base (see [03_architecture.md](03_architecture.md)).

## 4.1 Top level

| File | Module | Function |
|---|---|---|
| `rtl/chip/chip_top.v` | `chip_top` | Chip with pad ring: `t1c_riscv_soc` + 26 CIO250 signal pads + 14 power pads. Top for synthesis-with-pads and Innovus. |
| `rtl/soc/t1c_riscv_soc.v` | `t1c_riscv_soc` | SoC core: instantiates CPU, interconnect, boot ROM, SRAM, CLINT, PLIC, AHB→APB bridge, APB decoder, peripherals, reset synchroniser; wires interrupts (`irq_uart = TXINT | RXINT`). |
| `rtl/soc/reset_sync.v` | `reset_sync` | Active-high reset: asynchronous assert, 2-flop synchronous release. |

## 4.2 CPU (`rtl/core`)

| File | Module | Function |
|---|---|---|
| `t1c_riscv_cpu.v` | `t1c_riscv_cpu` | Pipeline top. Exports `InstrAddr`/`InstrAddrNext` (fetch), `DataAdr`/`DataAdrNext`, `WriteData` (lane-replicated), `MemWrite`, `MemRead`, `MemSize`; takes `MemStall` (wait states) and 3 interrupt lines. |
| `fetch.v` | `fetch` | PC register (`reset_ff`), next-PC mux (PC+4 / branch target / JALR / `mtvec` on trap / `mepc` on mret), IF/ID register, `PCFetchNext` for the IMEM macro. |
| `reset_ff.v` | `reset_ff` | PC flop with hold; holds PC at 0 one extra cycle after reset. |
| `decode.v` | `decode` | Register file read, immediate generation, controller, ID/EX register (flush → NOP bubble, hold on stall). Zeroes rs1/rs2 for LUI/AUIPC/JAL. |
| `controller.v`, `main_decoder.v`, `alu_decoder.v` | | Opcode → control signals; ALU operation select (BLTU uses its own unsigned compare code). Illegal opcodes decode to safe (no-write) controls. |
| `reg_file.v` | `reg_file` | 32×32 register file, x0 = 0, write-before-read in the same cycle. |
| `imm_extend.v` | `ImmExt` | I/S/B/U/J immediate formats. |
| `execute.v` | `execute` | Forwarding muxes, ALU, branch condition, PC target, MDU, CSR unit, EX/MEM register (holds on MemStall, bubbles while an M operation runs or a trap/mret is taken). |
| `alu.v` | `alu_unit` | ADD/SUB/logic/shifts/SLT(U); branch flags (eq, ne, lt, ltu, ge, geu). |
| `mdu_wrapper.v` | `mdu_wrapper` | RV32M: MUL/MULH/MULHSU/MULHU in 2 cycles (registered operands, one 33×33 multiplier); DIV/DIVU/REM/REMU 32-iteration restoring divider (33 cycles). x/0 and INT_MIN/−1 per spec. Handles `hold` (MemStall) and `kill` (trap). |
| `csr_unit.v` | `csr_unit` | mstatus/mie/mtvec/mepc/mcause/mip; interrupt arbitration (external > timer > software); trap entry/mret; gated while the pipeline is held (bug #17). |
| `hazard_unit.v` | `hazard_unit` | Forwarding selects, load-use stall, flush on branch/trap/mret, MemStall freezes everything, M-operation stall holds F/D/E. |
| `memory.v` | `memory` | MEM/WB register, byte-lane store data replication (bug #25), load data via `data_parser`. |
| `data_parser.v` | `data_parser` | LB/LH/LW/LBU/LHU byte/halfword select by address offset and sign/zero extension. |
| `writeback.v` | `writeback` | Result select: ALU / MDU / load / PC+4 / immediate or CSR. |
| `adder.v`, `mux2.v`, `mux3.v`, `mux4.v` | | Small datapath helpers. |

## 4.3 SoC infrastructure (`rtl/soc`)

| File | Module | Function |
|---|---|---|
| `soc_interconnect.v` | `soc_interconnect` | Address decode (ROM, IMEM, DMEM, CLINT, PLIC, APB, ASCON), byte enables, read-data mux, wait-state handshake: one transfer per access, pipeline frozen (`dstall`) until the slave responds. |
| `soc_sram.v` | `soc_sram` | IMEM + DMEM from 8 `rd3_4096x32` dual-port macros. IMEM port A fetch, port B data-side wait-state slave; DMEM port A zero-wait read, port B write with read-merge for sub-word stores and same-edge bypass. Simulation back door `bd_write/bd_read/bd_load`. |
| `boot_rom.v`, `boot_rom_image.vh` | `boot_rom` | 1 KB constant ROM; contents generated from `sw/boot/boot_loader.S` by `sw/boot/build_bootrom.sh`. `BOOTROM_LEGACY_PRELOAD` (sim only) makes it writable for legacy TBs. |
| `clint.v` | `clint` | RISC-V CLINT: 64-bit `mtime` (+1 per clock), `mtimecmp` (reset all-ones), `msip`. |
| `plic_new.v` | `plic_new` | 5 sources, 3-bit priorities (reset: timer 4, gpio 3, uart 7, spi 6, i2c 5), enable mask (reset: all enabled — delivery is still off until software sets `mie.MEIE` and `mstatus.MIE`), fixed threshold 0, claim/complete; level sources latch pending until complete. |
| `ahb_apb_bridge.v` | `ahb_apb_bridge` | AHB-Lite → APB (SETUP/ENABLE), waits for PREADY, returns `apb_xfer_done`. |
| `apb_decoder.v` | `apb_decoder` | PSEL per 4 KB window (timer, gpio, uart, spi, i2c, boot flash), PRDATA/PREADY mux. |

## 4.4 Peripherals (`rtl/peripherals`)

### Timer — `timer/apb_timer.v` (`0x4000_0000`)
Down-counter with reload; interrupt when it reaches 0. `EXTIN` is tied to 0
in the SoC, so the external gate/clock modes are not usable.

| Off | Reg | Bits |
|---|---|---|
| 0x00 | CTRL | [0] enable, [1] ext-in gate, [2] ext-in clock, [3] interrupt enable |
| 0x04 | VALUE | current count (write to load) |
| 0x08 | RELOAD | reload value |
| 0x0C | INTSTAT/INTCLR | read [0] interrupt; write 1 to clear |

### GPIO — `gpio/apb_gpio.v` (`0x4000_1000`)
8 pins, 2-flop input synchroniser, per-pin edge/level interrupts.

| Off | Reg | Function |
|---|---|---|
| 0x00 | DATA_IN | pin levels (RO) |
| 0x04 | DATA_OUT | output value |
| 0x08 | OUT_EN | 1 = drive the pin |
| 0x0C | INT_EN | interrupt enable |
| 0x10 | INT_TYPE | 1 = edge, 0 = level |
| 0x14 | INT_POL | 1 = rising/high, 0 = falling/low (bug #20) |
| 0x18 | INT_STAT | pending, write 1 to clear |

### UART — `uart/apb_uart.v` (`0x4000_2000`)
8N1, 1-byte TX and RX buffers. Bit time = `BAUDDIV` clocks
(`BAUDDIV[3:0]` = 1/16 fraction), i.e. `BAUDDIV = f_clk / baud` (868 for
115200 at 100 MHz).

| Off | Reg | Bits |
|---|---|---|
| 0x00 | CTRL | [0] TX en, [1] RX en, [2] TX irq en, [3] RX irq en |
| 0x04 | STATUS | [0] TX full, [1] RX full, [2] TX overrun, [3] RX overrun (w1c) |
| 0x08 | DATA | write: transmit byte |
| 0x0C | RXDATA | read: received byte |
| 0x10 | BAUDDIV | 20-bit divider |
| 0x14 | INTSTAT | [0] RX, [1] TX interrupt (w1c) |

### SPI — `spi/apb_spi.v`, `spi_fifo.v`, `spi_protocol_engine.v` (`0x4000_3000`)
Master, modes 0-3, 8/16/32-bit frames, MSB/LSB first, 4 chip selects,
16-entry × 32-bit TX and RX FIFOs. SCLK half period = `BAUD` clocks.

| Off | Reg | Bits |
|---|---|---|
| 0x00 | CTRL | [0] en [1] tx en [2] rx en [3] CS en [4] internal loopback [5] LSB first [6] irq en [9:8] CS select [10] hold CS |
| 0x04 | STATUS | [0] tx full [1] tx empty [2] rx full [3] rx empty [4] busy [5] done [6] tx ovf [7] rx ovf [8] irq [18:14] tx level [23:19] rx level |
| 0x08 | TXDATA | push TX FIFO |
| 0x0C | RXDATA | pop RX FIFO |
| 0x10 | BAUD | SCLK half-period in clocks |
| 0x14 | MODE | [1:0] mode, [15:8] CS-to-SCLK delay, [21:16] bits (8/16/32) |
| 0x18 | INTCLR | [0] done [1] tx ovf [2] rx ovf [3] irq (w1c) |
| 0x1C | RXHOLD | last RX word without popping |

### I2C — `i2c/apb_i2c.v`, `i2c_master_byte_ctrl.v`, `i2c_master_bit_ctrl.v` (`0x4000_4000`)
OpenCores-style master. SCL = f_clk / (5·(PRESCALE+1)).

| Off | Reg | Bits |
|---|---|---|
| 0x00 | PRESCALE | 16-bit |
| 0x04 | CTRL | [7] enable, [6] interrupt enable |
| 0x08 | RX | received byte |
| 0x0C | STATUS | [7] RxACK (1 = NACK) [6] busy [5] arbitration lost [1] transfer in progress [0] irq flag |
| 0x10 | TX | byte to send (address byte: addr7<<1 \| R/W) |
| 0x14 | CMD | [7] START [6] STOP [5] READ [4] WRITE [3] ACK (1 = send NACK) [0] IACK |

### Boot flash controller — `boot_flash/boot_flash_ctrl.v` (`0x4000_5000`)
Streams one SPI-NOR READ (0x03) of NBYTES from ADDR into 32-bit words
(little-endian), pausing SCLK until each word is read — no overrun.

| Off | Reg | Bits |
|---|---|---|
| 0x00 | CMD | 0x03 start READ, 0x00 abort |
| 0x04 | ADDR | 24-bit flash address |
| 0x08 | NBYTES | 24-bit byte count |
| 0x0C | STATUS | [0] busy [1] word valid [15:8] last byte |
| 0x10 | DATA | received word (read pops) |
| 0x14 | CLKDIV | SCLK half period (min 1, reset 4) |

### ASCON — `ascon_updated/*` (`0x4000_6000`, AHB)
ASCON-128 v1.2 AEAD engine (encrypt + decrypt/verify) with an internal
chaos-based key/nonce generator: a fresh key and nonce for every encryption,
never visible on the bus. (`rtl/peripherals/ascon/` is the earlier version,
no longer in `rtl_soc.f`.)

| File | Function |
|---|---|
| `ascon_ahb_wrapper.sv` | AHB-Lite slave front end (address bits [7:2], `hready` back-pressure). |
| `ascon_peripheral.sv` | Register file: 32 B message / 16 B AD buffers, CT/DOUT/TAG, read-only TAGIN, bus lock while busy. |
| `ascon_core.sv` | ASCON-128 FSM (init, AD, domain separation, message, finalisation, tag compare); one round unit, 2 rounds/clock (p12 = 6, p6 = 3 clocks). |
| `chaos_core.sv` | Fixed-point logistic map (μ = 3.99), two streams (key, nonce); 4 new iterations before each hand-out. |
| `config.sv`, `functions.sv`, `ascon_regs_pkg.sv` | Constants, round functions, register map. |

| Off | Reg | Bits |
|---|---|---|
| 0x00 | CTRL | [0] start [1] decrypt [2] soft reset [3] decrypt external CT (DIN) instead of stored CT |
| 0x04 | STATUS | [0] busy [1] done [2] chaos ready [3] ct valid [4] tag valid [5] tag ok [6] pt valid [7] key loaded [8] err |
| 0x08 | MSGLEN | message length 0..32 bytes |
| 0x0C | ADLEN | associated-data length 0..16 bytes |
| 0x10 | CTLEN | RO: length of the stored ciphertext |
| 0x20–0x3C | DIN0..7 | plaintext (encrypt) or external ciphertext (decrypt) |
| 0x40–0x4C | AD0..3 | associated data |
| 0x50–0x6C | CT0..7 | RO: ciphertext of the last encryption |
| 0x70–0x8C | DOUT0..7 | RO: decrypted plaintext, zero unless tag ok |
| 0x90–0x9C | TAG0..3 | RO: tag[127:96] .. tag[31:0] |
| 0xA0–0xAC | TAGIN0..3 | RO: expected tag = tag of the last encryption (hardware-loaded) |

Buffers are big-endian (first byte = [31:24] of word 0); unmapped offsets read
`0xDEADBEEF`. A decrypt always uses the key of the last encryption.
Limitation: the chaos seed comes from a power-on counter, so the key sequence
is deterministic per reset timing (a TRNG seed is the upgrade path).

## 4.5 Simulation-only models

| File | Function |
|---|---|
| `rtl/peripherals/spi/spi_flash_model.v` | SPI NOR flash (READ 0x03 / FAST READ 0x0B), `$readmemh`-loadable `mem[]`. |
| `sim/models/i2c_slave_mem.v` | I2C 256-byte register slave @0x50 (24C02-like). |
| `/home/install/scl180/.../rd3_4096x32.v` | SCL SRAM macro model (vendor). |
| `/home/install/scl180/iopad/cio250/.../zero/*.v` | CIO250 pad models (vendor, chip-level simulation). |
