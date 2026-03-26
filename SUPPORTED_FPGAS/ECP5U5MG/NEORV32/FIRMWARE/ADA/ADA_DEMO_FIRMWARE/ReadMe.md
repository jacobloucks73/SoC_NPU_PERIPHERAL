# Ada Demo Firmware

Each subdirectory is a standalone [Alire](https://alire.ada.dev/) project that demonstrates end-to-end neural network inference on the NEORV32 + NPU.

## Available Demos

| Demo | Model Architecture | What It Does |
|------|-------------------|--------------|
| `MNIST_28x28_TEST` | 784 inputs → dense layers → 10 outputs | Classifies handwritten digits (0–9) from the MNIST dataset at full 28×28 resolution |
| `BREAST_CANCER_TEST` | 30 inputs → dense layers → 2 outputs | Binary classification (benign/malignant) on the scikit-learn breast cancer dataset |
| `INTEGRATION_TEST` | Multiple models | Runs several different models in sequence to verify all NPU operations work correctly. Includes MNIST 14×14 and rock-paper-scissors models. |

## Project Structure (each demo follows the same pattern)

```
DEMO_NAME/
├── alire.toml           # Alire project manifest (dependencies, target config)
├── demo_name.gpr        # GNAT project file
├── src/
│   ├── demo_name.adb    # Main program — loads weights, runs inference, prints results
│   ├── *_weights.ads    # Pre-exported fixed-point weight constants
│   ├── *_samples.ads    # Test input data (e.g., pixel arrays for specific digits)
│   └── runtime_support.* # Low-level runtime support for bare-metal NEORV32
└── config/              # Alire-generated config files
```

## Building a Demo

Prerequisites: [Alire](https://alire.ada.dev/), `riscv64-elf-objcopy`, and `image_gen` (see [parent README](../README.md)).

```bash
cd MNIST_28x28_TEST      # or BREAST_CANCER_TEST, INTEGRATION_TEST

# 1. Build
alr build

# 2. Convert ELF → raw binary
riscv64-elf-objcopy -O binary bin/test_cases_neorv32 bin/test_cases_neorv32.bin

# 3. Generate NEORV32 executable
image_gen -app_bin bin/test_cases_neorv32.bin bin/test_cases_neorv32.exe
```

## Uploading to the NEORV32

1. Connect a serial terminal to the board's USB-serial port at **19200 baud, 8N1**.
2. Press the reset button. You should see the NEORV32 bootloader prompt.
3. Press `u` to enter upload mode.
4. Send `test_cases_neorv32.exe` as a raw binary transfer.
5. Press `e` to execute.

Inference results will print to the serial console.

## Creating a New Demo

1. Copy one of the existing demo folders as a template.
2. Train your model in `ML_MODELS/`.
3. Export weights with `HELPER_SCRIPTS/convert_weightsv4.py`.
4. Replace the `*_weights.ads` and `*_samples.ads` files with your exported data.
5. Update the main `.adb` to call the right sequence of NPU operations for your model.
6. Update `alire.toml` and the `.gpr` file with the new project name.

## Troubleshooting

- **`alr build` fails**: Make sure the RISC-V cross-compilation toolchain is configured in Alire. Check that `alire.toml` references the correct target.
- **`image_gen` not found**: Build it from `neorv32/sw/image_gen/` and add it to your PATH.
- **Serial output is garbage**: Verify baud rate is 19200. Check UART TX/RX pin connections.
- **"Awaiting neorv32_exe.bin..." but upload hangs**: Make sure you're sending the `.exe` file (not `.bin` or `.elf`) and using raw binary transfer mode in your terminal.
