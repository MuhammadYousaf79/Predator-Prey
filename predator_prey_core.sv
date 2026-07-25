module predator_prey (
    input  logic clk,
    input  logic reset,
    input  logic tick,

    output logic signed [31:0] prey,
    output logic signed [31:0] predator
);

    parameter DATA_WIDTH = 32;

    // Q16.16 fixed point
    // FIXED: Added 'signed' and 'sd' to force signed arithmetic
    parameter signed [31:0] ALPHA = 32'sd65536;   // 1.0
    parameter signed [31:0] BETA  = 32'sd32768;   // 0.5
    parameter signed [31:0] GAMMA = 32'sd65536;   // 1.0
    parameter signed [31:0] DELTA = 32'sd32768;   // 0.5
    parameter signed [31:0] H     = 32'sd66;      // 0.001

    // Combinational intermediates
    logic signed [63:0] mult_xy, mult1, mult2, mult3, mult4;
    logic signed [63:0] mult_h_dx, mult_h_dy;
    
    logic signed [31:0] xy;
    logic signed [31:0] dx;
    logic signed [31:0] dy;
    
    logic signed [31:0] next_prey;
    logic signed [31:0] next_predator;

    // ---------------------------------------------------------
    // COMBINATIONAL LOGIC: Calculate the next values
    // ---------------------------------------------------------
    always_comb begin
        // xy = x * y
        // (Verilog automatically sign-extends 32-bit to 64-bit here because LHS is 64-bit)
        mult_xy = prey * predator;
        xy = mult_xy >>> 16;

        // dx = ALPHA*x - BETA*xy
        mult1 = ALPHA * prey;
        mult2 = BETA * xy;
        dx = (mult1 >>> 16) - (mult2 >>> 16);

        // dy = GAMMA*xy - DELTA*y (FIXED: Swapped GAMMA and DELTA)
        mult3 = GAMMA * xy; 
        mult4 = DELTA * predator; 
        dy = (mult3 >>> 16) - (mult4 >>> 16);

        // Euler update calculations
        mult_h_dx = H * dx;
        mult_h_dy = H * dy;
        
        next_prey = prey + (mult_h_dx >>> 16);
        next_predator = predator + (mult_h_dy >>> 16);
    end

    // ---------------------------------------------------------
    // SEQUENTIAL LOGIC: Update registers on clock edge
    // ---------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // FIXED: Used signed decimals for initial state
            prey     <= 32'sd131072; // 2.0 in Q16.16
            predator <= 32'sd65536;  // 1.0 in Q16.16
        end
        else if (tick) begin
            prey     <= next_prey;
            predator <= next_predator;
        end
    end

endmodule