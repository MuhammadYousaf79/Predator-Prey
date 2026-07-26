module uart_baud_gen_tb ();
    
    logic clk;
    logic reset;
    logic baud_tick;

    always #0.5 clk = ~clk;

    uart_baud_gen dut (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick)
    );

    initial begin

        clk = 0;
        reset = 1;

        #20;
        reset = 0;

        #10000;

        $stop;

    end

endmodule