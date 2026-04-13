module top_fsm
    import mylib::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,

    // A_Engine control
    output logic                  gwin_fill_en,
    input  logic                  gwin_done,
    input  logic                  A_busy,
    output logic [$clog2(NE)-1:0] Nd_hyp,
    output logic                  compute_start,
    output logic [$clog2(NE)-1:0] col_req,

    // MP_Core control
    output logic       mp_start,
    input  logic       mp_done,
    input  logic [1:0] mp_phase,
    input  logic [$clog2(NE)-1:0] best_col_out,

    // Recon_SSE control
    output logic        recon_start,
    input  logic        recon_done,
    input  logic [63:0] sse,

    // Output
    output logic [$clog2(NE)-1:0] best_Nd,
    output logic                  best_Nd_valid
);

    // ── Phase encoding ─────────────────────────────────────────────
    localparam logic [1:0] PHASE_IDLE = 2'd0;
    localparam logic [1:0] PHASE_CALC = 2'd1;
    localparam logic [1:0] PHASE_UPD  = 2'd2;

    // ── FSM states ─────────────────────────────────────────────────
    typedef enum logic [3:0] {
        S_IDLE,
        S_GWIN_FILL,
        S_MP_INIT,
        S_SEND_COLS,
        S_WAIT_A_BUSY,  // Thêm state này
        S_WAIT_UPD,
        S_SEND_REPLAY,
        S_WAIT_REPLAY_BUSY, // Thêm state này
        S_ITER_OR_DONE,
        S_RECON_START,
        S_WAIT_RECON,
        S_UPDATE_MIN,
        S_NEXT_ND,
        S_DONE
    } state_t;

    state_t state;

    // ── Registers ─────────────────────────────────────────────────
    logic [$clog2(NE)-1:0] nd_cnt;
    logic [$clog2(NE)-1:0] col_cnt;
    logic [$clog2(NE)-1:0] best_col_lat;
    logic [63:0]           min_sse;

    // ── Sequential ────────────────────────────────────────────────
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= S_IDLE;
            gwin_fill_en  <=  0;
            compute_start <=  0;
            mp_start      <=  0;
            recon_start   <=  0;
            best_Nd_valid <=  0;
            nd_cnt        <= '0;
            col_cnt       <= '0;
            col_req       <= '0;
            Nd_hyp        <= '0;
            best_col_lat  <= '0;
            best_Nd       <= '0;
            min_sse       <= '1;
        end else begin

            // Xóa pulse mỗi cycle
            compute_start <= 0;
            mp_start      <= 0;
            recon_start   <= 0;
            best_Nd_valid <= 0;

            case (state)

            // ── S_IDLE ────────────────────────────────────────────
            S_IDLE: begin
                if (start) begin
                    state        <= S_GWIN_FILL;
                    gwin_fill_en <= 1;
                    nd_cnt       <= '0;
                    min_sse      <= '1;
                end
            end

            // ── S_GWIN_FILL ───────────────────────────────────────
            S_GWIN_FILL: begin
                if (gwin_done) begin
                    gwin_fill_en <= 0;
                    Nd_hyp       <= '0;
                    state        <= S_MP_INIT;
                end
            end

            // ── S_MP_INIT ─────────────────────────────────────────
            // Pulse mp_start, chuẩn bị gửi cột đầu tiên
            S_MP_INIT: begin
                mp_start <= 1;
                col_cnt  <= '0;
                state    <= S_SEND_COLS;
            end

            // ── S_SEND_COLS ───────────────────────────────────────
            S_SEND_COLS: begin
                if (!A_busy) begin
                    col_req       <= col_cnt;
                    compute_start <= 1;
                    state         <= S_WAIT_A_BUSY; // Chuyển sang chờ
                end
            end

            // ── S_WAIT_A_BUSY ─────────────────────────────────
            S_WAIT_A_BUSY: begin
                // Đợi A_engine phản hồi bận rồi mới quyết định tiếp
                if (A_busy) begin
                    if (col_cnt == NE - 1) begin
                        state <= S_WAIT_UPD;
                    end else begin
                        col_cnt <= col_cnt + 1;
                        state   <= S_SEND_COLS;
                    end
                end
            end

            // ── S_WAIT_UPD ────────────────────────────────────────
            // Chờ FIND_MAX + UPD_COEF xong → mp_phase = PHASE_UPD
            S_WAIT_UPD: begin
                if (mp_phase == PHASE_UPD) begin
                    best_col_lat <= best_col_out;
                    state        <= S_SEND_REPLAY;
                end
            end

            // ── S_SEND_REPLAY ─────────────────────────────────────
            S_SEND_REPLAY: begin
                if (!A_busy) begin
                    col_req       <= best_col_lat;
                    compute_start <= 1;
                    state         <= S_WAIT_REPLAY_BUSY; // Chuyển sang chờ
                end
            end

            // ── S_WAIT_REPLAY_BUSY ────────────────────────────────
            S_WAIT_REPLAY_BUSY: begin
                if (A_busy) begin
                    state <= S_ITER_OR_DONE;
                end
            end

            // ── S_ITER_OR_DONE ────────────────────────────────────
            // Chờ A_last (replay xong) rồi kiểm tra mp_done:
            //   mp_done=1 → K iterations xong → sang RECON
            //   mp_done=0 → còn iteration → gửi NE cột tiếp theo
            // Dùng mp_phase để detect: sau UPD_R → ITER_CHK → CALC hoặc DONE
            S_ITER_OR_DONE: begin
                if (mp_done) begin
                    state <= S_RECON_START;
                end else if (mp_phase == PHASE_CALC) begin
                    // mp_core đã sang iteration tiếp theo
                    col_cnt <= '0;
                    state   <= S_SEND_COLS;
                end
            end

            // ── S_RECON_START ─────────────────────────────────────
            S_RECON_START: begin
                recon_start <= 1;
                state       <= S_WAIT_RECON;
            end

            // ── S_WAIT_RECON ──────────────────────────────────────
            S_WAIT_RECON: begin
                if (recon_done) begin
                    state <= S_UPDATE_MIN;
                    $display("[%0t] Tien do: %0d / %0d (%.1f%%) - Hoan thanh kiem tra Nd_hyp = %0d", 
                             $time, 
                             nd_cnt + 1, 
                             NE, 
                             (nd_cnt + 1) * 100.0 / NE,
                             nd_cnt);
                end
            end

            // ── S_UPDATE_MIN ──────────────────────────────────────
            S_UPDATE_MIN: begin
                if (sse < min_sse) begin
                    min_sse <= sse;
                    best_Nd <= nd_cnt;
                end
                state <= S_NEXT_ND;
            end

            // ── S_NEXT_ND ─────────────────────────────────────────
            S_NEXT_ND: begin
                if (nd_cnt == NE - 1) begin
                    state <= S_DONE;
                end else begin
                    nd_cnt <= nd_cnt + 1;
                    Nd_hyp <= nd_cnt + 1;
                    state  <= S_MP_INIT;
                end
            end

            // ── S_DONE ────────────────────────────────────────────
            S_DONE: begin
                best_Nd_valid <= 1;
                state         <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule