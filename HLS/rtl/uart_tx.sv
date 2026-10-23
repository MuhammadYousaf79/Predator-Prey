// =============================================================================
// uart_tx.sv - 8N1 UART transmitter.
//              CLK_FREQ / BAUD_RATE must be an integer (100 MHz / 2 Mbaud = 50)
// =============================================================================
module uart_tx #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 2_000_000
)(
    input  logic       clk,
    input  logic       reset,
    input  logic       start,         // 1-cycle request, honoured when ready
    input  logic [7:0] data_in,

    output logic       tx_out,
    output logic       ready          // idle and able to accept a byte
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int CNT_W        = $clog2(CLKS_PER_BIT);

    logic [CNT_W-1:0] clk_cnt;
    logic [3:0]       bit_cnt;        // start + 8 data + stop = 10 bits
    logic [9:0]       frame;          // {stop, data[7:0], start}
    logic             busy;

    assign ready = !busy;

    always_ff @(posedge clk) begin
        if (reset) begin
            busy    <= 1'b0;
            clk_cnt <= '0;
            bit_cnt <= '0;
            frame   <= '1;
            tx_out  <= 1'b1;
        end else if (!busy) begin
            tx_out <= 1'b1;
            if (start) begin
                frame   <= {1'b1, data_in, 1'b0};
                tx_out  <= 1'b0;              // start bit
                busy    <= 1'b1;
                clk_cnt <= '0;
                bit_cnt <= '0;
            end
        end else if (clk_cnt == CNT_W'(CLKS_PER_BIT - 1)) begin
            clk_cnt <= '0;
            if (bit_cnt == 4'd9) begin
                busy   <= 1'b0;               // stop bit fully sent
                tx_out <= 1'b1;
            end else begin
                bit_cnt <= bit_cnt + 1'b1;
                tx_out  <= frame[bit_cnt + 1'b1];
            end
        end else begin
            clk_cnt <= clk_cnt + 1'b1;
        end
    end

endmodule
