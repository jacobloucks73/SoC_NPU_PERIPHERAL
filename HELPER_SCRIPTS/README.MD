# HELPER_SCRIPTS — Weight Conversion & Data Utilities

Utility scripts that bridge the gap between Python model training and FPGA deployment.

## Scripts

| Script | Purpose |
|--------|---------|
| `convert_weightsv4.py` | Converts trained model weights (floating-point) to fixed-point arrays formatted as Ada constants. This is the key step between `ML_MODELS/` and `ADA_DEMO_FIRMWARE/`. |
| `convert_data_to_img.py` | Converts raw inference data (e.g., MNIST pixel arrays) into viewable images for debugging and visualization. |

## Usage

### Converting Weights

```bash
python convert_weightsv4.py
```

<!-- TODO: Document the command-line arguments, input format, and output format -->
<!-- Example:
python convert_weightsv4.py --model ../ML_MODELS/weights.pt --format ada --q-format Q8.8 --output weights.ads
-->

The output is an Ada `.ads` file containing constant arrays that you copy into your firmware project's `src/` directory.

### Visualizing Data

```bash
python convert_data_to_img.py
```

<!-- TODO: Document arguments and expected input format -->

This is useful for verifying that the data being sent to the NPU matches what you expect (e.g., confirming a digit image looks correct before running inference).
