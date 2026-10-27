`timescale 1ns / 1ps

module i2c_system_top #(
    parameter integer SYS_CLK_FREQ     = 100_000_000,
    parameter integer I2C_CLK_FREQ     = 100_000,
    parameter integer CLK_DIV          = SYS_CLK_FREQ / (4 * I2C_CLK_FREQ),
    parameter [6:0]   SLAVE_ADDR_7BIT  = 7'h55,
    parameter [9:0]   SLAVE_ADDR_10BIT = 10'h2A5,
    parameter integer STRETCH_CYCLES   = 48
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start_cmd,
    input  wire        rw_cmd,
    input  wire        mode_10bit,
    input  wire        use_reg_addr,
    input  wire [9:0]  slave_addr,
    input  wire [7:0]  reg_addr,
    input  wire [2:0]  byte_len,
    input  wire [31:0] wr_data_burst,
    input  wire        stretch_en,

    output wire [31:0] rd_data_burst,
    output wire [7:0]  rd_last_byte,
    output wire        rd_byte_valid,
    output wire        busy,
    output wire        done,
    output wire        ack_error,
    output wire        stretch_detected,
    output wire [3:0]  slave_last_wr_addr,
    output wire [7:0]  slave_last_wr_data,
    output wire        slave_wr_valid,
    output wire        slave_busy,
    output wire [7:0]  slave_reg_00,
    output wire [7:0]  slave_reg_04,

    inout  wire        sda,
    inout  wire        scl
);

    pullup u_pullup_sda (sda);
    pullup u_pullup_scl (scl);

    i2c_master #(
        .SYS_CLK_FREQ (SYS_CLK_FREQ),
        .I2C_CLK_FREQ (I2C_CLK_FREQ),
        .CLK_DIV      (CLK_DIV)
    ) u_i2c_master (
        .clk              (clk),
        .rst_n            (rst_n),
        .start_cmd        (start_cmd),
        .rw_cmd           (rw_cmd),
        .mode_10bit       (mode_10bit),
        .use_reg_addr     (use_reg_addr),
        .slave_addr       (slave_addr),
        .reg_addr         (reg_addr),
        .byte_len         (byte_len),
        .wr_data_burst    (wr_data_burst),
        .rd_data_burst    (rd_data_burst),
        .rd_last_byte     (rd_last_byte),
        .rd_byte_valid    (rd_byte_valid),
        .busy             (busy),
        .done             (done),
        .ack_error        (ack_error),
        .stretch_detected (stretch_detected),
        .sda              (sda),
        .scl              (scl)
    );

    i2c_slave #(
        .SLAVE_ADDR_7BIT  (SLAVE_ADDR_7BIT),
        .SLAVE_ADDR_10BIT (SLAVE_ADDR_10BIT),
        .STRETCH_CYCLES   (STRETCH_CYCLES)
    ) u_i2c_slave (
        .clk          (clk),
        .rst_n        (rst_n),
        .stretch_en   (stretch_en),
        .last_wr_addr (slave_last_wr_addr),
        .last_wr_data (slave_last_wr_data),
        .wr_valid     (slave_wr_valid),
        .slave_busy   (slave_busy),
        .reg_00_out   (slave_reg_00),
        .reg_04_out   (slave_reg_04),
        .sda          (sda),
        .scl          (scl)
    );

endmodule