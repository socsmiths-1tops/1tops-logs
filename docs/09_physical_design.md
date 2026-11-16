# 9. Physical-design hand-off (SCL180, Innovus)

## 9.1 Inputs prepared

| Item | File |
|---|---|
| Chip RTL with pad ring | `rtl/chip/chip_top.v` |
| Chip synthesis script | `gate_level_netlist/chip/scripts/genus_chip.tcl` |
| Chip constraints (100 MHz, pad I/O budget) | `gate_level_netlist/chip/constraints/chip_top.sdc` |
| Netlist / SDC / SDF | `gate_level_netlist/chip/chip_top_netlist.v`, `chip_top.sdc`, `chip_top.sdf` |
| Genus → Innovus database | `gate_level_netlist/chip/innovus/` |
| RTL ↔ netlist LEC | `gate_level_netlist/chip/lec/rtl2gate.do` |
| I/O ring order | `pd/chip_top.io` |
| Timing views (MMMC) | `pd/scripts/mmmc.tcl` — setup SS 1.62 V 125 °C, hold FF 1.98 V −40 °C, SCL QRC tech file (4M) |
| Import | `pd/scripts/01_init.tcl` — LEFs: tech, std cells, `rd3_4096x32`, `tsl18cio250_4lm` |
| Floorplan | `pd/scripts/02_floorplan.tcl` |
| Power plan | `pd/scripts/03_powerplan.tcl` |
| Driver | `pd/scripts/run_fp.tcl` |

## 9.2 Libraries (all SCL180, 4-metal)

| Kind | Path under `/home/install/scl180` |
|---|---|
| Std cells | `stdcell/fs120/4M1IL/` — `lef/scl18fs120_tech.lef`, `lef/scl18fs120_std.lef`, `liberty/lib_flow_{ss,ff}/` |
| SRAM | `memory/dpram/4M1L/DP_SRAM_rd3_4096x32/` — `.lef`, `.lib` (ss/tt/ff), `.v`, `.cdl`, `.gds` |
| I/O pads | `iopad/cio250/4M1L/` — `lef/tsl18cio250_4lm.lef`, `liberty/tsl18cio250_{max,min}.lib`, `gds/` |
| Extraction | `qrc_tech_file/qrcTechFile_4M`, `CAPTABLE/generated_captable_4M.cap` |
| Seal ring | `ext_str/SEALRING_PAD_PDK2020.gds` |

Routing layers: M1 (H), M2 (V), M3 (H), TOP_M (V); site `CoreSite`
0.56 × 5.6 µm.

## 9.3 Floorplan

* Die 5200 × 5200 µm, core box 400 µm from the die edge (4400 × 4400 µm).
  (Innovus measures core margins from the inner pad edge: 150 µm + 250 µm pads.)
* Pad ring: 40 pads (`pd/chip_top.io`), `pfrelr` corners, `pfeed*` fillers.
* SRAM: 8 macros in 2 columns × 4 rows at the upper-left of the core,
  IMEM column left, DMEM column right, 20 µm halos, hard placement blockage
  over the macro block; standard cells in the remaining L-shaped area.
* Power: VDD/VSS core ring (M3/TOP_M, 20 µm), block rings around each
  macro, TOP_M vertical stripes every 150 µm (6 µm), M3 horizontal stripes
  every 450 µm (4 µm, sparse because M3 is one of only two horizontal
  routing layers), special routes to pad, macro and follow-pin rails. I/O supplies VDDO/VSSO are
  carried by the pad ring abutment.

## 9.4 Running it

```bash
source signoff/env.sh
cd gate_level_netlist/chip && genus -no_gui -files scripts/genus_chip.tcl -log logs/genus
cd ../../pd && innovus -stylus -batch -no_gui -files scripts/run_fp.tcl -log logs/innovus
innovus -stylus          # GUI; then: read_db db/chip_top_place
# optional pre-CTS optimisation in the same run:
innovus -stylus -batch -no_gui -execute "set ::RUN_OPT 1" -files scripts/run_fp.tcl
```

## 9.5 Results of the prepared floorplan (Innovus 21.15)

| Check | Result |
|---|---|
| Import (LEF/lib/netlist/MMMC) | clean, all 8 SRAM macros and 40 pads bound |
| Pad ring | 40 pads + 4 corners placed per `chip_top.io`, fillers inserted; `reports/pad_locations.csv` |
| Power plan DRC (`check_drc`) | **0 violations** |
| Placement (`place_design`) | all 79 507 cells legal (8 fixed macros); density **45.2 %** |
| Early global route | overflow **2.5 %** (M2 1.8 %, M3 4.7 %, TOP_M 0.9 %) — routable |
| Congestion hotspots | max 44.8, total 99.8 (normalised) |
| Databases | `db/chip_top_fp` (floorplan + power), `db/chip_top_place` (placed) |

Iteration log: a 5.0 mm die was tried first (`reports_5000/`): 64 %
density, 8.6 % overflow, M3 18.5 % — rejected. A full `place_opt_design`
on one CPU did not finish in 90 min; the scripts now use 8 threads and keep
pre-CTS optimisation optional (`RUN_OPT`). The pad-to-package nets drive the
10 pF board load through fixed pad cells; mark them `dont_touch` (done in
`run_fp.tcl`) so DRV fixing does not spin on them.

## 9.6 Remaining physical-design steps

1. CTS (`ccopt_design`), post-CTS optimisation, set propagated clocks.
2. Routing (`route_design`), post-route optimisation, SI.
3. Signoff extraction (Quantus) + STA (Tempus) at SS/TT/FF.
4. DRC/LVS (PVS/Assura) with the SCL rule decks, antenna, density fill.
5. Post-route GLS with the routed SDF (`make -C sw APP=... chipgls`
   after exporting the netlist/SDF).
6. GDS merge (std cells, SRAM, pads, seal ring) and tape-out checks.
