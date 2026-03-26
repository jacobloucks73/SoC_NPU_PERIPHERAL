# PREBUILT_DEMOS — Ready-to-Flash Binaries & Bitstreams

This directory contains prebuilt artifacts so you can try the demos **without installing any build tools**. Just flash and go.

## Available Demos

| Demo | Folder | Description |
|------|--------|-------------|
| MNIST 28×28 | `MNIST_28x28_TEST/` | Handwritten digit classification (full resolution) |
| MNIST 14×14 | `MNIST_14x14_TEST/` | Digit classification (downscaled, smaller model) |
| Breast Cancer | `BREAST_CANCER_TEST/` | Binary classification on tabular medical data |
| Rock-Paper-Scissors | `RPS_TEST/` | Grayscale image classification |
| Integration Test | `INTEGRATION_TEST/` | Runs multiple models to verify all NPU operations |

## Each demo folder contains

```
DEMO_NAME/
├── BITSTREAM/
│   └── README.MD    ← (will contain the .bit file for the ECP5)
└── BINARY/
    └── README.MD    ← (will contain the .exe file for the NEORV32 bootloader)
```

<!-- TODO: Replace the README placeholders with actual .bit and .exe files once tested -->

## How to Use

### 1. Flash the bitstream

Program `BITSTREAM/*.bit` to your ECP5 FPGA using Lattice Diamond Programmer or `openFPGALoader`:

```bash
openFPGALoader --board YOUR_BOARD BITSTREAM/demo_name.bit
```

### 2. Upload the firmware binary

1. Connect a serial terminal to the board's USB-serial at **19200 baud, 8N1**.
2. Press reset. You should see the NEORV32 bootloader prompt.
3. Press `u` to enter upload mode.
4. Send `BINARY/test_cases_neorv32.exe` as a raw binary transfer.
5. Press `e` to execute.

### 3. Watch the output

Inference results will print to the serial console. For MNIST demos, you'll see the predicted digit and confidence scores for each test sample.

## Building from Source

If you want to modify a demo or build it yourself, see:
- Firmware source: [`../FIRMWARE/ADA/ADA_DEMO_FIRMWARE/`](../FIRMWARE/ADA/ADA_DEMO_FIRMWARE/)
- Bitstream source: [`../NEORV32_SPECIFIC/`](../NEORV32_SPECIFIC/)
- Model training: [`../../../../ML_MODELS/`](../../../../ML_MODELS/)
