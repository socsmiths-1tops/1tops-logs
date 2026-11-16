# Boot Flow — t1c_riscv_soc

## Overview
```
reset ──► Boot ROM @0x0000_0000 (1 KB, bootloader, mask ROM)
            │  reads header + image over dedicated boot SPI (boot_flash_ctrl @0x4000_5000)
            ▼
          SPI-NOR flash (external, READ 0x03, mode 0)
            │  payload streamed word-by-word, CRC-32 computed on the fly
            ▼
          SRAM @0x1000_0000 ──► jump to header.entry (application)
```
Interrupts stay disabled (mstatus.MIE=0 from reset) for the whole boot.

## Flash image format (`sw/tools/mkimage.py`)
| Offset | Field | Value |
|---|---|---|
| 0x00 | magic  | `0x504F5431` ("1TOP", little-endian bytes `31 54 4F 50`) |
| 0x04 | length | payload bytes, multiple of 4, 4 … 0x10000 (whole 64 KB IMEM; stack is in DMEM) |
| 0x08 | crc32  | IEEE/zlib CRC-32 of the payload |
| 0x0C | entry  | absolute entry address, `0x1000_0000 ≤ entry < 0x1000_0000+length`, word aligned |
| 0x10 | payload | application binary linked at 0x1000_0000 (`scripts/link_app.ld`) |

Build: `python3 sw/tools/mkimage.py app.bin flash.hex [--entry 0x10000000]`
(one hex byte per line; program the same bytes into the real flash at offset 0).

## Error reporting
On failure the loader drives GPIO[7:0] as outputs with a code and halts:
| Code | Meaning |
|---|---|
| 0xE1 | bad magic (blank/erased flash reads 0xFFFFFFFF → E1) |
| 0xE2 | bad length |
| 0xE3 | CRC mismatch |
| 0xE4 | bad entry address |

## boot_flash_ctrl registers (base 0x4000_5000)
| Off | Name | Access | Description |
|---|---|---|---|
| 0x00 | CMD | W | 0x03 start READ at ADDR for NBYTES; 0x00 abort |
| 0x04 | ADDR | RW | 24-bit flash address (idle only) |
| 0x08 | NBYTES | RW | 24-bit byte count (idle only) |
| 0x0C | STATUS | R | [0] busy, [1] rx_valid, [15:8] last byte |
| 0x10 | DATA | R | received word (LE); read pops, SCLK resumes |
| 0x14 | CLKDIV | RW | SCLK half period in clk cycles (reset 4 → 6.25 MHz @50 MHz, 12.5 MHz @100 MHz) |

SCLK pauses (CS held low) whenever a word is waiting to be read, so there is no overrun.

## Performance
Per word: 32 SCLK periods (256 clk at CLKDIV=4) overlapped with the CRC loop.
Measured: 220 B image boots in ≈18 k cycles; ≈ 70 cycles/byte → 16 KB ≈ 1.1 M cycles (11 ms @100 MHz).

## Rebuilding the ROM
`sw/boot/build_bootrom.sh` assembles `sw/boot/boot_loader.S` and regenerates
`rtl/soc/boot_rom_image.vh` (currently 66/256 words). The regression rebuilds it and
warns if the committed file is stale. Any change to the bootloader = ROM change → re-run
full regression, synthesis and LEC.

## Verification
`signoff/scripts/run_bm_regression.sh` boots every bare-metal test through this flow and runs
negative tests `bootneg_{magic,len,crc,entry}` expecting codes E1–E4.

## Known limitations
- Integrity only (CRC-32), no authentication. ASCON on-chip could provide MAC-verified boot later.
- Single fixed image at flash offset 0; no fallback image, no UART recovery boot.
