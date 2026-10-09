module predator_prey (
    input  logic clk, reset, tick, valid_prey,
    input  logic signed [31:0] prey,
    output logic signed [31:0] predator,
    output logic done
);
    parameter signed [31:0] GAMMA = 32'sd16777216; // 1.0
    parameter signed [31:0] DELTA = 32'sd8388608;  // 0.5
    parameter signed [31:0] H     = 32'sd16777;    // 0.001
    localparam signed [31:0] Y0   = 32'sd16777216;

    logic prey_good;

    function automatic logic signed [31:0] qm(input logic signed [31:0] a, b);
        logic signed [63:0] p;
        p  = 64'(a) * 64'(b);
        qm = 32'(p >>> 24);
    endfunction

    logic signed [31:0] y_s, t2, t3, t4;
    logic [2:0] v;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            predator <= Y0; v <= '0; done <= 1'b0;
            y_s <= '0; t2 <= '0; t3 <= '0; t4 <= '0;
            prey_good <= 1'b0;
        end else begin
            done <= 1'b0;
            v    <= {v[1:0], tick};
            if (valid_prey) prey_good <= 1'b1;
            if (tick) begin
                y_s <= predator;
                if (prey_good || valid_prey) begin
                    t2  <= qm(GAMMA, prey) - DELTA;     // delta*x - gamma
                    prey_good <= 1'b0;
                end
            end
            if (v[0]) t3 <= qm(y_s, t2);            // y*(delta*x - gamma)
            if (v[1]) t4 <= qm(H, t3);              // h * that
            if (v[2]) begin predator <= y_s + t4; done <= 1'b1; end
        end
    end
endmodule