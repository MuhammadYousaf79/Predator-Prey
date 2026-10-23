// =============================================================================
// uart_rx.sv - 8N1 UART receiver, samples each bit at its centre.
//              CLK_FREQ / BAUD_RATE must be an integer (100 MHz / 2 Mbaud = 50)
// =============================================================================
module uart_rx #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 2_000_000
)(
    input  logic       clk,
    input  logic       reset,
    input  logic       rx_in,

    output logic [7:0] rx_data,
    output logic       rx_valid,      // 1-cycle strobe per received byte
    output logic       frame_error    // 1-cycle strobe on a missing stop bit
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int CNT_W        = $clog2(CLKS_PER_BIT);

    // 2-stage synchroniser for the asynchronous rx line
    (* ASYNC_REG = "TRUE" *) logic rx_meta, rx_sync;
    always_ff @(posedge clk) begin
        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx_in;
            rx_sync <= rx_meta;
        end
    end

    typedef enum logic [1:0] { IDLE, START, DATA, STOP } rx_state_t;
    rx_state_t state;

    logic [CNT_W-1:0] clk_cnt;
    logic [2:0]       bit_cnt;
    logic [7:0]       shift;

    always_ff @(posedge clk) begin
        if (reset) begin
            state       <= IDLE;
            clk_cnt     <= '0;
            bit_cnt     <= '0;
            shift       <= '0;
            rx_data     <= '0;
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;

            case (state)
                IDLE: begin
                    clk_cnt <= '0;
                    bit_cnt <= '0;
                    if (!rx_sync)
                        state <= START;
                end

                // Wait half a bit, re-check the line to reject glitches
                START: begin
                    if (clk_cnt == CNT_W'(CLKS_PER_BIT / 2 - 1)) begin
                        clk_cnt <= '0;
                        state   <= rx_sync ? IDLE : DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Sample the centre of each data bit, LSB first
                DATA: begin
                    if (clk_cnt == CNT_W'(CLKS_PER_BIT - 1)) begin
                        clk_cnt <= '0;
                        shift   <= {rx_sync, shift[7:1]};
                        if (bit_cnt == 3'd7)
                            state <= STOP;
                        else
                            bit_cnt <= bit_cnt + 1'b1;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Sample the centre of the stop bit, then return to IDLE at
                // once so the next start edge is not missed
                STOP: begin
                    if (clk_cnt == CNT_W'(CLKS_PER_BIT - 1)) begin
                        clk_cnt <= '0;
                        state   <= IDLE;
                        if (rx_sync) begin
                            rx_data  <= shift;
                            rx_valid <= 1'b1;
                        end else begin
                            frame_error <= 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
