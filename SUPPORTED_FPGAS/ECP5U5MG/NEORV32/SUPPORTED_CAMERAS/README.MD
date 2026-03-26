# OV5640 Camera Peripheral

A Wishbone-compatible camera interface for the OV5640 image sensor, designed to capture images and feed them directly into the NPU for real-time inference.

## Structure

```
OV5640/
├── OV5640_RTL/                     # VHDL hardware
│   ├── wb_0v5640.vhd              #   Wishbone slave — top-level camera controller
│   ├── ov5640_image_buffer.vhd    #   Frame buffer for captured image data
│   ├── i2c_controller.vhd        #   Generic I2C master controller
│   └── sccb_i2c_wrapper.vhd      #   SCCB protocol wrapper (OV5640 uses SCCB, which is I2C-like)
│
└── OV5640_LIBS/ADA/               # Ada driver library
    └── src/
        ├── wb_ov5640_helper.ads   #   Package spec — camera init, capture, config procedures
        ├── wb_ov5640_helper.adb   #   Package body
        ├── wb_ov5640_helper-debug.ads  # Debug output helpers
        └── wb_ov5640_helper-debug.adb
```

## How It Works

1. The SCCB/I2C interface configures the OV5640 sensor (resolution, format, exposure, etc.).
2. The image buffer captures pixel data from the sensor's parallel data interface.
3. The Wishbone slave exposes the buffer to the CPU, which can read pixel data and pass it to the NPU for inference.

## Hardware Connections

<!-- TODO: Fill in the actual pin connections for your board -->

| Signal | Direction | Description |
|--------|-----------|-------------|
| `cam_sda` | bidirectional | SCCB/I2C data line |
| `cam_scl` | out | SCCB/I2C clock line |
| `cam_pclk` | in | Pixel clock from sensor |
| `cam_vsync` | in | Vertical sync |
| `cam_href` | in | Horizontal reference |
| `cam_data[7:0]` | in | Parallel pixel data |
| `cam_xclk` | out | Master clock to sensor |
| `cam_pwdn` | out | Power down control |
| `cam_reset` | out | Sensor reset |

## Ada Driver

The `wb_ov5640_helper` Ada package provides procedures for:

- Initializing the OV5640 with a register configuration sequence over SCCB
- Capturing a frame into the image buffer
- Reading pixel data from the buffer via Wishbone
- Debug output of captured images over UART

## Adding a New Camera

To support a different camera sensor, follow this pattern:

1. Create a new folder under `SUPPORTED_CAMERAS/` (e.g., `OV7670/`).
2. Implement the I2C/SCCB configuration for the new sensor.
3. Adapt or reuse the image buffer and Wishbone interface.
4. Write an Ada driver library following the `wb_ov5640_helper` pattern.
5. Add a README documenting the sensor and pin connections.
