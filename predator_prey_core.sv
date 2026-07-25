module predator_prey (
    input logic clk,
    input logic reset,
    input logic tick,

    output logic signed [31:0] prey,
    output logic signed [31:0] predator
);

    parameter DATA_WIDTH = 32;

    // Q16.16 fixed point
    parameter ALPHA = 32'd65536;   // 1.0
    parameter BETA  = 32'd32768;   // 0.5
    parameter GAMMA = 32'd65536;   // 1.0
    parameter DELTA = 32'd32768;   // 0.5
    parameter H     = 32'd66;   // 0.001

    logic signed [63:0] mult_xy;
    logic signed [63:0] mult1, mult2, mult3, mult4;

    logic signed [31:0] xy;
    logic signed [31:0] dx;
    logic signed [31:0] dy;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            prey <= 32'd131072; // 2.0
            predator <= 32'd65536;  // 1.0
        end

        else if (tick) begin

            // xy = x*y
            mult_xy = prey * predator;
            xy = mult_xy >>> 16;

            // dx = ALPHA*x - BETA*xy
            mult1 = ALPHA * prey;
            mult2 = BETA * xy;

            dx = (mult1 >>> 16) - (mult2 >>> 16);

            // dy = DELTA*xy - GAMMA*y
            mult3 = DELTA * xy;
            mult4 = GAMMA * predator;

            dy = (mult3 >>> 16) - (mult4 >>> 16);

            // Euler update
            prey <= prey + ((H * dx) >>> 16);
            predator <= predator + ((H * dy) >>> 16);
        end
    end

endmodule