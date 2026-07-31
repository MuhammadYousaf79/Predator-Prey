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

    typedef enum logic [1:0] { IDLE, START, DATA_BITS } state;
    state C_state, N_state;

    logic [7:0] latched_data;

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
                if (tx_start) begin
                    tx_active = 1'b1;
                    N_state = START;
                end else begin
                    N_state = IDLE;
                end
            end

            START: begin
                tx_active = 1'b1;
                tx_out = 1'b0;
                if (baud_tick) begin
                    latched_data = data;
                    N_state = DATA_BITS;
                end
            end

            DATA_BITS: begin
                tx_active = 1'b1;
                tx_out = latched_data[bit_idx];
                if (baud_tick) begin
                    incr_bit_idx = 1'b1;
                    N_state = DATA_BITS;

                end
                if (bit_idx == 8) begin
                    tx_out = 1'b1;
                    tx_active = 1'b0;
                    incr_bit_idx = 1'b0;
                    reset_bit_idx = 1'b1;
                    tx_done = 1'b1;
                    N_state = IDLE;
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