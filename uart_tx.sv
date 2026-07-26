module uart_tx(
    input logic clk,
    input logic reset,

    input logic tx_start,
    input logic baud_tick,
    input logic [7:0] data,

    output logic tx_active,
    output logic tx_out,
    output logic tx_done

);

    typedef enum logic { IDLE, DATA_BITS } state;
    state C_state, N_state;

    logic [3:0] bit_idx;
    logic incr_bit_idx;
    logic reset_bit_idx;

    always_ff @(posedge clk or posedge reset) begin
        if (reset || reset_bit_idx) begin
            bit_idx <= 4'b0;
        end else if (incr_bit_idx) begin
            bit_idx <= bit_idx + 1;
        end
    end

    always_comb begin

        N_state = C_state;
        tx_active = 1'b0;
        tx_out = 1'b1;
        tx_done = 1'b0;
        incr_bit_idx = 1'b0;
        reset_bit_idx = 1'b0;

        case (C_state)

            IDLE: begin
                if (tx_start && baud_tick) begin
                    tx_active = 1'b1;
                    tx_out = 1'b0;
                    N_state = DATA_BITS;
                end else begin
                    N_state = IDLE;
                end
            end

            DATA_BITS: begin
                if (baud_tick) begin
                    tx_out = data[bit_idx];
                    tx_active = 1'b1;
                    incr_bit_idx = 1'b1;
                    N_state = DATA_BITS;

                    if (bit_idx == 8) begin
                        tx_out = 1'b1;
                        tx_active = 1'b0;
                        incr_bit_idx = 1'b0;
                        reset_bit_idx = 1'b1;
                        tx_done = 1'b1;
                        N_state = IDLE;
                    end
                end
            end
        
        endcase

    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            C_state <= IDLE;
        end else begin
            C_state <= N_state;
        end
    end

    
endmodule