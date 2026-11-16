# 3. SoC architecture

`t1c_riscv_soc` is a single-clock RV32IM microcontroller: a 5-stage pipelined
core, 64 KB instruction memory, 64 KB data memory, a boot ROM that loads the
application from an external SPI NOR flash, and AHB/APB peripherals. The
silicon target is SCL180 (180 nm) at **100 MHz** (SS corner).

## 3.1 Block diagram

```
                         ┌─────────────────────────────────────────────┐
  CLK ─┐                 │                 t1c_riscv_soc               │
  RST ─┴─► reset_sync ──►│  t1c_riscv_cpu (RV32IM + Zicsr, 5 stages)   │
                         │     │ fetch (next-PC)        │ data (E/M)    │
                         │     ▼                        ▼               │
                         │  ┌───────────────── soc_interconnect ──────┐ │
                         │  │ address decode, wait-state handshake    │ │
                         │  └─┬───────┬────────┬───────┬──────┬──────┬┘ │
                         │    │       │        │       │      │      │  │
                         │ boot_rom  soc_sram  clint  plic  AHB→APB  ascon (AHB)
                         │  1 KB    IMEM 64K           5 src  bridge     │
                         │          DMEM 64K                  │         │
                         │       (8× rd3_4096x32)       apb_decoder      │
                         │                    ┌──────┬────┬──┴──┬─────┬───────┐
                         │                  timer  gpio uart  spi   i2c  boot_flash_ctrl
                         └─────────────────────┼─────┼────┼─────┼─────┼────────┼──────┘
                                                    GPIO UART  SPI   I2C   SPI NOR flash
```

## 3.2 Memory map

| Region | Base | Size | Module | Notes |
|---|---|---|---|---|
| Boot ROM | `0x0000_0000` | 1 KB | `boot_rom` | first-stage bootloader, reset vector |
| CLINT | `0x0200_0000` | 64 KB | `clint` | `msip` +0x0, `mtimecmp` +0x4000, `mtime` +0xBFF8 |
| PLIC | `0x0C00_0000` | 64 MB window | `plic_new` | priority +4·id, pending +0x1000, enable +0x2000, claim +0x200004 |
| **IMEM** | `0x1000_0000` | 64 KB | `soc_sram` | code; fetched on macro port A, data access via port B (wait states) |
| **DMEM** | `0x1001_0000` | 64 KB | `soc_sram` | data, bss, heap, stack; zero wait state. Last 256 B = sim mailbox |
| Timer | `0x4000_0000` | 4 KB | `apb_timer` | APB |
| GPIO | `0x4000_1000` | 4 KB | `apb_gpio` | APB, 8 pins |
| UART | `0x4000_2000` | 4 KB | `apb_uart` | APB |
| SPI | `0x4000_3000` | 4 KB | `apb_spi` | APB, master |
| I2C | `0x4000_4000` | 4 KB | `apb_i2c` | APB, master |
| Boot flash ctrl | `0x4000_5000` | 4 KB | `boot_flash_ctrl` | APB, SPI-NOR READ streamer |
| ASCON | `0x4000_6000` | 4 KB | `ascon_ahb_wrapper` | AHB slave, crypto |

Every register is listed in `sw/bsp/include/soc.h` and in
[04_rtl_modules.md](04_rtl_modules.md).

## 3.3 CPU

* RV32I + M (multiply/divide) + Zicsr, machine mode only.
* Pipeline: Fetch → Decode → Execute → Memory → Writeback, full forwarding
  (E←M, E←W), load-use stall, branches/jumps resolved in Execute (2-cycle
  penalty), no branch prediction.
* Multiply: 2 cycles in Execute (operands registered, then a 33×33
  multiplier). Divide/remainder: iterative, 33 cycles. The pipeline holds
  while an M operation runs.
* CSRs: `mstatus` (MIE, MPIE), `mie`, `mtvec` (direct), `mepc`, `mcause`,
  `mip` (read-only). Interrupts: machine external (PLIC), timer (CLINT),
  software (CLINT). **No synchronous exceptions** (ecall/ebreak/illegal/
  misaligned are not trapped), no `mscratch`, no counters.
* Memory interface: next-fetch address (`InstrAddrNext`) and next data
  address (`DataAdrNext`) are exported so the synchronous-read SRAM macros
  return data in the cycle the pipeline needs it.

## 3.4 Memories

| | IMEM | DMEM |
|---|---|---|
| Macros | 4 × `rd3_4096x32` (16 KB) | 4 × `rd3_4096x32` |
| Port A | instruction fetch (next PC) | load read (address from Execute) |
| Port B | data-side access: read 2 cycles, write 1, sub-word write 3 | store write in Memory stage |
| Loads/stores | via wait-state slave (`dstall`) | 0 wait states |
| Sub-word stores | read-merge-write on port B | old word read on port A in E, merged write on port B in M; same-word back-to-back accesses bypassed |

The macros have no byte mask, so SB/SH are merged in the wrapper. Store
data on the bus is lane-replicated (SB `{4{b}}`, SH `{2{h}}`).

## 3.5 Buses and wait states

The CPU's Memory stage drives one data bus. `soc_interconnect` decodes the
address and, for slow targets (APB peripherals, ASCON, IMEM data side),
raises `dstall` which freezes the whole pipeline until the slave
completes. DMEM, boot ROM, CLINT and PLIC respond in the same cycle.

## 3.6 Interrupts

```
 timer ─┐
 gpio  ─┤  PLIC (5 sources, priority 1-7, threshold 0)  ──► mip.MEIP (mcause 0x8000000B)
 uart  ─┤  id: 1 timer 2 gpio 3 uart 4 spi 5 i2c
 spi   ─┤
 i2c   ─┘
 CLINT mtime >= mtimecmp ──────────────────────────────► mip.MTIP (mcause 0x80000007)
 CLINT msip ───────────────────────────────────────────► mip.MSIP (mcause 0x80000003)
```

Software: `crt0.S` saves the caller-saved registers and calls
`irq_dispatch()`, which claims/completes the PLIC and calls the handler
registered with `irq_attach()` (see [05_software_guide.md](05_software_guide.md)).

## 3.7 Clock and reset

* One clock domain (`clk`, 100 MHz). The CLINT `mtime` increments every clock.
* `rst` (active high) is synchronised by `reset_sync` (asynchronous assert,
  2-flop synchronous release). Peripherals use the same synchronised reset.

## 3.8 Boot flow

```
 reset ─► PC = 0x0000_0000 (Boot ROM)
          1. read 16-byte header from SPI flash offset 0 (boot_flash_ctrl)
             magic "1TOP" 0x504F5431 | length | CRC-32 | entry
          2. check magic, 4 <= length <= 64 KB and length % 4 == 0
          3. stream the payload into IMEM @0x1000_0000, CRC-32 on the fly
          4. check CRC and entry (inside the loaded image, word aligned)
          5. jump to entry  ─► crt0 _start ─► main()
 on error: GPIO[7:0] driven with E1 (magic) E2 (length) E3 (CRC) E4 (entry)
```

The flash image is produced by `sw/tools/mkimage.py` (run automatically by
`make`). Details: `signoff/docs/BOOT_FLOW.md`.
