`timescale 1ns / 1ps

module uart_tx_tb();

    // ---------------------------------------------------------
    // 1. Signals Declaration
    // ---------------------------------------------------------
    logic clk;
    logic reset;
    logic valid_in;
    // logic baud_tick;
    logic [7:0] data_in;

    logic tx_out;
    logic done;
    // ---------------------------------------------------------
    // 2. Instantiate the DUT (Device Under Test)
    // ---------------------------------------------------------
    uart_tx dut (
        .clk(clk),
        .reset(reset),
        .valid_in(valid_in),
        // .baud_tick(baud_tick),
        .data_in(data_in),
        .tx_out(tx_out),
        .done(done)
    );

    // ---------------------------------------------------------
    // 3. Clock Generation (100 MHz)
    // ---------------------------------------------------------
    always #5 clk = ~clk; // 10ns period -> 100MHz

    // ---------------------------------------------------------
    // 5. Stimulus (Sending Data)
    // ---------------------------------------------------------
    initial begin
        // Initialize Inputs
        clk = 0;
        reset = 0;
        data_in = 8'h00;
        valid_in = 0;
        
        // Hold reset for a few clocks, then release
        repeat(2) @(posedge clk);
        reset = 1;
        @(posedge clk);
        reset = 0;
        
        // Wait a few baud ticks to let the system stabilize
        // repeat(3) @(posedge clk iff baud_tick);

        repeat(10) @(posedge clk);

        // --- TEST 1: Send 8'hA5 (Binary: 10100101) ---
        $display("\n[%0t] Starting Test 1: Sending 8'hA5 (10100101)", $time);
        data_in     = 8'hA5;
        valid_in = 1;
        
        // Hold valid_in until a baud_tick occurs so the DUT catches it
        // @(posedge clk iff baud_tick);
        @(posedge clk);
        valid_in = 0; 

        // Wait until the DUT says it is done
        @(posedge clk iff done);
        $display("[%0t] Test 1 Complete!", $time);

        // Idle delay between bytes
        repeat(5) @(posedge clk);

        $stop;

    end

endmodule