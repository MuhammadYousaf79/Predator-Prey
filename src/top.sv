module top (
    input  logic clk,
    input  logic reset,
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
    logic [3:0]  pack_counter;
    logic        pack_en;
    logic        sending;

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

    // Latch values and manage packet transmission state
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            prey_latched     <= 32'b0;
            predator_latched <= 32'b0;
            pack_counter     <= 4'd0;
            sending          <= 1'b0;
        end else if (tick) begin
            prey_latched     <= prey;
            predator_latched <= predator;
            pack_counter     <= 4'd0;
            sending          <= 1'b1;  // Start packet on next clock cycle
        end else if (sending) begin
            if (pack_en) begin
                if (pack_counter == 4'd7) begin
                    pack_counter <= 4'd0;
                    sending      <= 1'b0; // All 8 bytes transmitted
                end else begin
                    pack_counter <= pack_counter + 4'd1;
                end
            end
        end
    end

    // Assert valid only when actively sending a packet
    assign valid_in = sending && (pack_counter <= 4'd7);

    // Byte select mux with complete defaults
    always_comb begin
        pack_en = done;
        
        case (pack_counter)
            4'd0:    data_in = prey_latched[31:24];
            4'd1:    data_in = prey_latched[23:16];
            4'd2:    data_in = prey_latched[15:8];
            4'd3:    data_in = prey_latched[7:0];
            4'd4:    data_in = predator_latched[31:24];
            4'd5:    data_in = predator_latched[23:16];
            4'd6:    data_in = predator_latched[15:8];
            4'd7:    data_in = predator_latched[7:0];
            default: data_in = 8'h00;
        endcase
    end
    
endmodule