# Basys3 — Xilinx Artix-7 (Planned)

> **Status: Not yet implemented.** This is a placeholder for future Basys3 support.

The Basys3 board uses a Xilinx Artix-7 FPGA. To port the NEORV32 + NPU to this board, you would need:

1. A top-level VHDL wrapper adapting the NEORV32 + NPU for the Artix-7 (clock PLLs, pin mapping).
2. A Xilinx `.xdc` constraints file mapping signals to Basys3 pins.
3. Vivado project files or a TCL build script.

If you have a Basys3 and want to contribute this port, see the [porting guide in CONTRIBUTING.md](../../CONTRIBUTING.md).

## Known Considerations

- The Basys3 has a 100 MHz oscillator — adjust `CLOCK_FREQUENCY` accordingly.
- The Artix-7 on the Basys3 (XC7A35T) has ~33K LUTs and 90 block RAMs — check that the NEORV32 + NPU configuration fits.
- UART is available over USB. Pin mapping is documented in the [Basys3 reference manual](https://digilent.com/reference/programmable-logic/basys-3/reference-manual).
