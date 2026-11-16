# t1c_riscv_soc — documentation

RV32IM bare-metal microcontroller SoC for SCL180, 100 MHz.
Read in order; chapter 1 gets your own C program running in minutes.

| # | Document | Contents |
|---|---|---|
| 1 | [Quick start](01_quick_start.md) | environment, run the example, write and run your own C program |
| 2 | [Folder structure](02_folder_structure.md) | where everything lives |
| 3 | [Architecture](03_architecture.md) | block diagram, memory map, CPU, memories, buses, interrupts, boot flow |
| 4 | [RTL module reference](04_rtl_modules.md) | every RTL module and every peripheral register |
| 5 | [Software guide](05_software_guide.md) | toolchain, build flow, linker layout, BSP API, examples, limits, board use |
| 6 | [Verification](06_verification.md) | all test levels, C tests, bugs found |
| 7 | [Signoff status](07_signoff_status.md) | RTL signoff checklist at 100 MHz, synthesis, LEC, GLS, lint, coverage, limitations |
| 8 | [Pinout and die](08_pinout_and_die.md) | pin count with/without I/O ring, pad cells, pinout, die size, package |
| 9 | [Physical design hand-off](09_physical_design.md) | chip_top synthesis, constraints, Innovus floorplan/power plan, next steps |

Related: `signoff/docs/BOOT_FLOW.md` (boot ROM protocol),
`signoff/STATUS.md` (live checklist), `gate_level_netlist/README.md`.
