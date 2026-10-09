module top (
    input  logic clk,
    input  logic reset,
    input  logic rx_in,

    output logic tx_out
);

    parameter CLK_FREQ  = 100_000_000;
    parameter BAUD_RATE = 2_000_000;


    // -------------------------------------------------------------------------
    // 1. 1 ms Hardware Timer (1 kHz tick)
    // -------------------------------------------------------------------------
    localparam ONE_MS_CYCLES = CLK_FREQ / 1000;
    logic [$clog2(ONE_MS_CYCLES)-1:0] ms_timer_cnt;
    logic tick_1ms;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            ms_timer_cnt <= '0;
            tick_1ms     <= 1'b0;
        end else if (ms_timer_cnt == ONE_MS_CYCLES - 1) begin
            ms_timer_cnt <= '0;
            tick_1ms     <= 1'b1;
        end else begin
            ms_timer_cnt <= ms_timer_cnt + 1'b1;
            tick_1ms     <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // 2. UART Receiver: Reassembles Raw 4-Byte Prey (MSB First)
    // -------------------------------------------------------------------------
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       frame_error;

    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_rx_inst (
        .clk(clk),
        .reset(reset),
        .rx_in(rx_in),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .frame_error(frame_error)
    );

    logic [31:0] prey_shift_reg;
    logic [31:0] prey_latched;
    logic [1:0]  rx_byte_cnt;
    logic        new_prey_ready;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            prey_shift_reg <= 32'b0;
            prey_latched   <= 32'b0;
            rx_byte_cnt    <= 2'd0;
            new_prey_ready <= 1'b0;
        end else begin
            if (rx_valid) begin
                prey_shift_reg <= {prey_shift_reg[23:0], rx_data};

                if (rx_byte_cnt == 2'd3) begin
                    rx_byte_cnt    <= 2'd0;
                    prey_latched   <= {prey_shift_reg[23:0], rx_data}; // Complete 32-bit prey
                    new_prey_ready <= 1'b1;
                end else begin
                    rx_byte_cnt    <= rx_byte_cnt + 2'd1;
                end
            end

            // Clear ready flag once the 1ms execution consumes it
            if (tick_1ms) begin
                new_prey_ready <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 3. Predator-Prey Model (Steps on tick_1ms)
    // -------------------------------------------------------------------------
    logic [31:0] predator_out;

    // one-cycle pulse when the 4th prey byte arrives
    wire prey_pulse = rx_valid && (rx_byte_cnt == 2'd3);

    // delay one clock so prey_latched has been loaded
    logic prey_pulse_d;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) prey_pulse_d <= 1'b0;
        else       prey_pulse_d <= prey_pulse;
    end

    logic core_done;
    predator_prey model (
        .clk(clk),
        .reset(reset),
        .tick(tick_1ms),
        .valid_prey(prey_pulse_d),
        .prey(prey_latched),
        .predator(predator_out),
        .done(core_done)
    );

    // -------------------------------------------------------------------------
    // 4. UART Transmitter: Transmits Raw 4-Byte Predator (MSB First)
    // -------------------------------------------------------------------------
    logic [7:0]  tx_data_in;
    logic        tx_valid_in;
    logic        tx_ready_out;
    logic        tx_done;

    uart_tx uart_tx_inst (
        .clk(clk),
        .reset(reset),
        .valid_in(tx_valid_in),
        .ready_out(tx_ready_out),
        .data_in(tx_data_in),
        .tx_out(tx_out),
        .done(tx_done)
    );

    // -------------------------------------------------------------------------
    // 5. TX Sequencer (Sends 4 Raw Bytes each 1 ms)
    // -------------------------------------------------------------------------
    logic [31:0] predator_latched;
    logic [1:0]  tx_byte_cnt;
    logic        tx_active;

    // Trigger transmission 1 clock cycle after tick_1ms to allow model output to settle
    logic start_tx_strobe;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            start_tx_strobe <= 1'b0;
        end else begin
            start_tx_strobe <= core_done;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            predator_latched <= 32'b0;
            tx_byte_cnt      <= 2'd0;
            tx_active        <= 1'b0;
        end else if (start_tx_strobe && !tx_active) begin
            predator_latched <= predator_out;
            tx_byte_cnt      <= 2'd0;
            tx_active        <= 1'b1;
        end else if (tx_active) begin
            if (tx_done) begin
                if (tx_byte_cnt == 2'd3) begin
                    tx_byte_cnt <= 2'd0;
                    tx_active   <= 1'b0; // All 4 bytes sent
                end else begin
                    tx_byte_cnt <= tx_byte_cnt + 2'd1;
                end
            end
        end
    end

    assign tx_valid_in = tx_active;

    // Direct 4-byte multiplexer without delimiters
    always_comb begin
        case (tx_byte_cnt)
            2'd0:    tx_data_in = predator_latched[31:24];
            2'd1:    tx_data_in = predator_latched[23:16];
            2'd2:    tx_data_in = predator_latched[15:8];
            2'd3:    tx_data_in = predator_latched[7:0];
            default: tx_data_in = 8'h00;
        endcase
    end

endmodule