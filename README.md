# I2C Master-Slave Protocol Implementation

This repository contains a complete, synthesizable I2C master and slave implementation written in Verilog, along with a top-level wrapper and a comprehensive self-checking testbench.

## Features
- **Parameterized Clocks:** Configurable system clock and I2C bus frequencies via module parameters.
- **Addressing Modes:** Fully supports both standard 7-bit and extended 10-bit addressing.
- **Advanced Protocol Handling:** Natively implements intentional clock stretching and repeated-START conditions for seamless multi-message transfers.
- **Burst Operations:** Supports multi-byte burst reads and writes (e.g., configuring multiple consecutive registers).
- **Self-Checking Verification:** Includes a testbench that validates protocol edge cases, including NACK recovery and clock stretch handshakes, outputting a clear pass/fail summary.

## File Structure
- `i2c_system_top.v`: The top-level wrapper that instantiates both the master and slave modules. It also implements internal pull-up logic for the SDA and SCL lines.
- `i2c_master.v`: The I2C master controller state machine handling transmission, reception, and bus clock generation.
- `i2c_slave.v`: The I2C slave device containing a 16-byte internal register memory to respond to master read/write requests.
- `tb_i2c_protocol.v`: The self-checking simulation testbench.

## Hardware & Toolchain
- **Language:** Verilog HDL
- **Simulation & Synthesis:** Xilinx Vivado
- **Target Hardware:** Designed for compatibility with FPGAs such as the Nexys 4 DDR (Artix-7), but easily portable to other architectures. 

## Usage in Xilinx Vivado

### 1. Project Setup
1. Open Xilinx Vivado and create a new **RTL Project**.
2. When prompted for parts/boards, select your target FPGA (e.g., Nexys 4 DDR).
3. In the **Add Sources** menu, click **Add Files** and import:
   - `i2c_system_top.v`
   - `i2c_master.v`
   - `i2c_slave.v`
4. Vivado will automatically set `i2c_system_top.v` as the top module.

### 2. Simulation
1. In the **Sources** pane, add `tb_i2c_protocol.v` under **Simulation Sources**.
2. Click **Run Simulation** -> **Run Behavioral Simulation** in the Flow Navigator.
3. Check the **Tcl Console** for the automated testbench output (Pass/Fail counts). You can also view the I2C transactions directly in the waveform viewer.

### 3. Synthesis & Implementation
1. Click **Run Synthesis** to compile the RTL into hardware primitives.
2. To run this on physical hardware, you will need to create and add an **XDC Constraints File** mapping the `clk`, `sda`, and `scl` ports to your specific FPGA pins.
