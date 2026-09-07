module predator_prey (
    input  logic clk,
    input  logic reset,
    input  logic tick,

    output logic signed [31:0] prey,
    output logic signed [31:0] predator
);

    parameter DATA_WIDTH = 32;

    // Q8.24 fixed point parameters
    parameter signed [31:0] ALPHA = 32'sd16777216;  // 1.0
    parameter signed [31:0] BETA  = 32'sd8388608;   // 0.5
    parameter signed [31:0] GAMMA = 32'sd16777216;  // 1.0
    parameter signed [31:0] DELTA = 32'sd8388608;   // 0.5
    parameter signed [31:0] H     = 32'sd16777;     // 0.001

    // ---------------------------------------------------------
    // PIPELINE STAGE 1: Calculate xy, alpha*prey, delta*predator
    // ---------------------------------------------------------
    logic signed [63:0] stg1_mult_xy, stg1_mult_alpha, stg1_mult_delta;
    
    logic signed [31:0] s1_xy, s1_alpha_prey, s1_delta_pred;
    logic signed [31:0] s1_prey, s1_predator;

    always_comb begin
        stg1_mult_xy    = prey * predator;
        stg1_mult_alpha = ALPHA * prey;
        stg1_mult_delta = DELTA * predator;
    end

    always_ff @(posedge clk) begin
        // Shift right by 24 for Q8.24 format
        s1_xy         <= stg1_mult_xy >>> 24;
        s1_alpha_prey <= stg1_mult_alpha >>> 24;
        s1_delta_pred <= stg1_mult_delta >>> 24;
        
        s1_prey       <= prey;
        s1_predator   <= predator;
    end

    // ---------------------------------------------------------
    // PIPELINE STAGE 2: Calculate dx and dy partials
    // ---------------------------------------------------------
    logic signed [63:0] stg2_mult_beta, stg2_mult_gamma;
    
    logic signed [31:0] s2_dx, s2_dy;
    logic signed [31:0] s2_prey, s2_predator;

    always_comb begin
        stg2_mult_beta  = BETA * s1_xy;
        stg2_mult_gamma = GAMMA * s1_xy;
    end

    always_ff @(posedge clk) begin
        // Shift right by 24 for Q8.24 format
        s2_dx <= s1_alpha_prey - (stg2_mult_beta >>> 24);
        s2_dy <= (stg2_mult_gamma >>> 24) - s1_delta_pred;
        
        s2_prey       <= s1_prey;
        s2_predator   <= s1_predator;
    end

    // ---------------------------------------------------------
    // PIPELINE STAGE 3: Multiply by H and add to original
    // ---------------------------------------------------------
    logic signed [63:0] stg3_mult_h_dx, stg3_mult_h_dy;
    
    logic signed [31:0] next_prey;
    logic signed [31:0] next_predator;

    always_comb begin
        stg3_mult_h_dx = H * s2_dx;
        stg3_mult_h_dy = H * s2_dy;
        
        // Shift right by 24 for Q8.24 format
        next_prey     = s2_prey + (stg3_mult_h_dx >>> 24);
        next_predator = s2_predator + (stg3_mult_h_dy >>> 24);
    end

    // ---------------------------------------------------------
    // SEQUENTIAL LOGIC: Update final registers on tick
    // ---------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            prey     <= 32'sd33554432; // 2.0 in Q8.24
            predator <= 32'sd16777216; // 1.0 in Q8.24
        end
        else if (tick) begin
            prey     <= next_prey;
            predator <= next_predator;
        end
    end

endmodule