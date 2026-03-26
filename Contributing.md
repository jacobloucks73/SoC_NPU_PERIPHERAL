# Contributing

Thanks for your interest in contributing! This project aims to make FPGA-based neural network inference accessible to anyone with a Wishbone-compatible SoC.

---

## Ways to Contribute

- **Port to a new FPGA board** — add a folder under `SUPPORTED_FPGAS/` with your top-level wrapper, constraints, and a README.
- **Add a new demo application** — train a model, export weights, write Ada firmware, and add it to `ADA_DEMO_FIRMWARE/`.
- **Improve the NPU peripheral** — add new operations, optimize timing, or reduce resource usage.
- **Add camera or sensor support** — follow the OV5640 pattern under `SUPPORTED_CAMERAS/`.
- **Write documentation** — architecture diagrams, register maps, tutorials.
- **Report bugs** — open an issue with your board, toolchain version, and steps to reproduce.

---

## Code Style

- **VHDL**: Use VHDL-2008. Format with the [VHDL Formatter](https://g2384.github.io/VHDLFormatter/). Use `_i` / `_o` suffixes for port signals.
- **Ada**: Follow default GNAT style. Use descriptive names.
- **Python**: Follow PEP 8. Include docstrings for public functions.
- **Naming**: No spaces in file or folder names. Use UPPER_CASE for top-level directories (to match existing convention) and lowercase for files.

---

## Pull Request Process

1. Fork the repo and create a feature branch.
2. Make your changes. Update or add READMEs if you change the directory structure.
3. Make sure build artifacts are not committed (check `.gitignore`).
4. Test your changes — simulation at minimum; hardware test if you have the board.
5. Open a PR with a clear description of what you changed and why.

---

## Porting to a New FPGA Board

### If you just want the NPU peripheral

1. Copy `RTL/wb_peripheral.vhd` into your project.
2. Connect its Wishbone slave port to your bus.
3. Assign a base address. Done.

### If you want the full NEORV32 + NPU reference design on a new board

1. Create `SUPPORTED_FPGAS/YOUR_BOARD/NEORV32/`.
2. Add a `NEORV32_SPECIFIC/` folder with your top-level VHDL wrapper, pin constraints, and build script. Use the ECP5 version as a template.
3. Adapt clock frequency, memory sizes, and UART pin mapping for your board.
4. Add a README documenting the board, toolchain, and any quirks.
5. Open a PR.

### Things to watch out for

- **Clock frequency**: The NEORV32 needs to know the system clock for baud rate calculation. Set the `CLOCK_FREQUENCY` generic.
- **Memory sizes**: IMEM and DMEM sizes are set via generics. Larger models need more IMEM.
- **Reset polarity**: Some boards use active-low, others active-high. Invert in your top-level if needed.

---

## Questions?

Open an issue. There are no dumb questions.
