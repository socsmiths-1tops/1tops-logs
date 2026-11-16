# HAL lint review — 2026-09-30 (RTL with SCL180 SRAM macros)

Run: `signoff/scripts/run_lint.sh` → `hal_full.log`, `hal_summary.txt`

| Tool | Errors | Warnings | Previous run (pre-SRAM rework) |
|---|---|---|---|
| halcheck | **0** | 2743 | 0 / 2690 |
| halsynth | **0** | 134 | 0 / 132 |
| halstruct | 296 (CBPAHI) | 681 | 277 / 653 |

## Dispositions

| Tag | Count | Where | Disposition |
|---|---|---|---|
| halstruct `*E,CBPAHI` | 296 | pipeline stages, interconnect | **Waived** (as before): combinational path crossing module boundaries — inherent to a pipelined CPU (forwarding, hazard, next-PC → SRAM address). Timing is closed by STA, not by module-boundary registering. +19 from the new sync-read SRAM address paths (next-PC / next-data-address). |
| `*N,CUVBPD`, halsynth `UNCINW` | 8 | `soc_sram` u_imem/u_dmem | **Expected**: `rd3_4096x32` is a hard macro; resolved from the SCL `.lib` in Genus/LEC (LEC compares all 8 as black boxes: equivalent). |
| halsynth `MULNBA` | +1 | `soc_sram` imem_resp | **Intentional**: default-then-set one-cycle pulse, same idiom as `apb_resp`/`ascon_resp`. |
| halsynth `BADFSM`/`EXTFSM`/`TRNMBT` | +2 | `soc_sram` i_st, interconnect | Style: 1-bit/2-bit handshake FSMs coded inline. No functional impact. |
| halsynth `NOLOCL` | 1 | `soc_sram` `merge()` | Style: function loop variable. |
| halcheck `LOGAND` | 2 | `soc_sram` l.102/117 | `&` between 1-bit signals ≡ `&&`. Cosmetic. |
| halcheck `USEPRT` | +16 | `soc_sram` | Expected: byte-offset bits [1:0] and region bits [31:16] of word addresses not used inside the wrapper (decoded in the interconnect). |
| halcheck `IPRTEX` | +19 | macro instances, SoC top | Constant tie-offs on macro ports (WEB1=1, OEB=0, I1=0). Intentional. |
| halcheck style (`MAXLEN`, `SEPLIN`, `NOBLKN`, `NBGEND`, `BITUNS`, `LRGOPR`, …) | rest | all | Coding-style; no functional effect. |

**Conclusion:** no functional lint issue in the reworked RTL. No new errors from halcheck/halsynth; halstruct delta fully explained.

## Re-run 2026-11-16 — ascon_updated integrated

| Tool | Errors | Warnings | Previous (2026-09-30) |
|---|---|---|---|
| halcheck | **0** | 2711 | 0 / 2743 |
| halsynth | **0** | 127 | 0 / 134 |
| halstruct | 337 (CBPAHI) | 1207 | 296 / 681 |

| Tag | Delta | Where | Disposition |
|---|---|---|---|
| halstruct `*E,CBPAHI` | +41 | `ascon_updated` (62 of 337 in ASCON) | **Waived** (same reason as above): combinational paths across ascon_core/chaos_core/peripheral boundaries; timing closed by STA (standalone synthesis WNS +800 ps at 100 MHz SS). |
| halstruct `*W,FFWASR` | +613 (all in ASCON) | `ascon_updated/*` | **Intentional**: ASCON uses a synchronous active-low reset (`always_ff @(posedge clk) if (!rst_n)`), driven by the SoC's synchronised reset. Verified in RTL and standalone GLS. |
| other halcheck/halsynth deltas | − | old `ascon/*` removed | Fewer warnings: old word assembler / unrolled permutation no longer in the build. |

**Conclusion:** 0 halcheck / halsynth errors after integration; all halstruct deltas explained.
