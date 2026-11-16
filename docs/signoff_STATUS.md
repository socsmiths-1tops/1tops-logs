# RTL Signoff — Live Status

Branch: `rtl-signoff` (master untouched = GitHub backup). Env: `source signoff/env.sh`
(Xcelium 22.09, Genus 21.1, Conformal 21.1, IMC; JasperGold not installed → IFV).
One-command regression: `signoff/scripts/run_all.sh` → `signoff/reports/regression_summary.txt`.

## Checklist

| # | Item | Status |
|---|------|--------|
| 1 | Tool env on this server | DONE |
| 2 | Production boot flow (ROM → SPI flash → SRAM) | **DONE** — see docs/BOOT_FLOW.md |
| 3 | SoC bare-metal regression, all via real boot | **21/21 PASS** (17 BM incl. bm21_mem_subsystem + 4 negative boot) |
| 3a | Iterative divider (32-cycle) + 2-cycle multiplier (registered operands, for timing) | DONE, compliance 46/46, full regression green |
| 4 | ISA compliance rv32ui + rv32um (core) | **46/46 PASS** |
| 5 | BFM bus/peripheral suite | **34/34 PASS** |
| 6 | Cross-peripheral + ASCON integration | **11/11 PASS** |
| 6a | Standalone TBs (13 unit, 3 core, 8 peripheral, 2 legacy boot) — `run_standalone.sh` | **26/26 PASS** (TBs ported to current RTL, see log 2026-09-30) |
| 6b | C software stack + C tests (`sw/`, `sim/`) | **10/10 PASS** RTL, 9/9 chip (pads), 8/8 GLS, 5/5 chip GLS |
| 7 | Trap/interrupt pipeline defect (#14/15/16) | CLOSED (root causes below) |
| 8 | Lint (HAL) | halcheck/halsynth 0 errors; halstruct CBPAHI = style (waived) — `reports/lint/lint_review.md` |
| 9 | Code coverage (IMC 15.2, assembly + integration + BFM + 10 C tests) | **83.8%** (was 74.3%) — remaining: rst_sync toggle, APB dec 70%, PLIC 70%, CLINT 74%, bridge 78%, ASCON asm 67% → tests/waivers |
| 10 | Formal (IFV) | optional, not done |
| 11 | Synthesis (Genus 21.1, SCL180 SS, 100 MHz, 8x rd3_4096x32) → `gate_level_netlist/` | **MET**: WNS **+800 ps**, TNS 0, DRV clean; 15.24 mm² = 12.65 SRAM + 2.59 logic; 9395 flops |
| 11b | Chip synthesis with CIO250 pad ring → `gate_level_netlist/chip/` | **MET**: WNS +800 ps, I/O +4.5 / +1.8 ns; 40 pads |
| 11a | LEC (Conformal) RTL→netlist | **PASS**: core 9434 EQ, chip 9426 EQ, 0 non-EQ, 0 abort |
| 12 | Gate-level sim (SDF SS, real SRAM macro model, real boot) | **11/11 PASS** + C tests 8/8; chip netlist 5/5 |
| 13 | Physical-design prep (`pd/`, `rtl/chip/chip_top.v`) | pad ring, pinout, floorplan 5×5 mm, power plan — see docs/09 |

## Bugs found in this signoff pass

| # | Where | Bug | Fix |
|---|-------|-----|-----|
| 17 | `csr_unit.v` | Trap/mret/CSR write took effect while pipeline frozen by MemStall: E not flushed → instruction executed twice; held mret re-fired; trap could land on mret | gate with `hold` (StallM); regression `bm16_irq_apb_stall` fails without the fix |
| 18 | `soc_interconnect.v` | Any instruction whose ALU result hit a peripheral window launched a phantom read (e.g. `lui s5,0x40003`) | CPU output `MemRead`; all read selects qualified |
| 19 | `soc_interconnect.v`, bridge | `apb_read_done` stuck high → every APB read returned the *previous* read's data (why tests read twice); APB writes didn't stall → back-to-back write dropped; PREADY ignored | request/response handshake, stall until `xfer_done`; ASCON honours `bus_ready` |
| 20 | `apb_gpio.v` | IntPol=1 meant active-low (contradicted firmware); hidden by #19 dropping the write | IntPol=1 → rising/high |
| 21 | `soc_interconnect.v` | APB decode `<= 4` excluded boot flash @0x4000_5000 → boot flash unreachable | `<= 5` |
| 22 | `t1c_riscv_soc.v` | `PRDATA_BOOTFLASH` undeclared → implicit 1-bit net | declared [31:0] |
| 23 | `t1c_riscv_soc.v` | External reset used directly (no synchronizer) | `reset_sync.v` (async assert, sync release) |
| 24 | i2c, spi, bridge, csr | case without default; `full_case parallel_case` pragmas (sim/synth mismatch risk) | defaults added, pragmas removed |
| 26 | `spi_protocol_engine.v` | Last bit of every frame never driven on MOSI (`< bits-1` guard) | `<=`; found by C test t_spi |
| 27 | `t1c_riscv_soc.v` | UART RXINT unconnected → no RX interrupts | `irq_uart = TXINT \| RXINT`; found by C test t_uart |
| 25 | `memory.v` | Store data not placed on byte lanes: SB/SH to offset≠0 wrote the wrong byte (core compliance TB's memory shifted it itself, SoC SRAM did not) | replicate {4{b}}/{2{h}}; `bm21_mem_subsystem` fails without fix |
| T1 | `bm11_vg03_nested.S` | Nested ISR re-enabled MIE without saving mepc → runaway (the "VG03 failure") | save/restore mepc (spec-required) |
| T2 | `repro_trap*.S` | `sp=0x10000` unmapped → ISR stack lost (the "skipped checkpoint") | test bug, not a CPU defect |
| T3 | `gpio_ascon_loop.S` | readback stored after the checkpoint the TB checks | reordered |

VG06 "unexplained 0x22" = bug #19 (0x22 was the previous status-read byte).

## Known limitations (documented, not defects)
- Core implements M-mode interrupts only: no synchronous exceptions (ecall/ebreak/illegal/misaligned), no mscratch/misa/counters → rv32mi compliance N/A.
- Boot image is unauthenticated (CRC-32 integrity only). ASCON could be used for a signed/MAC'd boot later.
- Integration TBs (cross/ASCON) still use legacy SRAM preload (`+define+BOOTROM_LEGACY_PRELOAD`); boot path itself is covered by the 20-test regression.

## Decisions (user, 2026-09-29)
- SRAM (2026-09-30): 64 KB IMEM @0x1000_0000 + 64 KB DMEM @0x1001_0000, 8x SCL180 dual-port rd3_4096x32 (sync read). DMEM zero-wait (read addr from E, RMW store + bypass); IMEM fetch on port A, data side = wait-state slave on port B. Stacks at top of DMEM; boot image ≤ 64 KB.
- Target: 100 MHz, SS corner
- Divider: iterative (approved)

## Log
- 2026-09-29: env set up; baseline 13/15; bugs 17–20 fixed → 15/15.
- 2026-09-29: boot flow implemented (bugs 21–22 found on the way); all BM tests via real boot + negative tests; compliance, BFM, integration ported & green; reset sync; lint clean-up; bm16 added.
- 2026-09-29: iterative divider + shared multiplier; all suites green; license-retry wrapper (lab licenses are shared); Genus run started.
- 2026-09-29: synthesis met 100 MHz SS; GLS 10/10 through real boot; LEC stage1 PASS; coverage 74.3%.
- 2026-09-30: full verification of every TB under tb/: signoff suite 46+20+34+11 all PASS; new run_standalone.sh covers the remaining 26 TBs → 26/26 PASS.
  No RTL defects found. The legacy TBs predated signoff/earlier RTL changes and were ported: unconnected new ports tied
  inactive (hold, IsCSRW, trap/MemStall/DivStall, instr_execute, irq_*); iterative-divider latency in tb_execute/tb_mdu_wrapper;
  reference-model errors fixed (BLTU code 10001, shamt[4:0] for SRAI/SRLI, byte-lane select in loads, rs1/rs2 zeroed for
  LUI/AUIPC/JAL, M-ext only for R-type, -16>>>2=-4, InstrE reset = NOP, illegal opcode = safe controls); GPIO INTPOL (bug #20)
  and SPI RXDATA sampled in APB SETUP instead of ACCESS (TB bug; check tightened to exact loopback equality);
  tb_boot_flash_ctrl rewritten for the streaming READ controller. Xcelium work-lib corruption (DLNFS/DLNORD) occurs when
  sims run concurrently on this NFS -> run suites sequentially (runner retries).
- 2026-09-30: SRAM macros integrated (IMEM/DMEM split, sync-read pipeline hookup), bug #25 fixed; RTL: compliance 46/46, BM 21/21,
  BFM 34/34, integration 11/11, standalone 26/26. Genus → gate_level_netlist/ (met 100 MHz SS), LEC PASS.
  GLS now SDF-annotated (zero-delay GLS races with the macro model: pins change in the CE timestep).
- 2026-10-02/04: bare-metal C software stack (sw/), C system testbench (sim/), 10 C tests; bugs #26 (SPI MOSI last
  bit) and #27 (UART RX IRQ) found by them. 2-cycle MUL; synthesis with 0.8 ns margin (WNS +800 ps); chip_top with
  CIO250 pads synthesised, LEC, GLS; coverage 83.8 %; pd/ (pad ring, floorplan, power plan); docs/ written.

