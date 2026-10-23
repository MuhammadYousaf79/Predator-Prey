// =============================================================================
// rtds_gen_top.sv - Real-time co-simulation of generator 1 (Nexys A7-100T)
//
//   CPU (network + other machines) <== UART 2 Mbaud ==> FPGA (generator 1)
//
// Every 1 ms tick the HLS core gen_step computes X(k+1) = X(k) + h f(X, V, th)
// and the result is sent to the CPU. All words are signed Q8.24, big-endian.
//
// CPU -> FPGA frames
//   INIT : 0xA5, delta, omega, Eq', Ed', Efd, Pm, x7, x8, x9, Vref, Pref (45 B)
//          Loads the state and set-points. Send once before stepping (or any
//          time to restart).
//   STEP : 0x5A, V, theta                                               (9 B)
//          Terminal-bus voltage magnitude / angle for the next step.
//
// FPGA -> CPU frame (after every step, 45 B = 225 us at 2 Mbaud)
//   0xC3, delta, omega, Eq', Ed', Efd, Pm, x7, x8, x9   (= X(k+1))
//         Pg, Qg                                        (at step k)
//
// Stepping
//   FREE_RUN = 0 : lock-step. A step runs on the 1 ms tick only once a fresh
//                  STEP frame has arrived (same scheme as the predator-prey
//                  design), so a slow CPU can never be overrun.
//   FREE_RUN = 1 : hard real time. A step runs on every 1 ms tick; if no new
//                  STEP frame arrived the last V / theta are held.
//
// LEDs : [0] initialised  [1] toggles on every step done
//        [2] UART frame error seen  [3] 1 ms deadline missed (sticky)
// done_o : step-done pulse (stretched to 1 us) on PMOD JA1 for a scope
// =============================================================================
module rtds_gen_top #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 2_000_000,
    parameter int FREE_RUN  = 0
)(
    input  logic       clk,
    input  logic       rst_n,         // CPU_RESETN, active low
    input  logic       uart_rx_i,
    output logic       uart_tx_o,
    output logic       done_o,
    output logic [3:0] led_o
);

    localparam logic [7:0] HDR_INIT = 8'hA5;
    localparam logic [7:0] HDR_STEP = 8'h5A;
    localparam logic [7:0] HDR_OUT  = 8'hC3;

    localparam int N_INIT_W = 11;     // 9 states + Vref + Pref
    localparam int N_STEP_W = 2;      // V + theta
    localparam int N_OUT_W  = 11;     // 9 states + Pg + Qg

    // -------------------------------------------------------------------------
    // Reset synchroniser (async assert, sync release -> active-high reset)
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) logic [1:0] rst_sync;
    logic reset;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rst_sync <= 2'b11;
        else        rst_sync <= {rst_sync[0], 1'b0};
    end
    assign reset = rst_sync[1];

    // -------------------------------------------------------------------------
    // 1 ms tick
    // -------------------------------------------------------------------------
    localparam int ONE_MS_CYCLES = CLK_FREQ / 1000;
    logic [$clog2(ONE_MS_CYCLES)-1:0] ms_cnt;
    logic tick_1ms;

    always_ff @(posedge clk) begin
        if (reset) begin
            ms_cnt   <= '0;
            tick_1ms <= 1'b0;
        end else if (ms_cnt == ONE_MS_CYCLES - 1) begin
            ms_cnt   <= '0;
            tick_1ms <= 1'b1;
        end else begin
            ms_cnt   <= ms_cnt + 1'b1;
            tick_1ms <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // UART receiver + frame parser
    // -------------------------------------------------------------------------
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_ferr;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .reset(reset), .rx_in(uart_rx_i),
        .rx_data(rx_data), .rx_valid(rx_valid), .frame_error(rx_ferr)
    );

    // A frame is dropped if the line stays silent for 20 byte times mid-frame,
    // so the parser always re-synchronises on the next header.
    localparam int RX_TIMEOUT = 20 * 10 * (CLK_FREQ / BAUD_RATE);

    typedef enum logic [1:0] { P_HDR, P_INIT, P_STEP } parse_t;
    parse_t pstate;

    logic [31:0] rx_word;
    logic [1:0]  rx_byte_idx;
    logic [3:0]  rx_word_idx;
    logic [$clog2(RX_TIMEOUT)-1:0] rx_idle_cnt;

    logic [31:0] init_buf [N_INIT_W];
    logic        init_pending;        // complete INIT frame waiting
    logic        init_taken;          // main FSM consumed it

    logic [31:0] v_buf, th_buf;
    logic        step_pending;        // complete STEP frame waiting
    logic        step_taken;

    wire  [31:0] rx_word_next = {rx_word[23:0], rx_data};
    wire         rx_word_done = rx_valid && (rx_byte_idx == 2'd3);

    always_ff @(posedge clk) begin
        if (reset) begin
            pstate       <= P_HDR;
            rx_byte_idx  <= '0;
            rx_word_idx  <= '0;
            rx_idle_cnt  <= '0;
            init_pending <= 1'b0;
            step_pending <= 1'b0;
        end else begin
            if (init_taken) init_pending <= 1'b0;
            if (step_taken) step_pending <= 1'b0;

            // inter-byte timeout while inside a frame
            if (pstate == P_HDR || rx_valid)
                rx_idle_cnt <= '0;
            else if (rx_idle_cnt == RX_TIMEOUT - 1)
                pstate <= P_HDR;
            else
                rx_idle_cnt <= rx_idle_cnt + 1'b1;

            if (rx_valid) begin
                case (pstate)
                    P_HDR: begin
                        rx_byte_idx <= '0;
                        rx_word_idx <= '0;
                        if (rx_data == HDR_INIT) pstate <= P_INIT;
                        if (rx_data == HDR_STEP) pstate <= P_STEP;
                    end

                    P_INIT: begin
                        rx_byte_idx <= rx_byte_idx + 1'b1;
                        if (rx_word_done) begin
                            rx_word_idx <= rx_word_idx + 1'b1;
                            if (rx_word_idx == N_INIT_W - 1) begin
                                init_pending <= 1'b1;
                                pstate       <= P_HDR;
                            end
                        end
                    end

                    P_STEP: begin
                        rx_byte_idx <= rx_byte_idx + 1'b1;
                        if (rx_word_done) begin
                            rx_word_idx <= rx_word_idx + 1'b1;
                            if (rx_word_idx != 0) begin
                                step_pending <= 1'b1;
                                pstate       <= P_HDR;
                            end
                        end
                    end

                    default: pstate <= P_HDR;
                endcase
            end
        end
    end

    // Payload registers: no reset (keeps the reset net small for timing)
    always_ff @(posedge clk) begin
        if (rx_valid && pstate != P_HDR)
            rx_word <= rx_word_next;
        if (rx_word_done && pstate == P_INIT)
            init_buf[rx_word_idx] <= rx_word_next;
        if (rx_word_done && pstate == P_STEP) begin
            if (rx_word_idx == 0) v_buf  <= rx_word_next;
            else                  th_buf <= rx_word_next;
        end
    end

    // -------------------------------------------------------------------------
    // HLS generator core (gen_step, ap_ctrl_hs, pipelined II = 1)
    // -------------------------------------------------------------------------
    // State X(k) and set-points: change only in M_IDLE, so they are stable
    // while the core is computing.
    logic [31:0] x_reg [9];
    logic [31:0] vref_reg, pref_reg;
    logic [31:0] v_core, th_core;     // V / theta snapshot for this step

    logic        ap_start, ap_done, ap_idle, ap_ready;
    logic [31:0] xn   [9];
    logic        xn_vld [9];
    logic [31:0] pg_o, qg_o;
    logic        pg_vld, qg_vld;

    gen_step u_gen (
        .ap_clk   (clk),
        .ap_rst   (reset),
        .ap_start (ap_start),
        .ap_done  (ap_done),
        .ap_idle  (ap_idle),
        .ap_ready (ap_ready),
        .v_mag_V  (v_core),
        .v_ang_V  (th_core),
        .v_ref_V  (vref_reg),
        .p_ref_V  (pref_reg),
        .delta_V  (x_reg[0]),
        .omega_V  (x_reg[1]),
        .eq_p_V   (x_reg[2]),
        .ed_p_V   (x_reg[3]),
        .efd_V    (x_reg[4]),
        .pm_V     (x_reg[5]),
        .x7_V     (x_reg[6]),
        .x8_V     (x_reg[7]),
        .x9_V     (x_reg[8]),
        .delta_n_V(xn[0]), .delta_n_V_ap_vld(xn_vld[0]),
        .omega_n_V(xn[1]), .omega_n_V_ap_vld(xn_vld[1]),
        .eq_p_n_V (xn[2]), .eq_p_n_V_ap_vld (xn_vld[2]),
        .ed_p_n_V (xn[3]), .ed_p_n_V_ap_vld (xn_vld[3]),
        .efd_n_V  (xn[4]), .efd_n_V_ap_vld  (xn_vld[4]),
        .pm_n_V   (xn[5]), .pm_n_V_ap_vld   (xn_vld[5]),
        .x7_n_V   (xn[6]), .x7_n_V_ap_vld   (xn_vld[6]),
        .x8_n_V   (xn[7]), .x8_n_V_ap_vld   (xn_vld[7]),
        .x9_n_V   (xn[8]), .x9_n_V_ap_vld   (xn_vld[8]),
        .pg_V     (pg_o),  .pg_V_ap_vld     (pg_vld),
        .qg_V     (qg_o),  .qg_V_ap_vld     (qg_vld)
    );

    // Capture every output on its own ap_vld (they may fire in different
    // pipeline stages); all have fired by the time ap_done is seen.
    logic [31:0] out_lat [N_OUT_W];

    always_ff @(posedge clk) begin
        for (int i = 0; i < 9; i++)
            if (xn_vld[i]) out_lat[i] <= xn[i];
        if (pg_vld) out_lat[9]  <= pg_o;
        if (qg_vld) out_lat[10] <= qg_o;
    end

    // -------------------------------------------------------------------------
    // Step sequencer
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] { M_IDLE, M_RUN, M_WAIT, M_COMMIT } main_t;
    main_t mstate;

    logic initialised;
    logic step_done;                  // 1-cycle "done" pulse per step
    logic tx_busy;
    logic deadline_miss;

    // Request a step: lock-step needs fresh data, free-run uses held data
    wire step_req = initialised && (FREE_RUN ? 1'b1 : step_pending);

    assign ap_start = (mstate == M_RUN);

    wire load_init  = (mstate == M_IDLE) && init_pending && !init_taken;
    wire start_step = (mstate == M_IDLE) && !load_init && tick_1ms &&
                      step_req && !tx_busy;

    // State / input registers: no reset, written only from M_IDLE / M_COMMIT
    always_ff @(posedge clk) begin
        if (load_init) begin
            for (int i = 0; i < 9; i++) x_reg[i] <= init_buf[i];
            vref_reg <= init_buf[9];
            pref_reg <= init_buf[10];
        end
        if (start_step) begin
            v_core  <= v_buf;
            th_core <= th_buf;
        end
        if (mstate == M_COMMIT)
            for (int i = 0; i < 9; i++) x_reg[i] <= out_lat[i];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            mstate        <= M_IDLE;
            initialised   <= 1'b0;
            init_taken    <= 1'b0;
            step_taken    <= 1'b0;
            step_done     <= 1'b0;
            deadline_miss <= 1'b0;
        end else begin
            init_taken <= 1'b0;
            step_taken <= 1'b0;
            step_done  <= 1'b0;

            case (mstate)
                M_IDLE: begin
                    if (load_init) begin
                        initialised <= 1'b1;
                        init_taken  <= 1'b1;
                    end else if (tick_1ms && step_req) begin
                        if (tx_busy) begin
                            // previous result still on the wire: 1 ms missed
                            deadline_miss <= 1'b1;
                        end else begin
                            step_taken <= step_pending;
                            mstate     <= M_RUN;
                        end
                    end
                end

                // ap_start high until the pipeline accepts the iteration
                M_RUN:    if (ap_ready) mstate <= M_WAIT;

                M_WAIT:   if (ap_done)  mstate <= M_COMMIT;

                // out_lat holds X(k+1), Pg, Qg here
                M_COMMIT: begin
                    step_done <= 1'b1;
                    mstate    <= M_IDLE;
                end

                default: mstate <= M_IDLE;
            endcase

            // a tick that arrives while still computing is also a miss
            if (tick_1ms && mstate != M_IDLE) deadline_miss <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // UART transmitter + result frame sequencer
    // -------------------------------------------------------------------------
    localparam int TX_BYTES = 1 + 4 * N_OUT_W;

    logic        tx_start, tx_ready;
    logic [7:0]  tx_byte;
    logic [32*N_OUT_W-1:0] tx_shift;
    logic [$clog2(TX_BYTES+1)-1:0] tx_left;
    logic        tx_hdr;

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
        .clk(clk), .reset(reset), .start(tx_start), .data_in(tx_byte),
        .tx_out(uart_tx_o), .ready(tx_ready)
    );

    assign tx_busy = (tx_left != 0);
    wire   tx_send = !step_done && (tx_left != 0) && tx_ready && !tx_start;

    always_ff @(posedge clk) begin
        if (reset) begin
            tx_left  <= '0;
            tx_hdr   <= 1'b0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            if (step_done) begin
                tx_left <= TX_BYTES;
                tx_hdr  <= 1'b1;
            end else if (tx_send) begin
                tx_start <= 1'b1;
                tx_left  <= tx_left - 1'b1;
                tx_hdr   <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (step_done) begin
            for (int i = 0; i < N_OUT_W; i++)
                tx_shift[32*(N_OUT_W-1-i) +: 32] <= out_lat[i];
        end else if (tx_send) begin
            if (tx_hdr) begin
                tx_byte <= HDR_OUT;
            end else begin
                tx_byte  <= tx_shift[32*N_OUT_W-1 -: 8];
                tx_shift <= {tx_shift[32*N_OUT_W-9:0], 8'h00};
            end
        end
    end

    // -------------------------------------------------------------------------
    // Status outputs
    // -------------------------------------------------------------------------
    logic       done_toggle, ferr_seen;
    logic [6:0] done_stretch;

    always_ff @(posedge clk) begin
        if (reset) begin
            done_toggle  <= 1'b0;
            ferr_seen    <= 1'b0;
            done_stretch <= '0;
            done_o       <= 1'b0;
        end else begin
            if (step_done) done_toggle <= ~done_toggle;
            if (rx_ferr)   ferr_seen   <= 1'b1;
            if (step_done)              done_stretch <= 7'd99;
            else if (done_stretch != 0) done_stretch <= done_stretch - 1'b1;
            done_o <= step_done || (done_stretch != 0);
        end
    end

    assign led_o = {deadline_miss, ferr_seen, done_toggle, initialised};

endmodule
