# 7. RTL signoff status — 100 MHz, SCL180

Date: 2026-10-02 · Branch `rtl-signoff`

## 7.1 Checklist

| # | Item | Result | Evidence |
|---|---|---|---|
| 1 | Functional regression (RTL) | **PASS** — compliance 46/46, assembly 21/21, BFM 34/34, integration 11/11, unit/core/peripheral 26/26 | `signoff/reports/regression_summary.txt` |
| 2 | C software tests (RTL) | **PASS 10/10** (≈ 190 checks) through the real boot | `sim/reports/sw_tests_rtl.txt` |
| 3 | C software tests, chip with pads (RTL + CIO250 models) | **PASS 9/9** | `sim/reports/sw_tests_chip.txt` |
| 4 | Synthesis, SoC core (Genus, SS 1.62 V 125 °C) | **MET** — WNS **+800 ps**, TNS 0, no DRV | `gate_level_netlist/reports/` |
| 5 | Synthesis, chip with pads | **MET** — WNS +800 ps; I/O: inputs +4.5 ns, outputs +1.8 ns | `gate_level_netlist/chip/reports/` |
| 6 | LEC RTL ↔ netlist (Conformal) | **EQUIVALENT** — core 9 434 points, chip 9 426 points, 0 non-equivalent / abort | `gate_level_netlist/lec/lec.log`, `chip/lec/lec.log` |
| 7 | GLS, SoC netlist + SDF (SS), real SRAM model | **PASS** — boot suite 11/11, C tests 8/8 (cycle-identical to RTL) | `signoff/logs/gls_gls/`, `sim/reports/sw_tests_gls.txt` |
| 8 | GLS, chip netlist with pads + SDF | **PASS 5/5** (cpu, gpio, i2c, spi, uart) | `sim/reports/sw_tests_chipgls.txt` |
| 9 | Lint (HAL) | **0 functional issues**; style items reviewed | `signoff/reports/lint/lint_review.md` |
| 10 | Clock / reset | single clock domain (no CDC); reset synchroniser; all async inputs (UART RX, GPIO, I2C, boot MISO) synchronised in their peripherals | review |
| 11 | Code coverage (block/expr/toggle/FSM) | **83.8 %** (was 74.3 %) | `signoff/reports/coverage/` |
| 12 | Formal property checks | not done (optional; see 7.5) | — |

## 7.2 Timing at 100 MHz (SS 1.62 V 125 °C, 0.2 ns uncertainty)

| Path group | Slack |
|---|---|
| Worst register-to-register (ASCON chaos generator) | +800 ps |
| CPU pipeline (branch resolve → ID/EX flush, multiplier) | ≥ +800 ps |
| Into SRAM macros (next-PC → IMEM CSB/A) | +802 ps |
| Out of SRAM macros (DMEM read → load register) | +4.3 ns |
| Chip inputs (pads) / outputs (pads, 10 pF board load) | +4.5 ns / +1.8 ns |

Synthesis targets 0.8 ns of extra margin so placement and routing have
headroom; reports and the hand-off SDC use the real constraints.
Changes made for timing: 2-cycle multiplier (registered operands).

## 7.3 Area and power (Genus, SS)

| | |
|---|---|
| SRAM macros | 12.65 mm² (8 × rd3_4096x32) |
| Standard-cell logic | 2.59 mm² (ASCON 1.9 mm²), 9 395 flip-flops |
| Pads | 40 × 65 × 250 µm (+ corners/fillers) |
| Power (default activity) | ≈ 280 mW; SRAM power under-reported (macro .lib has no internal-power tables) |

## 7.4 Defects found and fixed in signoff (27)

Full list in [06_verification.md](06_verification.md) §6.3 and
`signoff/STATUS.md`. The last two (#26 SPI last bit, #27 UART RX interrupt)
were found by the C software tests.

## 7.5 Open items and waivers

| Item | Status / recommendation |
|---|---|
| Coverage 83.8 % → ≥ 95 % | remaining holes: reset synchroniser toggle (2 flops), APB decoder read mux (70 %), PLIC/CLINT upper register bits, APB bridge error paths, ASCON partial-bit padding. Add targeted tests or document waivers. |
| Formal | optional: assertions on the wait-state handshake and the DMEM bypass/port-conflict logic. |
| Post-route signoff | STA with extracted parasitics, GLS with routed SDF and timing checks on, IR drop, DRC/LVS — physical-design phase. |

## 7.6 Known limitations (by design)

* No synchronous exceptions (illegal instruction, ecall/ebreak, misaligned
  access are not trapped); no `mscratch`, no performance counters.
* Boot image integrity is CRC-32 only (not authenticated).
* ASCON: key/nonce internal and not software-readable; decrypt+verify not
  usable from software (expected-tag input tied off); ciphertext blocks are
  paced by software (sticky `ct_valid`).
* Timer external input (`EXTIN`) tied low: external gate/clock modes unused.
* PLIC sources are enabled at reset (delivery still gated by `mie`/`mstatus`).
* Fetching the exact IMEM word that is being written through the data port
  in the same cycle returns X (self-modifying code is unsupported).
