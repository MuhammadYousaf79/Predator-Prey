module uart_tx (

    input logic clk,
    input logic reset,
    input logic valid_in,
    input logic baud_tick,
    input logic [7:0] data_in,

    output logic tx_out,
    output logic done

);

    uart_baud_gen ubg (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick)
    );

    uart_tx_datapath datapath (
    
        .clk(clk),
        .reset(reset),
        .data_in(data_in),
        .valid_in(valid_in),
        .transfer(baud_tick),
        .er(er),
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
        .transfer(baud_tick),
        .of(of),
        .sel(sel),
        .er(er),
        .en(en),
        .clr(clr),
        .load_reg(load_reg),
        .shift(shift),
        .done(done)
    );


endmodule