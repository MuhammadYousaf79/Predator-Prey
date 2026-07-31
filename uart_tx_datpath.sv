module uart_tx_datapath(
    
    input logic           clk,
    input logic           reset,
    input logic     [7:0] data_in,
    input logic           valid_in,
    input logic           transfer,
    input logic           er,
    input logic           load_reg,
    input logic           shift,
    input logic           clr,
    input logic           en,
    input logic     [1:0] sel,

    output logic           tx_out,
    output logic           of

);

    logic [7:0] reg_a;
    logic [7:0] shift_reg;
    logic [2:0] counter;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            reg_a <= 8'b0;
        end else if (en) begin
            reg_a <= data_in;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            shift_reg <= 8'b0;
        end else if (load_reg) begin
            shift_reg <= data_in;
        end else if (shift) begin
            shift_reg <= shift_reg >> 1;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset || clr) begin
            counter <= 3'b0;
        end else if (en) begin
            counter <= counter + 3'b1;
        end
    end

    always_comb begin

        of = (counter == 3'b111);

        if (sel == 2'b00) begin
            tx_out = 0;
        end else if (sel == 2'b01) begin
            tx_out = 1;
        end else if (sel == 2'b10) begin
            tx_out = shift_reg[0];
        end
    end

endmodule