module uart_tx #(
    parameter int CLK_FREQ  = 100_000_000, // 100 MHz default
    parameter int BAUD_RATE = 115_200
)(
    input  logic       clk,        // System clock
    input  logic       rst,        // Active high reset
    input  logic [7:0] tx_data,    // The 8-bit byte you want to send to the PC
    input  logic       tx_start,   // Pulse high for 1 cycle to kick off transmission
    output logic       tx,         // Physical output pin connected to PC RX
    output logic       tx_busy     // High when transmitting, low when ready for next byte
);

    // Calculate clock divider for exact baud rate
    localparam int CLK_DIV = CLK_FREQ / BAUD_RATE;

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_START_BIT,
        STATE_DATA_BITS,
        STATE_STOP_BIT
    } statetype_e;

    statetype_e state;

    int unsigned clk_count;
    logic [2:0]  bit_index;
    logic [7:0]  tx_shift_reg;

    // Main FSM Controller
    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= STATE_IDLE;
            clk_count    <= 0;
            bit_index    <= '0;
            tx_shift_reg <= '0;
            tx           <= 1'b1; // UART idle state is always HIGH
            tx_busy      <= 1'b0;
        end else begin
            case (state)

                STATE_IDLE: begin
                    tx      <= 1'b1; // Keep line high
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        tx_shift_reg <= tx_data; // Latch the data to send
                        tx_busy      <= 1'b1;
                        clk_count    <= 0;
                        state        <= STATE_START_BIT;
                    end
                end

                STATE_START_BIT: begin
                    tx <= 1'b0; // Drive line LOW for the Start Bit
                    if (clk_count == (CLK_DIV - 1)) begin
                        clk_count <= 0;
                        bit_index <= '0;
                        state     <= STATE_DATA_BITS;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                STATE_DATA_BITS: begin
                    tx <= tx_shift_reg[bit_index]; // Send bits out LSB first
                    if (clk_count == (CLK_DIV - 1)) begin
                        clk_count <= 0;
                        if (bit_index == 3'd7) begin
                            state <= STATE_STOP_BIT;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                STATE_STOP_BIT: begin
                    tx <= 1'b1; // Drive line HIGH for the Stop Bit
                    if (clk_count == (CLK_DIV - 1)) begin
                        clk_count <= 0;
                        state     <= STATE_IDLE; // Finished sending
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
