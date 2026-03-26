# Ada Firmware for NEORV32

This directory contains all Ada software that runs **on** the NEORV32 RISC-V processor.

## Structure

```
ADA/
├── ADA_LIBS/                    # Reusable libraries
│   ├── ADA_FUNCTION_LIB/        #   NPU driver + ML operations (ada_ml package)
│   └── INPUT_OUTPUT_LIB/        #   UART I/O helpers, debug printing, timing
│
└── ADA_DEMO_FIRMWARE/           # Demo applications
    ├── BREAST_CANCER_TEST/      #   Breast cancer binary classification
    ├── INTEGRATION_TEST/        #   Multi-model integration test
    └── MNIST_28x28_TEST/        #   MNIST digit classification
```

## Libraries (`ADA_LIBS/`)

### ADA_FUNCTION_LIB (the `ada_ml` package)

The core NPU driver library. It wraps the NPU's memory-mapped registers into clean Ada procedure calls. Key child packages:

| Package | Purpose |
|---------|---------|
| `Ada_ML.Dense` | Dense (fully connected) layer operations via the NPU |
| `Ada_ML.Activation` | Activation functions (ReLU, etc.) |
| `Ada_ML.Pooling` | Pooling operations |
| `Ada_ML.Processing` | Higher-level inference pipeline helpers |
| `Ada_ML.Utils` | Fixed-point conversion, data formatting |
| `Ada_ML.Debug` | Debug output over UART |

If you're porting to a different soft-core or language, this library shows exactly which registers to hit and in what order.

### INPUT_OUTPUT_LIB (the `Input_Output_Helper` package)

Utility library for UART communication, formatted debug output, and cycle-accurate timing measurements. Child packages:

| Package | Purpose |
|---------|---------|
| `Input_Output_Helper.Debug` | Pretty-print arrays, matrices, and results |
| `Input_Output_Helper.Utils` | String and number formatting |
| `Input_Output_Helper.Time_Measurements` | Cycle counting for benchmarks |

## Demo Firmware (`ADA_DEMO_FIRMWARE/`)

Each demo is a standalone Alire project that you can build and flash independently. See [`ADA_DEMO_FIRMWARE/README.md`](ADA_DEMO_FIRMWARE/README.md) for details on each demo and build instructions.

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Alire](https://alire.ada.dev/) | Ada package manager — downloads GNAT automatically |
| `riscv64-elf-objcopy` | Part of the RISC-V GCC toolchain |
| `image_gen` | NEORV32 executable image generator |

## Build & Flash (Quick Reference)

```bash
cd ADA_DEMO_FIRMWARE/MNIST_28x28_TEST    # or any demo

alr build
riscv64-elf-objcopy -O binary bin/test_cases_neorv32 bin/test_cases_neorv32.bin
image_gen -app_bin bin/test_cases_neorv32.bin bin/test_cases_neorv32.exe
```

Then upload `test_cases_neorv32.exe` via the NEORV32 UART bootloader (19200 baud, 8N1).
