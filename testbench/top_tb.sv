module top_tb ();
    

    logic clk;
    logic reset;
    logic tx_out;
    logic rx_in;

    top dut (
        .clk(clk),
        .reset(reset),
        .rx_in(rx_in),
        .tx_out(tx_out)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;

        #20;
        reset = 0;
        
        
        repeat(11) @(posedge dut.tick_1ms);

        $stop;

    end


endmodule