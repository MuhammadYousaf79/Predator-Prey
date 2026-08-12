module top_tb ();
    

    logic clk;
    logic reset;
    logic tx_out;

    top dut (
        .clk(clk),
        .reset(reset),
        .tx_out(tx_out)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;

        #20;
        reset = 0;
        
        
        repeat(2) @(posedge dut.tick);

        $stop;

    end


endmodule