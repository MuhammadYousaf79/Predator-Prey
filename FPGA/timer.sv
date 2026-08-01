 timer (
    input  logic clk,
    input  logic reset,
    output logic tick
);

    parameter COUNT_WIDTH = 17;
    parameter COUNT_TO = 100000;

    logic [COUNT_WIDTH-1:0] counter;

    always_comb begin
        if (counter >= COUNT_TO - 1) begin
            tick = 1;
        end else begin
            tick = 0;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 0;
        end else begin
            counter <= counter + 1;
        end
    end

