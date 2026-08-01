module top_tb ();
    

    logic clk;
    logic reset;
    logic tx_out;

    top top_dut (
        .clk(clk),
        .reset(reset),
        .tx_out(tx_out)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 0;

        @(posedge clk);
        reset = 1;
        repeat(2) @(posedge clk);
        reset = 0;


        #20000000

        $stop;

    end


endmodule