module predator_prey (
    input  logic clk,
    input  logic reset,
    input  logic tick,

    output logic signed [31:0] prey,
    output logic signed [31:0] predator
);

    parameter DATA_WIDTH = 32;

    // Q16.16 fixed point parameters
    parameter signed [31:0] ALPHA = 32'sd65536;   // 1.0
    parameter signed [31:0] BETA  = 32'sd32768;   // 0.5
    parameter signed [31:0] GAMMA = 32'sd65536;   // 1.0
    parameter signed [31:0] DELTA = 32'sd32768;   // 0.5
    parameter signed [31:0] H     = 32'sd66;      // 0.001

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
        // Shift and store intermediate calculations
        s1_xy         <= stg1_mult_xy >>> 16;
        s1_alpha_prey <= stg1_mult_alpha >>> 16;
        s1_delta_pred <= stg1_mult_delta >>> 16;
        
        // Pass the raw populations along the pipeline
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
        // dx = (ALPHA*prey) - (BETA*xy)
        s2_dx <= s1_alpha_prey - (stg2_mult_beta >>> 16);
        
        // dy = (GAMMA*xy) - (DELTA*predator)
        s2_dy <= (stg2_mult_gamma >>> 16) - s1_delta_pred;
        
        // Pass the raw populations down to the final stage
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
        
        // next = current + (H * derivative)
        next_prey     = s2_prey + (stg3_mult_h_dx >>> 16);
        next_predator = s2_predator + (stg3_mult_h_dy >>> 16);
    end

    // ---------------------------------------------------------
    // SEQUENTIAL LOGIC: Update final registers on tick
    // ---------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            prey     <= 32'sd131072; // 2.0 in Q16.16
            predator <= 32'sd65536;  // 1.0 in Q16.16
        end
        else if (tick) begin
            prey     <= next_prey;
            predator <= next_predator;
        end
    end

endmodule