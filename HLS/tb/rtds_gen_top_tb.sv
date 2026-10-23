// =============================================================================
// rtds_gen_top_tb.sv - System test of rtds_gen_top over the real UART pins
//
// The testbench plays the CPU: it sends an INIT frame, then N STEP frames,
// and checks every 45-byte result frame bit-exactly against
// gen_step_golden.hex, which the HLS C testbench writes (csim).
// It also checks that results arrive on the 1 ms grid.
// =============================================================================
`timescale 1ns / 1ps

module rtds_gen_top_tb;

    parameter string GOLDEN = "gen_step_golden.hex";
    localparam int   N_STEPS  = 4;
    localparam int   N_INIT_W = 11;
    localparam int   N_OUT_W  = 11;
    localparam int   N_GOLD_W = N_INIT_W + N_STEPS * (2 + N_OUT_W);
    localparam real  BIT_NS   = 500.0;          // 2 Mbaud

    logic       clk = 0;
    logic       rst_n = 0;
    logic       rx_line = 1;                    // CPU -> FPGA
    wire        tx_line;                        // FPGA -> CPU
    wire        done_o;
    wire [3:0]  led_o;

    always #5 clk = ~clk;                       // 100 MHz

    rtds_gen_top dut (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(rx_line), .uart_tx_o(tx_line),
        .done_o(done_o), .led_o(led_o)
    );

    logic [31:0] gold [N_GOLD_W];
    int errors = 0;

    // ---------------------------------------------------------- UART models
    task automatic send_byte(input logic [7:0] b);
        rx_line = 1'b0;                         // start
        #(BIT_NS);
        for (int i = 0; i < 8; i++) begin
            rx_line = b[i];
            #(BIT_NS);
        end
        rx_line = 1'b1;                         // stop
        #(BIT_NS);
    endtask

    task automatic send_word(input logic [31:0] w);
        for (int i = 3; i >= 0; i--) send_byte(w[8*i +: 8]);
    endtask

    task automatic recv_byte(output logic [7:0] b);
        @(negedge tx_line);
        #(BIT_NS * 1.5);
        for (int i = 0; i < 8; i++) begin
            b[i] = tx_line;
            #(BIT_NS);
        end
        if (tx_line !== 1'b1) begin
            $display("ERROR: stop bit missing on tx");
            errors++;
        end
    endtask

    task automatic recv_word(output logic [31:0] w);
        logic [7:0] b;
        for (int i = 3; i >= 0; i--) begin
            recv_byte(b);
            w[8*i +: 8] = b;
        end
    endtask

    // ------------------------------------------------------------- stimulus
    initial begin
        logic [7:0]  hdr;
        logic [31:0] w;
        int          base;
        realtime     t_done [N_STEPS];

        $readmemh(GOLDEN, gold);

        #200 rst_n = 1;
        #1000;

        // INIT: equilibrium state + set-points
        send_byte(8'hA5);
        for (int i = 0; i < N_INIT_W; i++) send_word(gold[i]);
        #5000;
        if (led_o[0] !== 1'b1) begin
            $display("ERROR: core not initialised after INIT frame");
            errors++;
        end

        for (int k = 0; k < N_STEPS; k++) begin
            base = N_INIT_W + k * (2 + N_OUT_W);

            send_byte(8'h5A);
            send_word(gold[base]);              // V
            send_word(gold[base + 1]);          // theta

            recv_byte(hdr);
            t_done[k] = $realtime;
            if (hdr !== 8'hC3) begin
                $display("ERROR step %0d: header %h", k, hdr);
                errors++;
            end
            for (int i = 0; i < N_OUT_W; i++) begin
                recv_word(w);
                if (w !== gold[base + 2 + i]) begin
                    $display("ERROR step %0d word %0d: got %h expected %h",
                             k, i, w, gold[base + 2 + i]);
                    errors++;
                end
            end
            $display("[%0t ns] step %0d: delta=%f omega=%f Pg=%f Qg=%f",
                     $time, k,
                     $signed(gold[base + 2]) / 16777216.0,
                     $signed(gold[base + 3]) / 16777216.0,
                     $signed(gold[base + 11]) / 16777216.0,
                     $signed(gold[base + 12]) / 16777216.0);
        end

        // consecutive results must be on the 1 ms tick grid
        for (int k = 1; k < N_STEPS; k++) begin
            real dt = (t_done[k] - t_done[k-1]) / 1.0e6;
            if (dt < 0.999 || dt > 1.001) begin
                $display("ERROR: step period %f ms", dt);
                errors++;
            end
        end
        if (led_o[3] !== 1'b0) begin
            $display("ERROR: deadline-miss LED set");
            errors++;
        end
        if (led_o[2] !== 1'b0) begin
            $display("ERROR: UART frame-error LED set");
            errors++;
        end

        if (errors == 0) $display("\n*** RTL TEST PASSED (%0d steps) ***", N_STEPS);
        else             $display("\n*** RTL TEST FAILED: %0d errors ***", errors);
        $finish;
    end

    // done_o must pulse once per step
    int done_cnt = 0;
    always @(posedge done_o) done_cnt++;
    final $display("done_o pulses: %0d", done_cnt);

    initial begin
        #20ms;
        $display("ERROR: timeout");
        $finish;
    end

endmodule
