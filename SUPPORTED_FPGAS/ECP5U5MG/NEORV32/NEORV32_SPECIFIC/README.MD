# NEORV32_SPECIFIC — ECP5 Board Setup Files

This directory contains everything needed to synthesize the NEORV32 + NPU system on the **Lattice ECP5 Evaluation Board** (ECP5U5MG).

## Files

| File | Purpose |
|------|---------|
| `neorv32_ProcessorTop_MinimalBoot.vhd` | Top-level VHDL wrapper — instantiates the NEORV32 processor, Wishbone bus, and NPU peripheral, then maps I/O to ECP5 pins |
| `ECP5EVN_NEORV32_MinimalBoot.lpf` | Lattice constraints file — maps logical signals to physical FPGA pins |
| `create_neorv32_diamond.tcl` | TCL script that creates and configures a complete Lattice Diamond project |

## Prerequisites

- [Lattice Diamond](https://www.latticesemi.com/latticediamond) (free license available)
- The NEORV32 VHDL source files (clone the [NEORV32 repo](https://github.com/stnolting/neorv32) and add all files from `rtl/core/` to your project)
- The NPU peripheral from `RTL/wb_peripheral.vhd`

## Building the Bitstream

### Using the TCL script (recommended)

```bash
cd NEORV32_SPECIFIC
pnmainc create_neorv32_diamond.tcl
```

This creates a Diamond project, adds all source files, runs synthesis, place-and-route, and generates a bitstream.

### Manually in Diamond GUI

1. Create a new project targeting your ECP5 device.
2. Add all NEORV32 `rtl/core/*.vhd` files to a library called `neorv32`.
3. Add `neorv32_ProcessorTop_MinimalBoot.vhd` as the top entity.
4. Add `../../RTL/wb_peripheral.vhd` (the NPU).
5. Import `ECP5EVN_NEORV32_MinimalBoot.lpf` as the constraints file.
6. Run the full flow: Synthesis → Map → Place & Route → Bitstream.

## Programming the FPGA

Use the Diamond Programmer (or `openFPGALoader`) to load the generated `.bit` file via JTAG.

After programming, connect a serial terminal at **19200 baud, 8N1** to the board's UART. Press reset — you should see the NEORV32 bootloader prompt.

## Pin Mapping

Key signal assignments from the `.lpf` file:

<!-- TODO: Fill in actual pin numbers from ECP5EVN_NEORV32_MinimalBoot.lpf -->

| Signal | FPGA Pin | Board Connection |
|--------|----------|-----------------|
| `clk_i` | — | On-board oscillator |
| `rstn_i` | — | Reset button (active low) |
| `uart0_txd_o` | — | UART TX → USB-serial |
| `uart0_rxd_i` | — | UART RX ← USB-serial |
| `gpio_o[7:0]` | — | LEDs |

## Porting to Another ECP5 Board

If you have a different ECP5 board (e.g., ULX3S, OrangeCrab, custom PCB):

1. Copy this directory as a starting point.
2. Update the `.lpf` file with your board's pin assignments.
3. Adjust the `CLOCK_FREQUENCY` generic in the top-level VHDL to match your oscillator.
4. Adjust IMEM/DMEM size generics if your FPGA has different block RAM capacity.
5. Rebuild.
