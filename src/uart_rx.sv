module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       reset,
    input  logic       rx_in,

    output logic [7:0] rx_data,
    output logic       rx_valid,
    output logic       frame_error
);

    // 16x oversampling tick counter
    localparam OVERSAMPLE_DIV = CLK_FREQ / (BAUD_RATE * 16);
    logic [$clog2(OVERSAMPLE_DIV)-1:0] tick_cnt;
    logic tick_16x;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            tick_cnt <= '0;
            tick_16x <= 1'b0;
        end else if (tick_cnt == OVERSAMPLE_DIV - 1) begin
            tick_cnt <= '0;
            tick_16x <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 1'b1;
            tick_16x <= 1'b0;
        end
    end

    // 2-Stage Synchronizer for async rx_in
    logic rx_sync1, rx_sync;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_sync1 <= 1'b1;
            rx_sync  <= 1'b1;
        end else begin
            rx_sync1 <= rx_in;
            rx_sync  <= rx_sync1;
        end
    end

    // Receiver FSM
    typedef enum logic [1:0] { IDLE, START, DATA, STOP } rx_state_t;
    rx_state_t state;

    logic [3:0] sample_cnt;
    logic [2:0] bit_cnt;
    logic [7:0] rx_shift;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            sample_cnt  <= 4'd0;
            bit_cnt     <= 3'd0;
            rx_shift    <= 8'd0;
            rx_data     <= 8'd0;
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            rx_valid <= 1'b0; // Default: 1-cycle strobe

            if (tick_16x) begin
                case (state)
                    IDLE: begin
                        sample_cnt <= 4'd0;
                        bit_cnt    <= 3'd0;
                        // Detect falling edge of Start Bit
                        if (!rx_sync) begin
                            state <= START;
                        end
                    end

                    START: begin
                        // Wait 8 ticks to sample the middle of the Start Bit
                        if (sample_cnt == 4'd7) begin
                            if (!rx_sync) begin
                                sample_cnt <= 4'd0;
                                state      <= DATA;
                            end else begin
                                state <= IDLE; // False alarm (glitch/noise)
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end

                    DATA: begin
                        // Sample in the middle of each bit period (16 ticks)
                        if (sample_cnt == 4'd15) begin
                            sample_cnt <= 4'd0;
                            rx_shift   <= {rx_sync, rx_shift[7:1]}; // LSB first
                            
                            if (bit_cnt == 3'd7) begin
                                state <= STOP;
                            end else begin
                                bit_cnt <= bit_cnt + 3'd1;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end

                    STOP: begin
                        // Sample the Stop Bit at mid-point (16 ticks)
                        if (sample_cnt == 4'd15) begin
                            if (rx_sync == 1'b1) begin
                                rx_data     <= rx_shift;
                                rx_valid    <= 1'b1; // Successfully received byte
                                frame_error <= 1'b0;
                            end else begin
                                frame_error <= 1'b1; // Missing stop bit
                            end
                            state <= IDLE;
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule