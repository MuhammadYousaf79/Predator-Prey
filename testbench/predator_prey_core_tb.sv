`timescale 1ns/1ps

module predator_prey_tb;

    logic clk;
    logic reset;
    logic tick;

    logic signed [31:0] prey;
    logic signed [31:0] predator;

    real real_val_prey;
    real real_val_predator;
    int c = 0;
    integer csv_file;

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
        csv_file = $fopen("../script/pipeline_predator_prey.csv", "w");

        if (csv_file == 0) begin
            $display("ERROR: Could not open CSV file.");
            $stop;
        end
    end

    initial begin
        clk = 0;
        reset = 1;

        #20;
        reset = 0;

        #1400000;

        $stop;
    end

    // Display only when tick occurs
    always @(posedge clk) begin
        if (tick) begin
        c = c+1;
	    real_val_prey = $itor(prey) / 65536.0;
	    real_val_predator = $itor(predator) / 65536.0;
            $display("Iter=%0d | Time=%0t | prey=%0d -> %0f | y=%0d -> %0f",
                     c, $time, prey, real_val_prey, predator, real_val_predator);
        $fwrite(csv_file, "%0d,%0d\n", prey, predator);
        end

    end

    // Waveform dump
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, predator_prey_tb);
    end

endmodule