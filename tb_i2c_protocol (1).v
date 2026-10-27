`timescale 1ns / 1ps

module tb_i2c_protocol;

    localparam integer SIM_CLK_DIV = 16;
    localparam integer STRETCH_CYCLES = 48;

    reg clk;
    reg rst_n;
    reg start_cmd;
    reg rw_cmd;
    reg mode_10bit;
    reg use_reg_addr;
    reg [9:0] slave_addr;
    reg [7:0] reg_addr;
    reg [2:0] byte_len;
    reg [31:0] wr_data_burst;
    reg stretch_en;

    wire [31:0] rd_data_burst;
    wire [7:0] rd_last_byte;
    wire rd_byte_valid;
    wire busy;
    wire done;
    wire ack_error;
    wire stretch_detected;
    wire [3:0] slave_last_wr_addr;
    wire [7:0] slave_last_wr_data;
    wire slave_wr_valid;
    wire slave_busy;
    wire [7:0] slave_reg_00;
    wire [7:0] slave_reg_04;

    wire sda;
    wire scl;

    integer pass_count;
    integer fail_count;
    reg saw_stretch_flag;

    i2c_system_top #(
        .SYS_CLK_FREQ(100_000_000),
        .I2C_CLK_FREQ(100_000),
        .CLK_DIV(SIM_CLK_DIV),
        .SLAVE_ADDR_7BIT(7'h55),
        .SLAVE_ADDR_10BIT(10'h2A5),
        .STRETCH_CYCLES(STRETCH_CYCLES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_cmd(start_cmd),
        .rw_cmd(rw_cmd),
        .mode_10bit(mode_10bit),
        .use_reg_addr(use_reg_addr),
        .slave_addr(slave_addr),
        .reg_addr(reg_addr),
        .byte_len(byte_len),
        .wr_data_burst(wr_data_burst),
        .stretch_en(stretch_en),
        .rd_data_burst(rd_data_burst),
        .rd_last_byte(rd_last_byte),
        .rd_byte_valid(rd_byte_valid),
        .busy(busy),
        .done(done),
        .ack_error(ack_error),
        .stretch_detected(stretch_detected),
        .slave_last_wr_addr(slave_last_wr_addr),
        .slave_last_wr_data(slave_last_wr_data),
        .slave_wr_valid(slave_wr_valid),
        .slave_busy(slave_busy),
        .slave_reg_00(slave_reg_00),
        .slave_reg_04(slave_reg_04),
        .sda(sda),
        .scl(scl)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (start_cmd)
            saw_stretch_flag <= 1'b0;
        else if (stretch_detected)
            saw_stretch_flag <= 1'b1;
    end

    task run_i2c_xfer(
        input t_rw,
        input t_10bit,
        input t_use_reg,
        input [9:0] t_saddr,
        input [7:0] t_raddr,
        input [2:0] t_len,
        input [31:0] t_wdata,
        input t_stretch
    );
        begin
            @(posedge clk);
            rw_cmd <= t_rw;
            mode_10bit <= t_10bit;
            use_reg_addr <= t_use_reg;
            slave_addr <= t_saddr;
            reg_addr <= t_raddr;
            byte_len <= t_len;
            wr_data_burst <= t_wdata;
            stretch_en <= t_stretch;
            start_cmd <= 1'b1;
            @(posedge clk);
            start_cmd <= 1'b0;

            wait (done == 1'b1);
            repeat (20) @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("i2c_protocol_sim.vcd");
        $dumpvars(0, tb_i2c_protocol);

        pass_count = 0;
        fail_count = 0;
        rst_n = 1'b0;
        start_cmd = 1'b0;
        rw_cmd = 1'b0;
        mode_10bit = 1'b0;
        use_reg_addr = 1'b1;
        slave_addr = 10'h055;
        reg_addr = 8'h00;
        byte_len = 3'd1;
        wr_data_burst = 32'd0;
        stretch_en = 1'b0;

        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        $display("======================================================================");
        $display(" STARTING VIVADO I2C PROTOCOL GROUND-UP SELF-CHECKING TESTBENCH");
        $display("======================================================================");

        run_i2c_xfer(1'b0, 1'b0, 1'b1, 10'h055, 8'h04, 3'd1, 32'h0000_00A5, 1'b0);
        if (!ack_error && (slave_reg_04 == 8'hA5)) begin
            $display("[PASS] Test 1: 7-Bit Single-Byte Write  | Reg[0x04] = 0x%02X", slave_reg_04);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 1: 7-Bit Single-Byte Write  | ack_err=%b, Reg[0x04]=0x%02X", ack_error, slave_reg_04);
            fail_count = fail_count + 1;
        end

        run_i2c_xfer(1'b1, 1'b0, 1'b1, 10'h055, 8'h04, 3'd1, 32'h0000_0000, 1'b0);
        if (!ack_error && (rd_data_burst[7:0] == 8'hA5)) begin
            $display("[PASS] Test 2: 7-Bit Repeated-START Read| Read Data = 0x%02X", rd_data_burst[7:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 2: 7-Bit Repeated-START Read| ack_err=%b, Read=0x%02X", ack_error, rd_data_burst[7:0]);
            fail_count = fail_count + 1;
        end

        run_i2c_xfer(1'b0, 1'b0, 1'b1, 10'h055, 8'h08, 3'd4, 32'hCAFE_BEEF, 1'b0);
        if (!ack_error && (slave_last_wr_addr == 4'hB) && (slave_last_wr_data == 8'hCA)) begin
            $display("[PASS] Test 3: 7-Bit 4-Byte Burst Write | Reg[0x08..0x0B] Written (Last=0x%02X)", slave_last_wr_data);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 3: 7-Bit 4-Byte Burst Write | ack_err=%b, LastAddr=0x%0X", ack_error, slave_last_wr_addr);
            fail_count = fail_count + 1;
        end

        run_i2c_xfer(1'b1, 1'b0, 1'b1, 10'h055, 8'h08, 3'd4, 32'h0000_0000, 1'b0);
        if (!ack_error && (rd_data_burst == 32'hCAFE_BEEF)) begin
            $display("[PASS] Test 4: 7-Bit 4-Byte Burst Read  | Read Word = 0x%08X", rd_data_burst);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 4: 7-Bit 4-Byte Burst Read  | ack_err=%b, Read=0x%08X", ack_error, rd_data_burst);
            fail_count = fail_count + 1;
        end

        run_i2c_xfer(1'b0, 1'b1, 1'b1, 10'h2A5, 8'h0C, 3'd2, 32'h0000_1234, 1'b0);
        run_i2c_xfer(1'b1, 1'b1, 1'b1, 10'h2A5, 8'h0C, 3'd2, 32'h0000_0000, 1'b0);
        if (!ack_error && (rd_data_burst[15:0] == 16'h1234)) begin
            $display("[PASS] Test 5: 10-Bit Addressing R/W    | Slave=10'h2A5, Read=0x%04X", rd_data_burst[15:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 5: 10-Bit Addressing R/W    | ack_err=%b, Read=0x%04X", ack_error, rd_data_burst[15:0]);
            fail_count = fail_count + 1;
        end

        run_i2c_xfer(1'b0, 1'b0, 1'b1, 10'h055, 8'h05, 3'd1, 32'h0000_007E, 1'b1);
        if (!ack_error && saw_stretch_flag && (slave_last_wr_data == 8'h7E)) begin
            $display("[PASS] Test 6: Slave Clock Stretching   | Stretch Handshake Verified (Data=0x%02X)", slave_last_wr_data);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 6: Slave Clock Stretching   | ack_err=%b, stretch=%b", ack_error, saw_stretch_flag);
            fail_count = fail_count + 1;
        end

        run_i2c_xfer(1'b0, 1'b0, 1'b1, 10'h055, 8'h06, 3'd1, 32'h0000_009C, 1'b0);
        run_i2c_xfer(1'b1, 1'b0, 1'b1, 10'h055, 8'h00, 3'd4, 32'h0000_0000, 1'b0);
        if (!ack_error && (rd_data_burst == 32'h4433_2211)) begin
            $display("[PASS] Test 7: Default ROM Burst Read   | Reg[0x00..0x03] = 0x%08X", rd_data_burst);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 7: Default ROM Burst Read   | ack_err=%b, Read=0x%08X", ack_error, rd_data_burst);
            fail_count = fail_count + 1;
        end

        run_i2c_xfer(1'b0, 1'b0, 1'b1, 10'h077, 8'h00, 3'd1, 32'h0000_0099, 1'b0);
        if (ack_error && !busy) begin
            $display("[PASS] Test 8: Address NACK Recovery    | Unmapped Addr 7'h77 NACKed & Bus Released");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 8: Address NACK Recovery    | ack_err=%b, busy=%b", ack_error, busy);
            fail_count = fail_count + 1;
        end

        $display("======================================================================");
        $display(" TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("======================================================================");
        $finish;
    end

endmodule