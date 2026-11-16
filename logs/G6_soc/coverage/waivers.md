# Coverage waivers — t1c_riscv_soc

Coverage items that cannot be hit in this SoC configuration (structurally
constant or unreachable), with the reason. Everything else is to be covered
by tests (`sw/tests/*`, `tb/*`). Review and approve per item.

| ID | Instance | Item | Type | Reason |
|---|---|---|---|---|
| W1 | `u_rst_sync` | sync flops 0→1 toggle | toggle | Active-high reset synchroniser: flops go 1 during reset and 0 after release; a 0→1 transition only happens on a second reset assertion. Checked by review + GLS reset. |
| W2 | `apb_dec` | `PRDATA` fall-through (`psel_idx` 6/7), `PREADY` default | block/expr | Interconnect selects APB only for `daddr[15:12] ≤ 5`; indices 6/7 are unreachable. |
| W3 | `apb_dec` | `PWDATA[31:0]`, `PADDR[31:15]`, `PADDR[11:8]` toggle | toggle | `PWDATA` port unused inside the decoder; APB window is fixed `0x4000_0xxx-0x4000_5xxx`, high address bits constant; registers sit below offset 0x100. |
| W4 | `apb_dec` | `PRDATA_TIMER/GPIO/UART[31:8]`, `PREADY_*`, `PSLVERR` | toggle | 8-bit register blocks return zero upper bits; all APB slaves are zero-wait (`PREADY=1`), no slave errors. |
| W5 | `apb_bridge` | ENABLE→SETUP back-to-back branch, `PREADY=0` wait in ENABLE | block | Interconnect issues one transfer at a time and holds the CPU until `xfer_done` (bug #19 fix), so a new HSEL never coincides with ENABLE; no slave inserts wait states. |
| W6 | `apb_bridge` | `HADDR/HWDATA` upper-bit toggle into `addr_reg/wdata_reg` | toggle | Same as W3/W4: fixed APB window, narrow peripheral registers. |
| W7 | `clint_inst` | `mtime[63:32]` toggle | toggle | Needs 2³² cycles (43 s at 100 MHz). Carry logic is covered by synthesis/LEC; high-word compare is tested with `mtimecmp_hi` (`t_cov_misc`). |
| W8 | `plic_inst` | `prio[*][2:0]` toggle via `HWDATA[31:3]`, `threshold` | toggle | Priorities are 3 bits; threshold is a constant 0 by design (bare-metal). |
| W9 | `bootrom` | unused ROM words (66 of 256 used) | block | Constant table; unused entries return NOP. |
| W10 | `ascon_eng` | decrypt tag compare (`tag_ok`) true branch | expr | Expected-tag input tied to 0 in `ascon_peripheral.sv` (documented hardware limitation). |
| W11 | `cpu.csr` | `mstatus` bits other than MIE/MPIE, `mcause[30:5]` | toggle | Not implemented / not writable bits read as constants; full-width `mepc/mtvec/mcause` walked in `t_regs`. |

Waiver file for IMC (apply with `load -refinement`) is to be generated from
this list once the licence server is available (`signoff/scripts/run_coverage.sh`
→ IMC `exclude` commands).
