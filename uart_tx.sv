module uart_tx (
    input  logic       clk,
    input  logic       reset,
    input  logic       valid_in,
    input  logic [7:0] data_in,

    output logic       tx_out,
    output logic       ready_out,
    output logic       done
);

    // Explicitly declare internal wires to connect datapath/controller
    logic       baud_tick;
    logic       of;
    logic [1:0] sel;
    logic       en;
    logic       clr;
    logic       load_reg;
    logic       shift;

    uart_baud_gen ubg (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick)
    );

    uart_tx_datapath datapath (
        .clk(clk),
        .reset(reset),
        .data_in(data_in),
        .load_reg(load_reg),
        .shift(shift),
        .clr(clr),
        .en(en),
        .sel(sel),
        .tx_out(tx_out),
        .of(of)
    );

    uart_tx_controller CTRL (
        .clk(clk),
        .reset(reset),
        .valid_in(valid_in),
        .ready_out(ready_out),
        .transfer(baud_tick),
        .of(of),
        .sel(sel),
        .en(en),
        .clr(clr),
        .load_reg(load_reg),
        .shift(shift),
        .done(done)
    );

endmodule