module predator_prey (
    input  logic clk,
    input  logic reset,
    input  logic tick,                      // 1-cycle strobe when prey is valid / 1ms fires

    input  logic signed [31:0] prey,        // Supplied from PC (Q8.24)
    output logic signed [31:0] predator     // Computed by FPGA (Q8.24)
);

    parameter DATA_WIDTH = 32;

    // Q8.24 fixed point parameters
    parameter signed [31:0] GAMMA = 32'sd16777216;  // 1.0
    parameter signed [31:0] DELTA = 32'sd8388608;   // 0.5
    parameter signed [31:0] H     = 32'sd16777;     // 0.001

    // Initial state: 1.0 in Q8.24
    localparam signed [31:0] INIT_PREDATOR = 32'sd16777216;

    // ---------------------------------------------------------
    // STAGE 1: Multiplication (xy and delta * predator)
    // ---------------------------------------------------------
    logic signed [63:0] mult_xy;
    logic signed [63:0] mult_delta_pred;
    
    logic signed [31:0] s1_xy;
    logic signed [31:0] s1_delta_pred;
    logic signed [31:0] s1_predator;
    logic               s1_valid;

    always_comb begin
        mult_xy         = prey * predator;
        mult_delta_pred = DELTA * predator;
    end

    // ---------------------------------------------------------
    // STAGE 2: dy partial calculation (gamma * xy) - (delta * pred)
    // ---------------------------------------------------------
    logic signed [63:0] mult_gamma_xy;
    logic signed [31:0] s2_dy;
    logic signed [31:0] s2_predator;
    logic               s2_valid;

    always_comb begin
        mult_gamma_xy = GAMMA * s1_xy;
    end

    // ---------------------------------------------------------
    // STAGE 3: Scale by H and compute next predator
    // ---------------------------------------------------------
    logic signed [63:0] mult_h_dy;
    logic signed [31:0] next_predator;

    always_comb begin
        mult_h_dy     = H * s2_dy;
        next_predator = s2_predator + (mult_h_dy >>> 24);
    end

    // ---------------------------------------------------------
    // Synchronous Pipeline Progression
    // ---------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            predator      <= INIT_PREDATOR;
            s1_xy         <= '0;
            s1_delta_pred <= '0;
            s1_predator   <= '0;
            s1_valid      <= 1'b0;

            s2_dy         <= '0;
            s2_predator   <= '0;
            s2_valid      <= 1'b0;
        end else begin
            // Pipeline Stage 1
            if (tick) begin
                s1_xy         <= mult_xy >>> 24;
                s1_delta_pred <= mult_delta_pred >>> 24;
                s1_predator   <= predator;
                s1_valid      <= 1'b1;
            end else begin
                s1_valid      <= 1'b0;
            end

            // Pipeline Stage 2
            if (s1_valid) begin
                s2_dy       <= (mult_gamma_xy >>> 24) - s1_delta_pred;
                s2_predator <= s1_predator;
                s2_valid    <= 1'b1;
            end else begin
                s2_valid    <= 1'b0;
            end

            // Pipeline Stage 3 (Commit updated value)
            if (s2_valid) begin
                predator <= next_predator;
            end
        end
    end

endmodule