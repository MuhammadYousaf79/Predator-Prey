module timer_tb();
    
    logic clk;
    logic reset;
    logic tick;

    always #5 clk = ~clk;

    timer dut (
        .clk(clk),
        .reset(reset),
        .tick(tick)
    );

    initial begin

        clk = 0;
        reset = 1;

        #20;
        reset = 0;

        repeat(3) @(posedge tick);

        $stop;

    end

endmodule