module uart_rx #(
    parameter int CLK_FREQ  = 100_000_000, // 100 MHz default
    parameter int BAUD_RATE = 115_200
)(
    input  logic       clk,       // System clock
    input  logic       rst,       // Active high reset
    input  logic       rx,        // Asynchronous RX input line
    output logic       rx_ready,  // Pulses high for 1 clock cycle on valid data
    output logic [7:0] rx_data    // 8-bit received byte
);

    // Calculate clock divider for 16x oversampling
    localparam int CLK_DIV = CLK_FREQ / (BAUD_RATE * 16);

    // Strongly typed enumerated states for cleaner debugging
    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_START,
        STATE_DATA,
        STATE_STOP
    } statetype_e;

    statetype_e state;
    
    // Internal counters and registers using native integer/logic sizing
    int unsigned   clk_count;
    logic [3:0]    sample_count; // 0 to 15 oversampling counter
    logic [2:0]    bit_index;    // 0 to 7 bit tracker
    logic [7:0]    rx_shift_reg;
    
    // Double-flop synchronizer to safely handle asynchronous input
    logic rx_sync_0, rx_sync_1;
    always_ff @(posedge clk) begin
        rx_sync_0 <= rx;
        rx_sync_1 <= rx_sync_0;
    end

    // 16x Baud Rate Generator tick
    logic baud_tick;
    assign baud_tick = (clk_count == (CLK_DIV - 1));

    always_ff @(posedge clk) begin
        if (rst) begin
            clk_count <= 0;
        end else if (baud_tick) begin
            clk_count <= 0;
        end else begin
            clk_count <= clk_count + 1;
        end
    end

    // Main FSM Controller
    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= STATE_IDLE;
            sample_count <= '0;
            bit_index    <= '0;
            rx_ready     <= 1'b0;
            rx_data      <= '0;
            rx_shift_reg <= '0;
        end else begin
            rx_ready <= 1'b0; // Default pulse state

            if (baud_tick) begin
                unique case (state)
                    
                    STATE_IDLE: begin
                        sample_count <= '0;
                        bit_index    <= '0;
                        if (!rx_sync_1) begin // Falling edge indicates start bit
                            state <= STATE_START;
                        end
                    end

                    STATE_START: begin
                        if (sample_count == 4'd7) begin // Center of the start bit
                            if (!rx_sync_1) begin       // Verify line is still low
                                sample_count <= '0;
                                state        <= STATE_DATA;
                            end else begin
                                state        <= STATE_IDLE; // False alarm glitch
                            end
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end

                    STATE_DATA: begin
                        if (sample_count == 4'd15) begin // Midpoint of the data bit
                            sample_count <= '0;
                            rx_shift_reg[bit_index] <= rx_sync_1;
                            
                            if (bit_index == 3'd7) begin
                                state <= STATE_STOP;
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end

                    STATE_STOP: begin
                        if (sample_count == 4'd15) begin // Midpoint of the stop bit
                            if (rx_sync_1) begin         // Verify valid high stop bit
                                rx_data  <= rx_shift_reg;
                                rx_ready <= 1'b1;        // Broadcast ready strobe
                            end
                            state <= STATE_IDLE;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end

                endcase
            end
        end
    end

endmodule
