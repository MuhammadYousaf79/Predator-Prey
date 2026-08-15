module top (
    input logic clk,
    input logic reset,

    output logic tx_out
);

    logic        tick;
    logic [31:0] prey;
    logic [31:0] predator;
    
    logic [7:0]  data_in;
    logic        valid_in;
    logic        ready_out;
    logic        done;

    logic [31:0] prey_latched;
    logic [31:0] predator_latched;
    logic [2:0]  pack_counter;
    logic pack_en;
    logic pack_rst;

    predator_prey model (
        .clk(clk),
        .reset(reset),
        .tick(tick),
        .prey(prey),
        .predator(predator)
    );

    timer timer (
        .clk(clk),
        .reset(reset),
        .tick(tick)
    );

    uart_tx uart (
        .clk(clk),
        .reset(reset),
        .valid_in(valid_in),
        .ready_out(ready_out),
        .data_in(data_in),
        .tx_out(tx_out),
        .done(done)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset || pack_rst) begin
            pack_counter <= 3'b0;
        end else if (pack_en) begin
            pack_counter <= pack_counter + 3'b1;
        end
    end


    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            valid_in <= 1'b0;
            prey_latched     <= 32'b0;
            predator_latched <= 32'b0;
        end else if (tick) begin
            prey_latched <= prey;
            predator_latched <= predator;
            valid_in <= 1'b1;
            pack_rst <= 1'b1;
        end else begin
            pack_rst <= 1'b0;
        end
    end

    always_comb begin
        if (reset) begin
            data_in = 8'b0;
        end
        if (ready_out) begin
            case (pack_counter)
                3'd0: data_in = prey_latched[31:24];
                3'd1: data_in = prey_latched[23:16];
                3'd2: data_in = prey_latched[15:8];
                3'd3: data_in = prey_latched[7:0];
                3'd4: data_in = predator_latched[31:24];
                3'd5: data_in = predator_latched[23:16];
                3'd6: data_in = predator_latched[15:8];
                3'd7: data_in = predator_latched[7:0];
                default: data_in = 8'b0;
            endcase
            
        end
        if (done) begin
            pack_en = 1'b1;
        end else begin
            pack_en = 1'b0;
        end
    end
    
endmodule