# 1. Quick start — run your own C program on the SoC

## 1.1 Prerequisites (already installed on the lab server)

| Tool | Version | Used for |
|---|---|---|
| RISC-V GCC `riscv32-unknown-elf-` | 16.1, rv32im | compiling software |
| Python 3 | ≥ 3.6 | flash image tool |
| Cadence Xcelium | 22.09 | RTL / gate-level simulation |
| Cadence Genus | 21.1 | synthesis |
| Cadence Conformal | 21.1 | equivalence check |
| Cadence Innovus | 21.1 | physical design |
| SCL180 PDK | `/home/install/scl180` | std cells, SRAM macros, I/O pads |

## 1.2 One-time setup (every new shell)

```bash
cd /home/onetops/1tops/rv32im
source signoff/env.sh          # Cadence tools + RISC-V GCC on PATH, licences
```

Check: `riscv32-unknown-elf-gcc --version` and `which xrun`.

## 1.3 Run the example

```bash
make -C sw APP=hello sim
```

What happens: `hello/main.c` is compiled with the BSP, linked for IMEM/DMEM,
packed into a flash image (`sw/build/hello/flash.hex`), the SoC is
simulated at 100 MHz, the Boot ROM loads the program from the simulated
SPI flash, and the UART console is printed:

```
[uart] Hello from t1c_riscv_soc (RV32IM @ 100 MHz)
[uart] fib(11) = 89, 1234567 / 89 = 13871 rem 48
[uart] GPIO out = 0xa5
TB: program exit after 302089 cycles
EXIT code=0
SIM RESULT: PASS
```

(First run also elaborates the design, ~10 s; later runs reuse it.)

## 1.4 Your own program

```bash
mkdir -p sw/apps/myapp
$EDITOR sw/apps/myapp/main.c        # see template below
make -C sw APP=myapp sim
```

Template:

```c
#include "bsp.h"

int main(void)
{
    uart_init(UART_BAUD);                 /* console */
    printf("my program\n");

    /* ... your code: drivers in bsp.h, registers in soc.h ... */

    return 0;                             /* 0 = PASS, non-zero = FAIL in sim */
}
```

* Several `.c` / `.S` files and headers in the directory are built together.
* An application anywhere on disk: `make -C sw APP=/abs/path/to/dir sim`.
* Build only (for a board): `make -C sw APP=myapp` → program
  `sw/build/myapp/flash.bin` into the SPI NOR flash at offset 0.
* Gate-level (synthesized netlist, SS delays): `make -C sw APP=myapp gls`
  (much slower; keep programs short).
* Everything the BSP offers: [05_software_guide.md](05_software_guide.md).

## 1.5 Where the results are

```
sw/build/myapp/
  myapp.elf / .dis / .map / .size     program, disassembly, memory map, sizes
  myapp.bin                           raw image (code + initial data)
  flash.bin                           image for the real SPI flash
  flash.hex                           image for simulation
  sim_rtl.log                         full simulation log
  uart_rtl.txt                        console output only
```

## 1.6 If something goes wrong

| Symptom | Cause / fix |
|---|---|
| `riscv32-unknown-elf-gcc: command not found` | `source signoff/env.sh` |
| `error: app 'x' not found` | directory must be `sw/apps/x`, `sw/tests/x` or a path |
| link error "does not fit in 64 KB IMEM" | program too large: `-Os` (`make OPT=-Os`), remove code |
| `TB: Boot ROM error 0xE3` | image corrupted (CRC); rebuild |
| `TIMEOUT` | program never returned: add `return`/`exit()`, or raise `+TIMEOUT_CYC=` (see `sim/run_app.sh`) |
| no console output | `uart_init()` not called |
| `elaboration failed` | read `sim/build/rtl/elab.log` |

## 1.7 Full verification and signoff runs

```bash
make -C sw tests                     # all C tests (RTL)       -> sim/reports/
sim/run_sw_tests.sh gls              # selected C tests on the netlist
signoff/scripts/run_all.sh           # complete RTL regression -> signoff/reports/
```

See [06_verification.md](06_verification.md) and
[07_signoff_status.md](07_signoff_status.md).
