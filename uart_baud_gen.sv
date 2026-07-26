module uart_baud_gen (
    input  logic clk,
    input  logic reset,
    output logic baud_tick
);

    parameter BAUD_COUNT_WIDTH = 10;
    parameter BAUD_COUNT_TO = 868;

    logic [BAUD_COUNT_WIDTH-1:0] baud_counter;

    always_comb begin
        if ((baud_counter == BAUD_COUNT_TO) || (baud_counter == BAUD_COUNT_TO + 1)) begin
            baud_tick = 1;
        end else begin
            baud_tick = 0;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            baud_counter <= 0;
        end else begin
            baud_counter <= baud_counter + 1;
        end
    end

endmodule