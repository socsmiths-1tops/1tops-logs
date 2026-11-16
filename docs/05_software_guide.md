# 5. Software guide — writing bare-metal C for the SoC

## 5.1 Toolchain

| Item | Value |
|---|---|
| Compiler | `riscv32-unknown-elf-gcc` 16.1 (`/home/onetops/1tops/tool_chain/riscv32-install/bin`) |
| ISA / ABI | `-march=rv32im_zicsr -mabi=ilp32` (no compressed, no atomics, no FPU) |
| C library | none from the toolchain; the BSP supplies `printf`, `memcpy`, ... (`sw/bsp/src`) |
| Runtime libgcc | linked for 64-bit arithmetic helpers |

The toolchain directory must be on `PATH` (see [01_quick_start.md](01_quick_start.md)).

## 5.2 What happens to your program

```
 sw/apps/myapp/*.c  ──make──►  myapp.elf ──objcopy──► myapp.bin ──mkimage──► flash.bin / flash.hex
                                (code @0x1000_0000,        raw image        16-byte header + image
                                 data image after it)                        (magic, length, CRC32, entry)

 power-on ─► Boot ROM reads flash.bin from the SPI NOR flash, copies the image
            to IMEM, checks the CRC, jumps to 0x1000_0000
         ─► crt0.S: stack + gp, copy .rodata/.data to DMEM, clear .bss,
            mtvec = trap_entry, call main()
         ─► main() returns ─► exit(code) ─► sim_exit(code) (simulation stops;
            on silicon the CPU idles)
```

## 5.3 Memory layout (`sw/bsp/linker/soc.ld`)

| Section | Runs from | Stored in image | Notes |
|---|---|---|---|
| `.text` | IMEM `0x1000_0000` | yes | `_start` first |
| `.rodata`, `.data`, `.sdata` | DMEM `0x1001_0000` | yes (after `.text`) | copied by crt0 — constants are read at 0 wait states |
| `.bss`, `.sbss` | DMEM | no | zeroed by crt0 |
| heap | DMEM, after `.bss` | no | `_heap_start` .. `_heap_end` (no malloc provided) |
| stack | top of DMEM, 4 KB default | no | `make STACK_SIZE=8192` |
| sim mailbox | `0x1001_FF00`–`0x1001_FFFF` | no | reserved |

Limits: code + constants + initialised data ≤ 64 KB (flash image);
data + bss + stack ≤ 64 KB − 256 B. The linker stops with an error if either
overflows.

## 5.4 Building and running

```bash
cd rv32im
make -C sw APP=hello            # build only  -> sw/build/hello/
make -C sw APP=hello sim        # build + boot in RTL simulation
make -C sw APP=hello gls        # build + boot on the gate-level netlist (slow)
make -C sw APP=/path/to/mydir   # any directory with .c/.S files
make -C sw list | tests | clean
```

| Variable | Default | Meaning |
|---|---|---|
| `CPU_HZ` | 100000000 | clock the code assumes (delays, baud rates) |
| `UART_BAUD` | 115200 | console baud for `make` (silicon) |
| `SIM_BAUD` | 3125000 | console baud used by `sim`/`gls` (fast simulation) |
| `OPT` | `-O2` | optimisation |
| `STACK_SIZE` | 4096 | bytes |
| `CFLAGS_EXTRA` | | extra compiler flags |

Outputs in `sw/build/<app>/`: `.elf`, `.dis` (disassembly with source),
`.map`, `.size`, `<app>.bin`, **`flash.bin`** (program into the SPI NOR flash
at offset 0) and `flash.hex` (simulation), plus `sim_rtl.log` /
`uart_rtl.txt` after a simulation.

## 5.5 A new application in three steps

```bash
mkdir sw/apps/myapp
cat > sw/apps/myapp/main.c <<'EOF'
#include "bsp.h"
int main(void)
{
    uart_init(UART_BAUD);
    printf("hello from myapp\n");
    gpio_set_output(0xFF);
    gpio_write(0x3C);
    return 0;                 /* 0 = PASS in simulation */
}
EOF
make -C sw APP=myapp sim
```

Expected:
```
  CC/LD  myapp  (baud 3125000, 100000000 Hz)
  SIM    myapp [rtl]  (log: sw/build/myapp/sim_rtl.log)
[uart] hello from myapp
EXIT code=0
SIM RESULT: PASS
```

Several `.c` files and private headers in the app directory are compiled
together automatically.

## 5.6 BSP API (`#include "bsp.h"`)

**Console / UART** — `uart_init(baud)`, `uart_putc`, `uart_puts`,
`uart_getc` (blocking), `uart_getc_nb` (−1 if empty), `uart_rx_ready`,
`uart_flush`; `printf`, `snprintf`, `vprintf`, `puts`, `putchar`
(`%d %i %u %x %X %o %c %s %p %%`, width, `-`, `0`; no floating point).

**GPIO** — `gpio_set_output(mask)`, `gpio_set_input(mask)`,
`gpio_write(v)`, `gpio_set/clear/toggle(mask)`, `gpio_read()`;
interrupts: `gpio_irq_config(mask, GPIO_IRQ_EDGE_RISE|EDGE_FALL|LEVEL_HIGH|LEVEL_LOW)`,
`gpio_irq_status()`, `gpio_irq_clear(mask)`, `gpio_irq_disable(mask)`.
For level interrupts mask (`gpio_irq_disable`) before clearing.

**Timer** — `timer_start(period_cycles, irq)`, `timer_stop`,
`timer_value`, `timer_irq_pending`, `timer_irq_clear`.

**CLINT / delays** — `clint_mtime()` (64-bit, 1 tick per clock),
`clint_timer_after(cycles)`, `clint_set_timecmp`, `clint_timer_off`,
`clint_soft_irq(on)`, `delay_cycles`, `delay_us`, `delay_ms`.

**SPI** — `spi_init(&cfg)` with `spi_cfg_t {sclk_hz, mode, bits, cs,
lsb_first, cs_delay, loopback}`, `spi_transfer(word)`,
`spi_transfer_buf(tx, rx, n)`, `spi_hold_cs(on)`.

**I2C** — `i2c_init(scl_hz)`, `i2c_write(addr7, buf, n)`,
`i2c_read(addr7, buf, n)`, `i2c_write_reg(addr7, reg, buf, n)`,
`i2c_read_reg(addr7, reg, buf, n)`; return `I2C_OK`, `I2C_ENACK`,
`I2C_EARB`, `I2C_ETIMEOUT`.

**ASCON** — `ascon_encrypt(pt, n, ad, ad_len, ct, tag[16])` (n ≤ 32,
ad_len ≤ 16; fresh hardware key per call), `ascon_decrypt_stored(ad, ad_len,
pt, &n)` (decrypt + verify the last ciphertext), `ascon_decrypt(ct, n, ad,
ad_len, pt)` (external ciphertext, checked against the last tag),
`ascon_reset()`; return `ASCON_OK`, `ASCON_EAUTH` (tag mismatch, plaintext
withheld), `ASCON_EINVAL`, `ASCON_EHW`, `ASCON_TIMEOUT`.

**Interrupts** — `irq_attach(IRQ_ID_TIMER|GPIO|UART|SPI|I2C, handler, prio)`,
`irq_detach(id)`, `irq_attach_mtimer(h)`, `irq_attach_msoft(h)`,
`irq_global_enable/disable()`, `irq_save()/irq_restore()`. Handlers are plain
`void f(void)` functions; they must clear the peripheral's own flag (the
dispatcher does the PLIC claim/complete).

**Registers** — every register as a macro in `soc.h`, e.g.
`UART_BAUDDIV = 868;`, `if (SPI_STATUS & SPI_ST_BUSY) ...`; CSR access with
`csr_read(mstatus)`, `csr_write`, `csr_set`, `csr_clear`.

**Tests / simulation** — `TEST_CHECK(cond, name)`, `TEST_EQ(got, exp, name)`,
`TEST_DONE()` (prints and returns the failure count), `sim_exit(code)`.

## 5.7 Interrupt example

```c
#include "bsp.h"
static volatile int ticks;
static void on_timer(void) { ticks++; timer_irq_clear(); }

int main(void)
{
    uart_init(UART_BAUD);
    irq_attach(IRQ_ID_TIMER, on_timer, 1);
    irq_global_enable();
    timer_start(CPU_HZ / 1000, 1);          /* 1 kHz */
    while (ticks < 10) ;
    printf("10 ms elapsed\n");
    return 0;
}
```

## 5.8 Rules and limits of this core

* No hardware exceptions: illegal instructions, `ecall`/`ebreak` and
  misaligned accesses are **not** trapped. The build uses `-mstrict-align`;
  do not use packed structs with misaligned fields.
* Integer only (no FPU); `float`/`double` would need soft-float libgcc
  routines and are not supported by the BSP `printf`.
* No `malloc` (use static buffers or the heap symbols yourself).
* Shared registers changed by an interrupt handler must be `volatile`.
* IMEM is readable/writable as data but slower (wait states); keep data in
  DMEM (the linker already does).
* The console is UART 8N1; in simulation it runs at `SIM_BAUD` and the
  testbench loops TXD back to RXD.

## 5.9 Existing programs

| Program | What it shows |
|---|---|
| `apps/hello` | console, arithmetic, GPIO |
| `apps/blinky` | timer interrupt + GPIO chaser |
| `apps/uart_echo` | interactive console (self-fed in simulation) |
| `apps/irq_demo` | four interrupt sources together |
| `tests/t_*` | self-checking tests for every block (see [06_verification.md](06_verification.md)) |

## 5.10 Running on a board

1. `make -C sw APP=myapp` (uses `UART_BAUD`, 115200 by default).
2. Program `sw/build/myapp/flash.bin` into the SPI NOR flash at offset 0
   (any SPI flash programmer; READ command 0x03, 24-bit addresses).
3. Connect a terminal to UART_TXD/UART_RXD at 115200 8N1, release reset.
4. If the image is bad the chip drives GPIO[7:0] = 0xE1..0xE4 (see §3.8).
