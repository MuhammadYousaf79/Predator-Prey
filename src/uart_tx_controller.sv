module uart_tx_controller (
    input  logic       clk,
    input  logic       reset,
    input  logic       valid_in,
    input  logic       transfer,    // 1-clock-cycle pulse at baud rate

    input  logic       of,          // 1 when counter == 7
    output logic [1:0] sel,
    output logic       en,
    output logic       clr,
    output logic       load_reg,
    output logic       shift,
    output logic       ready_out,
    output logic       done,
    output logic       baud_rst     // Synchronizes/zeros baud generator
);

    typedef enum logic [2:0] { 
        IDLE, 
        LOAD, 
        START, 
        TX_DATA, 
        STOP 
    } state_t;

    state_t C_state, N_state;

    // State Register
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            C_state <= IDLE;
        end else begin
            C_state <= N_state;
        end
    end

    // Next State and Combinational Output Logic
    always_comb begin
        // Safe defaults
        N_state   = C_state;
        sel       = 2'b01;  // tx_out = 1'b1 (Idle/Stop line high)
        en        = 1'b0;
        clr       = 1'b0;
        load_reg  = 1'b0;
        shift     = 1'b0;
        done      = 1'b0;
        ready_out = 1'b0;
        baud_rst  = 1'b0;

        case (C_state)
            IDLE: begin
                ready_out = 1'b1;
                baud_rst  = 1'b1; // Keep baud timer cleared until work starts
                
                if (valid_in) begin
                    load_reg = 1'b1; // Latch data_in cleanly
                    clr      = 1'b1; // Clear bit counter
                    N_state  = START;
                end
            end

            START: begin
                sel = 2'b00; // tx_out = 0 (Start bit)
                
                // Hold Start bit for exactly one full baud period
                if (transfer) begin
                    N_state = TX_DATA;
                end
            end

            TX_DATA: begin
                sel = 2'b10; // tx_out = shift_reg[0]

                if (transfer) begin
                    if (of) begin
                        N_state = STOP; // Finished 8th bit
                    end else begin
                        shift   = 1'b1; // Shift to next bit
                        en      = 1'b1; // Increment bit counter
                    end
                end
            end

            STOP: begin
                sel = 2'b01; // tx_out = 1 (Stop bit)

                // Hold stop bit for a full baud period before finishing
                if (transfer) begin
                    done    = 1'b1;  // Signal packet manager that byte is fully sent
                    N_state = IDLE;
                end
            end

            default: N_state = IDLE;
        endcase
    end

endmodule