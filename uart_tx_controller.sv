module uart_tx_controller (
    input logic         clk,
    input logic         reset,
    input logic         valid_in,
    input logic         transfer,
    input logic         of,

    output logic  [1:0] sel,
    output logic        er,
    output logic        en,
    output logic        clr,
    output logic        load_reg,
    output logic        shift,
    output logic        done

);


    typedef enum logic [1:0] { IDLE, LOAD_DATA, TRANSFER } state;
    state C_state, N_state;


    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            C_state <= IDLE;
        end else begin
            C_state <= N_state;
        end
    end

    always_comb begin
        case (C_state)
            
            IDLE: begin
                if (!valid_in) begin
                    N_state = IDLE;
                    sel = 2'b01;
                    clr = 1'b1;
                    en = 1'b0;
                    er = 1'b0;
                    shift = 1'b0;
                    load_reg = 1'b0;
                    done = 1'b0;
                end else if (valid_in)begin
                    er = 1'b1;
                    N_state = LOAD_DATA;
                end
            end

            LOAD_DATA: begin
                if (!transfer) begin
                    N_state = LOAD_DATA;
                end else if (transfer) begin
                    load_reg = 1'b1;
                    sel = 2'b00;
                    N_state = TRANSFER;
                end
            end

            TRANSFER: begin
                if (transfer) begin
                    sel = 2'b10;
                end
                if (!of) begin
                    N_state = TRANSFER;
                    shift = transfer;
                    en = transfer;
                end else if (of) begin
                    sel = 2'b10;
                    done = 1'b1;
                    N_state = IDLE;
                end
            end

        endcase
    end


    
endmodule