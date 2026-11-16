# 1-TOPS RV32IM SoC (SoCSmiths) — signoff evidence

Evidence for the 1-TOPS signoff checklist, gates G0–G6 (tools, spec, RTL, integration, verification).
Design: RV32IM + Zicsr, 5-stage pipeline, AHB/APB SoC with GPIO, UART, SPI, I2C, timer, CLINT, PLIC,
SPI-flash boot ROM and ASCON-128 crypto engine. Current implementation library: SCL180.

| Folder | Content | Gate |
|---|---|---|
| `rtl/` | RTL as verified (`rtl/rtl_soc.f` = file list) | G2, G3 |
| `docs/` | architecture, memory/interrupt map, boot flow, verification, signoff status, pinout | G1 |
| `logs/G0_tools/` | toolchain hello-world on SoC, Spike rv32ui run | G0 |
| `logs/G2_G3_lint/` | Cadence HAL lint (full log, summary, waiver review) | G2, G3 |
| `logs/G4_unit_core/` | unit / core / peripheral standalone testbench logs (26/26 PASS) | G4 |
| `logs/G5_isa/` | riscv-tests rv32ui + rv32um on the core (46/46 PASS) | G5 |
| `logs/G6_soc/bm/` | SoC bare-metal tests via real boot + negative boot tests (21/21) | G6 |
| `logs/G6_soc/integration/` | BFM bus suite (34/34), cross-peripheral + ASCON (11/11) | G6 |
| `logs/G6_soc/c_tests/` | bare-metal C test suite (12/12) | G6 |
| `logs/G6_soc/coverage/` | IMC code coverage (SoC 83.94 %, core 87.63 %), waivers | G5, G6 |
| `logs/regression_summary.txt` | one-command full RTL regression summary | G0, G4, G6 |

Simulator: Cadence Xcelium 22.09; coverage: IMC 15.2; lint: HAL; ISS: Spike 1.1.1-dev;
toolchain: riscv32-unknown-elf-gcc.
