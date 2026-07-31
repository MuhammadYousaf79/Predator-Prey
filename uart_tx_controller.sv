module uart_tx_controller (
    input  logic       clk,
    input  logic       reset,
    input  logic       valid_in,
    input  logic       transfer, // acts as baud_tick

    input  logic       of,
    output logic [1:0] sel,
    output logic       en,
    output logic       clr,
    output logic       load_reg,
    output logic       shift,
    output logic       done
);

    typedef enum logic [2:0] { IDLE, START, TX_DATA, STOP } state_t;
    state_t C_state, N_state;

    // State Register
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            C_state <= IDLE;
        end else begin
            C_state <= N_state;
        end
    end

    // Next State and Output Logic
    always_comb begin
        // 1. DEFAULT ASSIGNMENTS (Prevents Latches)
        N_state  = C_state;
        sel      = 2'b01; // Default tx_out = 1 (Idle)
        en       = 1'b0;
        clr      = 1'b0;
        load_reg = 1'b0;
        shift    = 1'b0;
        done     = 1'b0;

        // 2. FSM LOGIC
        case (C_state)
            
            IDLE: begin
                if (valid_in) begin
                    load_reg = 1'b1;  // Grab the data immediately
                    clr      = 1'b1;  // Clear the bit counter
                    N_state  = START; 
                end
            end

            START: begin
                sel = 2'b00; // Drive tx_out = 0
                // Hold the start bit until the next baud tick
                if (transfer) begin
                    N_state = TX_DATA;
                end
            end

            TX_DATA: begin
                sel = 2'b10; // Drive tx_out = shift_reg[0]
                
                if (transfer) begin
                    if (of) begin
                        N_state = STOP; // Sent 8 bits, go to stop bit
                    end else begin
                        shift = 1'b1;   // Shift to next bit
                        en    = 1'b1;   // Increment counter
                    end
                end
            end

            STOP: begin
                sel = 2'b01; // Drive tx_out = 1
                
                // Hold the stop bit until the next baud tick
                if (transfer) begin
                    done    = 1'b1;
                    N_state = IDLE;
                end
            end

            default: N_state = IDLE;
        endcase
    end

endmodule