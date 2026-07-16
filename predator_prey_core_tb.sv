`timescale 1ns/1ps

module predator_prey_tb;

    logic clk;
    logic reset;
    logic tick;

    logic signed [31:0] prey;
    logic signed [31:0] predator;

    real real_val_prey;
    real real_val_predator;

    // Clock generation
    always #5 clk = ~clk;

    // Faster timer for simulation
    timer timer_inst (
        .clk(clk),
        .reset(reset),
        .tick(tick)
    );

    // Override H with larger value for simulation
    predator_prey dut (
        .clk(clk),
        .reset(reset),
        .tick(tick),
        .prey(prey),
        .predator(predator)
    );

    initial begin
        clk = 0;
        reset = 1;

        #20;
        reset = 0;

        #20000;

        $stop;
    end

    // Display only when tick occurs
    always @(posedge clk) begin
        if (tick) begin
	    real_val_prey = $itor(prey) / 65536.0;
	    real_val_predator = $itor(predator) / 65536.0;
            $display("Time=%0t | prey=%0d -> %0f | y=%0d -> %0f",
                     $time, prey, real_val_prey, predator, real_val_predator);
        end
    end

    // Waveform dump
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, predator_prey_tb);
    end

endmodule