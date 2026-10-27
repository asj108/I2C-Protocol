# I2C Master-Slave Protocol Implementation

This repository contains a complete, synthesizable I2C master and slave implementation written in Verilog, along with a top-level wrapper and a self-checking testbench. 

## Features
* **Parameterized Clocks:** Configurable system clock and I2C bus frequencies.
* **Addressing Modes:** Supports both standard 7-bit and extended 10-bit addressing.
* **Advanced I2C Features:** Implements clock stretching and repeated-START conditions.
* **Burst Operations:** Supports multi-byte burst reads and writes.
* **Verification:** Includes a comprehensive, self-checking testbench validating protocol edge cases (NACK recovery, clock stretch handshaking, etc.).

## File Structure
* `i2c_system_top.v`: Top-level wrapper instantiating both the master and slave modules with internal pull-ups for SDA and SCL.
* `i2c_master.v`: The I2C master controller state machine.
* `i2c_slave.v`: The I2C slave device containing a 16-byte internal register memory.
* `tb_i2c_protocol.v`: A self-checking testbench that simulates various I2C transactions and generates a `.vcd` waveform file.

## Simulation
To simulate this project using Icarus Verilog, run the following commands:
```bash
iverilog -o i2c_sim tb_i2c_protocol.v i2c_system_top.v i2c_master.v i2c_slave.v
vvp i2c_sim
```
This will output the test results to the console and generate an `i2c_protocol_sim.vcd` file that can be viewed in GTKWave.
