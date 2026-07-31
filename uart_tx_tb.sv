`timescale 1ns / 1ps

module uart_tx_tb();

    // ---------------------------------------------------------
    // 1. Signals Declaration
    // ---------------------------------------------------------
    logic       clk = 0;
    logic       reset;
    logic       tx_start;
    logic       baud_tick;
    logic [7:0] data;
    
    logic       tx_active;
    logic       tx_out;
    logic       tx_done;

    // ---------------------------------------------------------
    // 2. Instantiate the DUT (Device Under Test)
    // ---------------------------------------------------------
    uart_tx dut (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .baud_tick(baud_tick),
        .data(data),
        .tx_active(tx_active),
        .tx_out(tx_out),
        .tx_done(tx_done)
    );

    uart_baud_gen ubg (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick)
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
        reset    = 1;
        tx_start = 0;
        data     = 8'h00;
        
        // Hold reset for a few clocks, then release
        repeat(5) @(posedge clk);
        reset = 0;
        
        // Wait a few baud ticks to let the system stabilize
        repeat(3) @(posedge clk iff baud_tick);

        // repeat(2) @(posedge clk);

        // --- TEST 1: Send 8'hA5 (Binary: 10100101) ---
        $display("\n[%0t] Starting Test 1: Sending 8'hA5 (10100101)", $time);
        data     = 8'hA5;
        tx_start = 1;
        
        // Hold tx_start until a baud_tick occurs so the DUT catches it
        @(posedge clk iff baud_tick);
        // @(posedge clk);
        tx_start = 0; 

        // Wait until the DUT says it is done
        @(posedge clk iff tx_done);
        $display("[%0t] Test 1 Complete!", $time);

        // Idle delay between bytes
        repeat(5) @(posedge clk iff baud_tick);

        // --- TEST 2: Send 8'h3C (Binary: 00111100) ---
        $display("\n[%0t] Starting Test 2: Sending 8'h3C (00111100)", $time);
        data     = 8'h3C;
        tx_start = 1;
        
        @(posedge clk iff baud_tick);
        tx_start = 0;

        @(posedge clk iff tx_done);
        $display("[%0t] Test 2 Complete!\n", $time);
        
        // Give it some time to idle before finishing
        repeat(10) @(posedge clk);
        $display("Simulation Finished Successfully.");
        $stop;
    end

    // ---------------------------------------------------------
    // 6. UART Receiver (Self-Checking Monitor)
    // ---------------------------------------------------------
    logic [7:0] rx_data;
    
    initial begin
        forever begin
            // 1. Wait for start bit (falling edge of tx_out)
            @(negedge tx_out);
            $display("[%0t] Monitor: Start bit detected!", $time);
            
            // 2. Wait 1 full baud period to sample the first data bit
            repeat(ubg.BAUD_COUNT_TO) @(posedge clk);
            
            // 3. Sample 8 data bits (LSB first)
            for (int i = 0; i < 8; i++) begin
                rx_data[i] = tx_out;
                $display("[%0t] Monitor: Bit %0d sampled as %b", $time, i, tx_out);
                repeat(ubg.BAUD_COUNT_TO) @(posedge clk);
            end
            
            // 4. Check Stop bit
            if (tx_out == 1'b1)
                $display("[%0t] Monitor: Stop bit valid! Reconstructed Byte: 8'h%h", $time, rx_data);
            else
                $error("[%0t] Monitor: Stop bit ERROR! tx_out is low.", $time);
        end
    end

endmodule