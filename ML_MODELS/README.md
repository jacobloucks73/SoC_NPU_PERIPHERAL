# ML_MODELS — Model Training & Exploration

This directory contains Python scripts and Jupyter notebooks for training the neural networks that run on the NPU.

## Models

| File | Dataset | Description |
|------|---------|-------------|
| `14x14_mnist_test.py` | MNIST (downscaled) | Digit classification on 14×14 images — smaller model for constrained FPGAs |
| `28x28_mnist_test.ipynb` | MNIST (full) | Digit classification on 28×28 images |
| `breast_cancer.ipynb` | Scikit-learn breast cancer | Binary classification on 30 tabular features |
| `rock_paper_scissor_manual_dataset_and_model.ipynb` | Custom RPS dataset | Grayscale image classification (rock/paper/scissors) |

## Prerequisites

```bash
pip install torch torchvision numpy matplotlib scikit-learn jupyter
```

<!-- TODO: Add a requirements.txt with pinned versions -->

## Workflow

1. **Train** a model by running the script or notebook.
2. **Export weights** to fixed-point using `HELPER_SCRIPTS/convert_weightsv4.py`.
3. **Embed** the exported weights as Ada constants in an `ADA_DEMO_FIRMWARE` project (see the existing demos for the pattern).
4. **Build and flash** the firmware onto the NEORV32.

## Adding a New Model

To create a new demo:

1. Train your model here. Keep the architecture simple — only use operations the NPU supports (dense/MAC, ReLU activation, pooling).
2. Save the trained weights.
3. Use `HELPER_SCRIPTS/convert_weightsv4.py` to convert weights to the NPU's fixed-point format.
4. Create a new Ada project under `SUPPORTED_FPGAS/.../ADA_DEMO_FIRMWARE/` using one of the existing demos as a template.
5. Paste the exported weight arrays into an `.ads` file in the new project's `src/` directory.

## Notes on Fixed-Point Conversion

The NPU operates on fixed-point integers, not floating-point. The conversion step (handled by `convert_weightsv4.py`) quantizes your trained weights. Some accuracy loss is expected — the notebooks are a good place to compare floating-point accuracy vs. quantized accuracy before deploying to hardware.
