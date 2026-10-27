`timescale 1ns / 1ps

module i2c_master #(
    parameter integer SYS_CLK_FREQ = 100_000_000,
    parameter integer I2C_CLK_FREQ = 100_000,
    parameter integer CLK_DIV = SYS_CLK_FREQ / (4 * I2C_CLK_FREQ)
)(
    input wire clk,
    input wire rst_n,
    input wire start_cmd,
    input wire rw_cmd,
    input wire mode_10bit,
    input wire use_reg_addr,
    input wire [9:0] slave_addr,
    input wire [7:0] reg_addr,
    input wire [2:0] byte_len,
    input wire [31:0] wr_data_burst,
    output reg [31:0] rd_data_burst,
    output reg [7:0] rd_last_byte,
    output reg rd_byte_valid,
    output reg busy,
    output reg done,
    output reg ack_error,
    output reg stretch_detected,
    inout wire sda,
    inout wire scl
);

    reg sda_oe;
    reg scl_oe;

    assign sda = sda_oe ? 1'b0 : 1'bz;
    assign scl = scl_oe ? 1'b0 : 1'bz;

    reg [1:0] sda_sync;
    reg [1:0] scl_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_sync <= 2'b11;
            scl_sync <= 2'b11;
        end else begin
            sda_sync <= {sda_sync[0], sda};
            scl_sync <= {scl_sync[0], scl};
        end
    end

    wire sda_curr = sda_sync[1];
    wire scl_curr = scl_sync[1];

    localparam [2:0] ST_IDLE = 3'd0,
                     ST_START = 3'd1,
                     ST_SEND_BYTE = 3'd2,
                     ST_WAIT_ACK = 3'd3,
                     ST_REP_START = 3'd4,
                     ST_RECV_BYTE = 3'd5,
                     ST_SEND_ACK = 3'd6,
                     ST_STOP = 3'd7;

    localparam [2:0] PHASE_ADDR1 = 3'd0,
                     PHASE_ADDR2 = 3'd1,
                     PHASE_REG_ADDR = 3'd2,
                     PHASE_REP_ADDR = 3'd3,
                     PHASE_DATA = 3'd4;

    reg [2:0] state;
    reg [2:0] sub_phase;
    reg [1:0] quad;
    reg [15:0] div_cnt;
    reg [2:0] bit_cnt;
    reg [2:0] byte_idx;

    reg rw_reg;
    reg mode_10bit_reg;
    reg use_reg_addr_reg;
    reg [9:0] slave_addr_reg;
    reg [7:0] reg_addr_reg;
    reg [2:0] byte_len_reg;
    reg [31:0] wr_data_reg;

    reg [7:0] tx_shift;
    reg [7:0] rx_shift;

    wire [7:0] next_wr_byte = (byte_idx == 3'd0) ? wr_data_reg[7:0] :
                              (byte_idx == 3'd1) ? wr_data_reg[15:8] :
                              (byte_idx == 3'd2) ? wr_data_reg[23:16] :
                                                   wr_data_reg[31:24];

    wire [7:0] next_seq_wr_byte = (byte_idx == 3'd0) ? wr_data_reg[15:8] :
                                  (byte_idx == 3'd1) ? wr_data_reg[23:16] :
                                                       wr_data_reg[31:24];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            sub_phase <= PHASE_ADDR1;
            quad <= 2'd0;
            div_cnt <= 16'd0;
            bit_cnt <= 3'd7;
            byte_idx <= 3'd0;
            sda_oe <= 1'b0;
            scl_oe <= 1'b0;
            rw_reg <= 1'b0;
            mode_10bit_reg <= 1'b0;
            use_reg_addr_reg <= 1'b0;
            slave_addr_reg <= 10'd0;
            reg_addr_reg <= 8'd0;
            byte_len_reg <= 3'd1;
            wr_data_reg <= 32'd0;
            tx_shift <= 8'd0;
            rx_shift <= 8'd0;
            rd_data_burst <= 32'd0;
            rd_last_byte <= 8'd0;
            rd_byte_valid <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            ack_error <= 1'b0;
            stretch_detected <= 1'b0;
        end else begin
            done <= 1'b0;
            rd_byte_valid <= 1'b0;

            if (state == ST_IDLE) begin
                sda_oe <= 1'b0;
                scl_oe <= 1'b0;
                stretch_detected <= 1'b0;
                if (start_cmd) begin
                    busy <= 1'b1;
                    ack_error <= 1'b0;
                    rw_reg <= rw_cmd;
                    mode_10bit_reg <= mode_10bit;
                    use_reg_addr_reg <= use_reg_addr;
                    slave_addr_reg <= slave_addr;
                    reg_addr_reg <= reg_addr;
                    byte_len_reg <= (byte_len == 3'd0) ? 3'd1 :
                                    (byte_len > 3'd4) ? 3'd4 : byte_len;
                    wr_data_reg <= wr_data_burst;
                    rd_data_burst <= 32'd0;
                    byte_idx <= 3'd0;
                    quad <= 2'd0;
                    div_cnt <= 16'd0;
                    state <= ST_START;
                end
            end else begin
                if (quad == 2'd2 && !scl_oe &&
                    (div_cnt >= 16'd4) && !scl_curr) begin
                    stretch_detected <= 1'b1;
                end else begin
                    stretch_detected <= 1'b0;
                    if (div_cnt < CLK_DIV - 1) begin
                        div_cnt <= div_cnt + 16'd1;
                    end else begin
                        div_cnt <= 16'd0;

                        case (state)
                            ST_START: begin
                                case (quad)
                                    2'd0: begin
                                        scl_oe <= 1'b0;
                                        sda_oe <= 1'b0;
                                        quad <= 2'd1;
                                    end
                                    2'd1: begin
                                        scl_oe <= 1'b0;
                                        sda_oe <= 1'b1;
                                        quad <= 2'd2;
                                    end
                                    2'd2: begin
                                        scl_oe <= 1'b0;
                                        sda_oe <= 1'b1;
                                        quad <= 2'd3;
                                    end
                                    2'd3: begin
                                        scl_oe <= 1'b1;
                                        sda_oe <= 1'b1;
                                        quad <= 2'd0;
                                        bit_cnt <= 3'd7;
                                        sub_phase <= PHASE_ADDR1;
                                        if (mode_10bit_reg) begin
                                            tx_shift <= {5'b11110, slave_addr_reg[9:8], 1'b0};
                                        end else begin
                                            tx_shift <= {slave_addr_reg[6:0],
                                                         (use_reg_addr_reg ? 1'b0 : rw_reg)};
                                        end
                                        state <= ST_SEND_BYTE;
                                    end
                                endcase
                            end

                            ST_SEND_BYTE: begin
                                case (quad)
                                    2'd0: begin
                                        scl_oe <= 1'b1;
                                        sda_oe <= ~tx_shift[7];
                                        quad <= 2'd1;
                                    end
                                    2'd1: begin
                                        scl_oe <= 1'b0;
                                        quad <= 2'd2;
                                    end
                                    2'd2: begin
                                        scl_oe <= 1'b0;
                                        quad <= 2'd3;
                                    end
                                    2'd3: begin
                                        scl_oe <= 1'b1;
                                        quad <= 2'd0;
                                        if (bit_cnt == 3'd0) begin
                                            state <= ST_WAIT_ACK;
                                        end else begin
                                            bit_cnt <= bit_cnt - 3'd1;
                                            tx_shift <= {tx_shift[6:0], 1'b0};
                                        end
                                    end
                                endcase
                            end

                            ST_WAIT_ACK: begin
                                case (quad)
                                    2'd0: begin
                                        scl_oe <= 1'b1;
                                        sda_oe <= 1'b0;
                                        quad <= 2'd1;
                                    end
                                    2'd1: begin
                                        scl_oe <= 1'b0;
                                        quad <= 2'd2;
                                    end
                                    2'd2: begin
                                        scl_oe <= 1'b0;
                                        if (sda_curr == 1'b1)
                                            ack_error <= 1'b1;
                                        quad <= 2'd3;
                                    end
                                    2'd3: begin
                                        scl_oe <= 1'b1;
                                        quad <= 2'd0;
                                        if (ack_error) begin
                                            state <= ST_STOP;
                                        end else begin
                                            bit_cnt <= 3'd7;
                                            case (sub_phase)
                                                PHASE_ADDR1: begin
                                                    if (mode_10bit_reg) begin
                                                        sub_phase <= PHASE_ADDR2;
                                                        tx_shift <= slave_addr_reg[7:0];
                                                        state <= ST_SEND_BYTE;
                                                    end else if (use_reg_addr_reg) begin
                                                        sub_phase <= PHASE_REG_ADDR;
                                                        tx_shift <= reg_addr_reg;
                                                        state <= ST_SEND_BYTE;
                                                    end else begin
                                                        sub_phase <= PHASE_DATA;
                                                        if (rw_reg == 1'b0) begin
                                                            tx_shift <= next_wr_byte;
                                                            state <= ST_SEND_BYTE;
                                                        end else begin
                                                            state <= ST_RECV_BYTE;
                                                        end
                                                    end
                                                end

                                                PHASE_ADDR2: begin
                                                    if (use_reg_addr_reg) begin
                                                        sub_phase <= PHASE_REG_ADDR;
                                                        tx_shift <= reg_addr_reg;
                                                        state <= ST_SEND_BYTE;
                                                    end else if (rw_reg == 1'b0) begin
                                                        sub_phase <= PHASE_DATA;
                                                        tx_shift <= next_wr_byte;
                                                        state <= ST_SEND_BYTE;
                                                    end else begin
                                                        state <= ST_REP_START;
                                                    end
                                                end

                                                PHASE_REG_ADDR: begin
                                                    if (rw_reg == 1'b0) begin
                                                        sub_phase <= PHASE_DATA;
                                                        tx_shift <= next_wr_byte;
                                                        state <= ST_SEND_BYTE;
                                                    end else begin
                                                        state <= ST_REP_START;
                                                    end
                                                end

                                                PHASE_REP_ADDR: begin
                                                    sub_phase <= PHASE_DATA;
                                                    state <= ST_RECV_BYTE;
                                                end

                                                PHASE_DATA: begin
                                                    if (byte_idx + 3'd1 < byte_len_reg) begin
                                                        byte_idx <= byte_idx + 3'd1;
                                                        tx_shift <= next_seq_wr_byte;
                                                        state <= ST_SEND_BYTE;
                                                    end else begin
                                                        state <= ST_STOP;
                                                    end
                                                end

                                                default: state <= ST_STOP;
                                            endcase
                                        end
                                    end
                                endcase
                            end

                            ST_REP_START: begin
                                case (quad)
                                    2'd0: begin
                                        scl_oe <= 1'b1;
                                        sda_oe <= 1'b0;
                                        quad <= 2'd1;
                                    end
                                    2'd1: begin
                                        scl_oe <= 1'b0;
                                        sda_oe <= 1'b0;
                                        quad <= 2'd2;
                                    end
                                    2'd2: begin
                                        scl_oe <= 1'b0;
                                        sda_oe <= 1'b1;
                                        quad <= 2'd3;
                                    end
                                    2'd3: begin
                                        scl_oe <= 1'b1;
                                        sda_oe <= 1'b1;
                                        quad <= 2'd0;
                                        bit_cnt <= 3'd7;
                                        sub_phase <= PHASE_REP_ADDR;
                                        if (mode_10bit_reg) begin
                                            tx_shift <= {5'b11110, slave_addr_reg[9:8], 1'b1};
                                        end else begin
                                            tx_shift <= {slave_addr_reg[6:0], 1'b1};
                                        end
                                        state <= ST_SEND_BYTE;
                                    end
                                endcase
                            end

                            ST_RECV_BYTE: begin
                                case (quad)
                                    2'd0: begin
                                        scl_oe <= 1'b1;
                                        sda_oe <= 1'b0;
                                        quad <= 2'd1;
                                    end
                                    2'd1: begin
                                        scl_oe <= 1'b0;
                                        quad <= 2'd2;
                                    end
                                    2'd2: begin
                                        scl_oe <= 1'b0;
                                        rx_shift <= {rx_shift[6:0], sda_curr};
                                        quad <= 2'd3;
                                    end
                                    2'd3: begin
                                        scl_oe <= 1'b1;
                                        quad <= 2'd0;
                                        if (bit_cnt == 3'd0) begin
                                            rd_last_byte <= rx_shift;
                                            rd_byte_valid <= 1'b1;
                                            case (byte_idx[1:0])
                                                2'd0: rd_data_burst[7:0] <= rx_shift;
                                                2'd1: rd_data_burst[15:8] <= rx_shift;
                                                2'd2: rd_data_burst[23:16] <= rx_shift;
                                                2'd3: rd_data_burst[31:24] <= rx_shift;
                                            endcase
                                            state <= ST_SEND_ACK;
                                        end else begin
                                            bit_cnt <= bit_cnt - 3'd1;
                                        end
                                    end
                                endcase
                            end

                            ST_SEND_ACK: begin
                                case (quad)
                                    2'd0: begin
                                        scl_oe <= 1'b1;
                                        sda_oe <= (byte_idx + 3'd1 < byte_len_reg) ? 1'b1 : 1'b0;
                                        quad <= 2'd1;
                                    end
                                    2'd1: begin
                                        scl_oe <= 1'b0;
                                        quad <= 2'd2;
                                    end
                                    2'd2: begin
                                        scl_oe <= 1'b0;
                                        quad <= 2'd3;
                                    end
                                    2'd3: begin
                                        scl_oe <= 1'b1;
                                        quad <= 2'd0;
                                        if (byte_idx + 3'd1 < byte_len_reg) begin
                                            byte_idx <= byte_idx + 3'd1;
                                            bit_cnt <= 3'd7;
                                            state <= ST_RECV_BYTE;
                                        end else begin
                                            state <= ST_STOP;
                                        end
                                    end
                                endcase
                            end

                            ST_STOP: begin
                                case (quad)
                                    2'd0: begin
                                        scl_oe <= 1'b1;
                                        sda_oe <= 1'b1;
                                        quad <= 2'd1;
                                    end
                                    2'd1: begin
                                        scl_oe <= 1'b0;
                                        sda_oe <= 1'b1;
                                        quad <= 2'd2;
                                    end
                                    2'd2: begin
                                        scl_oe <= 1'b0;
                                        sda_oe <= 1'b0;
                                        quad <= 2'd3;
                                    end
                                    2'd3: begin
                                        scl_oe <= 1'b0;
                                        sda_oe <= 1'b0;
                                        quad <= 2'd0;
                                        busy <= 1'b0;
                                        done <= 1'b1;
                                        state <= ST_IDLE;
                                    end
                                endcase
                            end

                            default: state <= ST_IDLE;
                        endcase
                    end
                end
            end
        end
    end

endmodule