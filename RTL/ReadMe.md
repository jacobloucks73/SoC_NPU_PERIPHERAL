# RTL — NPU Peripheral (VHDL)

This directory contains the **reusable core** of the project: a Wishbone B4 slave peripheral that performs neural network operations in hardware.

## Files

| File | Description |
|------|-------------|
| `wb_peripheral.vhd` | The NPU peripheral — supports dense (MAC), activation, and pooling operations |

## Wishbone Interface

The peripheral implements a standard Wishbone B4 slave interface:

| Signal | Direction | Description |
|--------|-----------|-------------|
| `wb_clk_i` | in | System clock |
| `wb_rst_i` | in | Synchronous reset |
| `wb_cyc_i` | in | Bus cycle active |
| `wb_stb_i` | in | Strobe — valid transfer |
| `wb_we_i` | in | Write enable |
| `wb_adr_i` | in | Register address |
| `wb_dat_i` | in | Write data |
| `wb_dat_o` | out | Read data |
| `wb_ack_o` | out | Transfer acknowledge |

<!-- TODO: Add a register map table here once the addresses are documented -->
<!-- Example:
| Address Offset | Register | R/W | Description |
|----------------|----------|-----|-------------|
| 0x00 | CONTROL | R/W | Operation select + start bit |
| 0x04 | STATUS | R | Busy / done flags |
| 0x08 | DATA_IN | W | Input operand |
| 0x0C | DATA_OUT | R | Result |
| 0x10 | WEIGHT | W | Weight value for MAC |
-->

## Using in Your Own SoC

This peripheral has **no dependencies** on the NEORV32 or any specific FPGA. It is pure behavioral VHDL.

1. Add `wb_peripheral.vhd` to your synthesis project.
2. Instantiate it and connect the Wishbone signals to your bus interconnect.
3. Assign it a base address that doesn't conflict with your existing peripherals.
4. From your CPU firmware, write operands and control bits, then read back results.

## Supported Operations

<!-- TODO: Fill in the actual operations and their control register encodings -->

| Operation | Description | Control Code |
|-----------|-------------|-------------|
| Dense / MAC | Multiply-accumulate for fully connected layers | TBD |
| Activation (ReLU) | Applies ReLU to input | TBD |
| Pooling | Max or average pooling | TBD |
