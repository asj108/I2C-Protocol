`timescale 1ns / 1ps

module i2c_slave #(
    parameter [6:0]  SLAVE_ADDR_7BIT  = 7'h55,
    parameter [9:0]  SLAVE_ADDR_10BIT = 10'h2A5,
    parameter integer STRETCH_CYCLES  = 48
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       stretch_en,
    output reg  [3:0] last_wr_addr,
    output reg  [7:0] last_wr_data,
    output reg        wr_valid,
    output reg        slave_busy,
    output wire [7:0] reg_00_out,
    output wire [7:0] reg_04_out,

    inout  wire       sda,
    inout  wire       scl
);

    reg sda_oe;
    reg scl_oe;

    assign sda = sda_oe ? 1'b0 : 1'bz;
    assign scl = scl_oe ? 1'b0 : 1'bz;

    reg [1:0] sda_sync;
    reg [1:0] scl_sync;
    reg       sda_d;
    reg       scl_d;

    wire sda_curr = sda_sync[1];
    wire scl_curr = scl_sync[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_sync <= 2'b11;
            scl_sync <= 2'b11;
            sda_d    <= 1'b1;
            scl_d    <= 1'b1;
        end else begin
            sda_sync <= {sda_sync[0], sda};
            scl_sync <= {scl_sync[0], scl};
            sda_d    <= sda_curr;
            scl_d    <= scl_curr;
        end
    end

    wire scl_rising  = (!scl_d && scl_curr);
    wire scl_falling = (scl_d && !scl_curr);
    wire sda_rising  = (!sda_d && sda_curr);
    wire sda_falling = (sda_d && !sda_curr);

    wire start_cond = sda_falling && scl_curr && scl_d;
    wire stop_cond  = sda_rising && scl_curr && scl_d;

    localparam [3:0] SLV_IDLE      = 4'd0,
                     SLV_ADDR1     = 4'd1,
                     SLV_ACK_ADDR1 = 4'd2,
                     SLV_ADDR2     = 4'd3,
                     SLV_ACK_ADDR2 = 4'd4,
                     SLV_REG_PTR   = 4'd5,
                     SLV_ACK_REG   = 4'd6,
                     SLV_RX_DATA   = 4'd7,
                     SLV_ACK_RX    = 4'd8,
                     SLV_TX_DATA   = 4'd9,
                     SLV_WAIT_MACK = 4'd10;

    reg [3:0]  state;
    reg [3:0]  bit_cnt;
    reg [7:0]  rx_shift;
    reg [7:0]  tx_shift;
    reg [3:0]  reg_ptr;
    reg        rw_mode;
    reg        is_10bit_hdr;
    reg        ten_bit_matched;
    reg [15:0] stretch_cnt;

    reg [7:0] reg_mem [0:15];
    integer i;

    assign reg_00_out = reg_mem[0];
    assign reg_04_out = reg_mem[4];

    wire is_10bit_prefix = (rx_shift[7:3] == 5'b11110) &&
                           (rx_shift[2:1] == SLAVE_ADDR_10BIT[9:8]);

    wire [3:0] next_reg_ptr = reg_ptr + 4'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= SLV_IDLE;
            sda_oe          <= 1'b0;
            scl_oe          <= 1'b0;
            bit_cnt         <= 4'd0;
            rx_shift        <= 8'd0;
            tx_shift        <= 8'd0;
            reg_ptr         <= 4'd0;
            rw_mode         <= 1'b0;
            is_10bit_hdr    <= 1'b0;
            ten_bit_matched <= 1'b0;
            stretch_cnt     <= 16'd0;
            last_wr_addr    <= 4'd0;
            last_wr_data    <= 8'd0;
            wr_valid        <= 1'b0;
            slave_busy      <= 1'b0;
            reg_mem[0]      <= 8'h11;
            reg_mem[1]      <= 8'h22;
            reg_mem[2]      <= 8'h33;
            reg_mem[3]      <= 8'h44;
            for (i = 4; i < 16; i = i + 1) begin
                reg_mem[i] <= 8'h00;
            end
        end else begin
            wr_valid <= 1'b0;

            if (stop_cond) begin
                state           <= SLV_IDLE;
                sda_oe          <= 1'b0;
                scl_oe          <= 1'b0;
                ten_bit_matched <= 1'b0;
                slave_busy      <= 1'b0;
                stretch_cnt     <= 16'd0;
            end else if (start_cond) begin
                state       <= SLV_ADDR1;
                bit_cnt     <= 4'd0;
                sda_oe      <= 1'b0;
                scl_oe      <= 1'b0;
                slave_busy  <= 1'b1;
                stretch_cnt <= 16'd0;
            end else if (stretch_cnt > 16'd0) begin
                stretch_cnt <= stretch_cnt - 16'd1;
                if (stretch_cnt == 16'd1) begin
                    scl_oe <= 1'b0;
                end
            end else begin
                case (state)
                    SLV_IDLE: begin
                        sda_oe <= 1'b0;
                        scl_oe <= 1'b0;
                    end

                    SLV_ADDR1: begin
                        if (scl_rising) begin
                            rx_shift <= {rx_shift[6:0], sda_curr};
                            bit_cnt  <= bit_cnt + 4'd1;
                        end else if (scl_falling && (bit_cnt == 4'd8)) begin
                            bit_cnt <= 4'd0;
                            if (rx_shift[7:1] == SLAVE_ADDR_7BIT) begin
                                rw_mode      <= rx_shift[0];
                                is_10bit_hdr <= 1'b0;
                                sda_oe       <= 1'b1;
                                if (stretch_en) begin
                                    scl_oe      <= 1'b1;
                                    stretch_cnt <= STRETCH_CYCLES[15:0];
                                end
                                state <= SLV_ACK_ADDR1;
                            end else if (is_10bit_prefix &&
                                         ((rx_shift[0] == 1'b0) || ten_bit_matched)) begin
                                rw_mode      <= rx_shift[0];
                                is_10bit_hdr <= 1'b1;
                                sda_oe       <= 1'b1;
                                if (stretch_en) begin
                                    scl_oe      <= 1'b1;
                                    stretch_cnt <= STRETCH_CYCLES[15:0];
                                end
                                state <= SLV_ACK_ADDR1;
                            end else begin
                                sda_oe          <= 1'b0;
                                ten_bit_matched <= 1'b0;
                                state           <= SLV_IDLE;
                            end
                        end
                    end

                    SLV_ACK_ADDR1: begin
                        if (scl_falling) begin
                            bit_cnt <= 4'd0;
                            if (is_10bit_hdr && (rw_mode == 1'b0)) begin
                                sda_oe <= 1'b0;
                                state  <= SLV_ADDR2;
                            end else if (rw_mode == 1'b0) begin
                                sda_oe <= 1'b0;
                                state  <= SLV_REG_PTR;
                            end else begin
                                tx_shift <= reg_mem[reg_ptr];
                                sda_oe   <= ~reg_mem[reg_ptr][7];
                                state    <= SLV_TX_DATA;
                            end
                        end
                    end

                    SLV_ADDR2: begin
                        if (scl_rising) begin
                            rx_shift <= {rx_shift[6:0], sda_curr};
                            bit_cnt  <= bit_cnt + 4'd1;
                        end else if (scl_falling && (bit_cnt == 4'd8)) begin
                            bit_cnt <= 4'd0;
                            if (rx_shift == SLAVE_ADDR_10BIT[7:0]) begin
                                ten_bit_matched <= 1'b1;
                                sda_oe          <= 1'b1;
                                state           <= SLV_ACK_ADDR2;
                            end else begin
                                ten_bit_matched <= 1'b0;
                                sda_oe          <= 1'b0;
                                state           <= SLV_IDLE;
                            end
                        end
                    end

                    SLV_ACK_ADDR2: begin
                        if (scl_falling) begin
                            sda_oe  <= 1'b0;
                            bit_cnt <= 4'd0;
                            state   <= SLV_REG_PTR;
                        end
                    end

                    SLV_REG_PTR: begin
                        if (scl_rising) begin
                            rx_shift <= {rx_shift[6:0], sda_curr};
                            bit_cnt  <= bit_cnt + 4'd1;
                        end else if (scl_falling && (bit_cnt == 4'd8)) begin
                            bit_cnt <= 4'd0;
                            reg_ptr <= rx_shift[3:0];
                            sda_oe  <= 1'b1;
                            if (stretch_en) begin
                                scl_oe      <= 1'b1;
                                stretch_cnt <= STRETCH_CYCLES[15:0];
                            end
                            state <= SLV_ACK_REG;
                        end
                    end

                    SLV_ACK_REG: begin
                        if (scl_falling) begin
                            sda_oe  <= 1'b0;
                            bit_cnt <= 4'd0;
                            state   <= SLV_RX_DATA;
                        end
                    end

                    SLV_RX_DATA: begin
                        if (scl_rising) begin
                            rx_shift <= {rx_shift[6:0], sda_curr};
                            bit_cnt  <= bit_cnt + 4'd1;
                        end else if (scl_falling && (bit_cnt == 4'd8)) begin
                            bit_cnt          <= 4'd0;
                            reg_mem[reg_ptr] <= rx_shift;
                            last_wr_addr     <= reg_ptr;
                            last_wr_data     <= rx_shift;
                            wr_valid         <= 1'b1;
                            reg_ptr          <= next_reg_ptr;
                            sda_oe           <= 1'b1;
                            if (stretch_en) begin
                                scl_oe      <= 1'b1;
                                stretch_cnt <= STRETCH_CYCLES[15:0];
                            end
                            state <= SLV_ACK_RX;
                        end
                    end

                    SLV_ACK_RX: begin
                        if (scl_falling) begin
                            sda_oe  <= 1'b0;
                            bit_cnt <= 4'd0;
                            state   <= SLV_RX_DATA;
                        end
                    end

                    SLV_TX_DATA: begin
                        if (scl_rising) begin
                            bit_cnt <= bit_cnt + 4'd1;
                        end else if (scl_falling) begin
                            if (bit_cnt == 4'd8) begin
                                bit_cnt <= 4'd0;
                                sda_oe  <= 1'b0;
                                reg_ptr <= next_reg_ptr;
                                state   <= SLV_WAIT_MACK;
                            end else begin
                                tx_shift <= {tx_shift[6:0], 1'b0};
                                sda_oe   <= ~tx_shift[6];
                            end
                        end
                    end

                    SLV_WAIT_MACK: begin
                        if (scl_rising) begin
                            rx_shift[0] <= sda_curr;
                        end else if (scl_falling) begin
                            if (rx_shift[0] == 1'b0) begin
                                tx_shift <= reg_mem[reg_ptr];
                                sda_oe   <= ~reg_mem[reg_ptr][7];
                                bit_cnt  <= 4'd0;
                                state    <= SLV_TX_DATA;
                            end else begin
                                sda_oe <= 1'b0;
                                state  <= SLV_IDLE;
                            end
                        end
                    end

                    default: state <= SLV_IDLE;
                endcase
            end
        end
    end

endmodule