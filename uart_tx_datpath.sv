module uart_tx_datapath(
    input  logic       clk,
    input  logic       reset,
    input  logic [7:0] data_in,
    input  logic       load_reg,
    input  logic       shift,
    input  logic       clr,
    input  logic       en,
    input  logic [1:0] sel,

    output logic       tx_out,
    output logic       of
);

    logic [7:0] shift_reg;
    logic [2:0] counter;

    // Shift Register
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            shift_reg <= 8'b0;
        end else if (load_reg) begin
            shift_reg <= data_in;
        end else if (shift) begin
            shift_reg <= {1'b0, shift_reg[7:1]}; // Explicit right shift
        end
    end

    // Bit Counter
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 3'b0;
        end else if (clr) begin
            counter <= 3'b0;
        end else if (en) begin
            counter <= counter + 3'b1;
        end
    end

    // Output Mux and Overflow
    always_comb begin
        of = (counter == 3'b111);

        case (sel)
            2'b00: tx_out = 1'b0;         // Start Bit
            2'b01: tx_out = 1'b1;         // Idle / Stop Bit
            2'b10: tx_out = shift_reg[0]; // Data Bits
            default: tx_out = 1'b1;       // Safe default
        endcase
    end

endmodule