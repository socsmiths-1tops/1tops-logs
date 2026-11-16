# 6. Verification

All results below are on the current RTL (with the SCL180 SRAM macros) and
are reproducible with the listed commands (after `source signoff/env.sh`).

## 6.1 Levels

| Level | What | Command | Result |
|---|---|---|---|
| Unit | 13 core-block testbenches (ALU, decode, execute, MDU, CSR, hazard, memory, ...) | `signoff/scripts/run_standalone.sh unit` | 13/13 pass, ~205 k checks |
| Core | `t1c_riscv_cpu` with program memories | `run_standalone.sh core` | 3/3 |
| ISA compliance | riscv-tests rv32ui + rv32um on the core | `signoff/scripts/run_compliance.sh` | **46/46** |
| Peripherals | standalone GPIO, timer, UART, I2C, SPI, boot flash ctrl, ASCON | `run_standalone.sh periph` | 8/8 |
| SoC, assembly | 17 bare-metal programs + 4 corrupted-image tests, all through the real boot | `signoff/scripts/run_bm_regression.sh` | **21/21** |
| SoC, bus | bus-functional-model suite (every register, wait states) | `run_tb.sh tb/soc/tb_soc_bfm.v ...` (in `run_all.sh`) | **34/34** |
| SoC, integration | cross-peripheral loops + ASCON | `signoff/scripts/run_integration.sh` | **11/11** |
| **SoC, C software** | 9 self-checking C programs through the real boot | `make -C sw tests` / `sim/run_sw_tests.sh rtl` | **9/9** |
| **Chip (pads)** | same 9 C programs on `chip_top` with SCL180 pad models | `sim/run_sw_tests.sh chip` | **9/9** |
| Gate level | SoC netlist + SDF (SS), real boot, SRAM macro model | `signoff/scripts/run_gls.sh`, `sim/run_sw_tests.sh gls` | see 6.4 |
| Equivalence | RTL vs netlist (Conformal) | `lec -XL -dofile gate_level_netlist/lec/rtl2gate.do` | see 6.4 |
| Lint | HAL | `signoff/scripts/run_lint.sh` | 0 functional issues |
| Coverage | block/expr/toggle/FSM, merged over SoC runs | `signoff/scripts/run_coverage.sh` | see 6.5 |

One command for the whole RTL regression: `signoff/scripts/run_all.sh`
→ `signoff/reports/regression_summary.txt`.

## 6.2 C test programs (`sw/tests`)

| Test | Checks |
|---|---|
| `t_cpu` | RV32IM arithmetic incl. MULH/MULHSU/MULHU, DIV/REM corner cases (÷0, INT_MIN/−1), dependent divide chain, shifts, LB/LH/LBU/LHU sign extension, recursion, indirect calls, switch tables, 64-bit multiply/divide via libgcc (29 checks) |
| `t_irq` | CSR read/write incl. csrrwi/csrrsi/csrrci, mtime, CLINT timer interrupt, masked pending interrupt (`mip`), software interrupt, PLIC + APB timer periodic interrupts during computation (21) |
| `t_uart` | BAUDDIV, polled loopback, overrun flag, RX interrupts through the PLIC |
| `t_gpio` | 16 output→input patterns, set/clear/toggle, rising/falling edge and high/low level interrupts (11) |
| `t_spi` | 48 frames: modes 0-3 × 8/16/32 bit × CS0-3 × MSB/LSB first over the pins, 6-frame FIFO burst, CS hold, internal loopback, done interrupt |
| `t_i2c` | prescaler, register read of power-up data, 4-byte write + read back, current-address read, NACK from absent device (11) |
| `t_ascon` | encryption of 1/4/7/8/13/24-byte messages, tag valid |
| `t_bootflash` | reads its own image back from the SPI flash: header magic, length, CRC-32, payload == IMEM |
| `t_mem` | crt0 `.data`/`.rodata` copy and `.bss` clear, DMEM pattern over all banks, sub-word read-modify-write, IMEM data-side write/merge, memcpy/memset, deep recursion (13) |

Testbench board model (`sim/tb/tb_soc_app.v`): 100 MHz clock, SPI NOR
flash with the program image, UART console decoder (TXD looped to RXD),
GPIO[7:4] driven from GPIO[3:0], SPI MISO = MOSI, I2C bus with pull-ups and
a 256-byte slave at 0x50. A program ends the simulation by returning from
`main` (exit code 0 = pass).

## 6.3 Bugs found by verification

| # | Block | Defect | Found by |
|---|---|---|---|
| 17 | csr_unit | trap/mret/CSR write while pipeline frozen → instruction executed twice | assembly regression |
| 18 | interconnect | phantom peripheral reads from non-load instructions | BFM |
| 19 | interconnect/bridge | APB read returned previous data; writes dropped; PREADY ignored | BFM |
| 20 | gpio | interrupt polarity inverted | BFM |
| 21 | interconnect | boot flash window not decoded | boot flow |
| 22 | soc top | `PRDATA_BOOTFLASH` implicit 1-bit net | lint |
| 23 | soc top | no reset synchroniser | review |
| 24 | i2c/spi/bridge/csr | case without default, `full_case` pragmas | lint |
| 25 | memory | SB/SH to offset ≠ 0 wrote the wrong byte | `bm21_mem_subsystem` |
| **26** | spi engine | last bit of every frame never driven on MOSI | **C test `t_spi`** |
| **27** | soc top | UART RX interrupt not connected to the PLIC | **C test `t_uart`** |

## 6.4 Gate level and equivalence

Filled in from the final netlist run (see [07_signoff_status.md](07_signoff_status.md)).

## 6.5 Coverage

See [07_signoff_status.md](07_signoff_status.md) and
`signoff/reports/coverage/`.
