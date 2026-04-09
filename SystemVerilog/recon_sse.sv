module recon_sse
    import mylib::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,                               // pulse từ Top FSM
    input  var logic signed [COEF_W-1:0] coef [0:NE-1], // từ MP_Core

    // D ROM shared (column-major: addr = col*NE + n)
    output logic [$clog2(D_DEPTH)-1:0] d_addr,
    input  logic signed [D_W-1:0]      d_dout,

    output logic        done,  // pulse 1 cycle khi xong
    output logic [63:0] sse    // giữ đến lần start tiếp theo
);

    // ── S ROM nội bộ ──────────────────────────────────────────────
    logic [$clog2(S_DEPTH)-1:0] s_addr;
    logic signed [S_W-1:0]      s_dout;

    sync_bram #(
        .DATA_W    (S_W),
        .DEPTH     (S_DEPTH),
        .INIT_FILE ("D:/CS_Full/Data/s_vector.txt")
    ) u_s_rom (
        .clk  (clk),
        .we   (1'b0),
        .addr (s_addr),
        .din  ('0),
        .dout (s_dout)
    );

    // ── SREC accumulators [NE] × 64 bit ───────────────────────────
    logic signed [SACC_W-1:0] srec_acc [0:NE-1];

    // ── FSM ───────────────────────────────────────────────────────
    typedef enum logic [1:0] {
        S_IDLE, S_RECON, S_SSE, S_DONE
    } state_t;
    state_t state;

    // ── Counters ──────────────────────────────────────────────────
    logic [$clog2(NE)-1:0]   col_j;
    logic [$clog2(NE+1)-1:0] n_cnt;
    logic [$clog2(NE+1)-1:0] n_cnt_d1;
    logic [$clog2(NE+1)-1:0] sse_cnt;
    logic [$clog2(NE+1)-1:0] sse_cnt_d1;

    // ── Khai báo ở module level (không được khai báo trong always) ─
    logic signed [SACC_W-1:0] diff_raw;
    logic signed [SACC_W-1:0] diff;

    // ── Combinatorial ─────────────────────────────────────────────
    assign d_addr = ($clog2(D_DEPTH))'(col_j) * ($clog2(D_DEPTH))'(NE)
                  + ($clog2(D_DEPTH))'(n_cnt);

    assign s_addr = sse_cnt[$clog2(S_DEPTH)-1:0];

    // Tính diff tổ hợp (dùng trong S_SSE)
    assign diff_raw = SACC_W'(signed'(s_dout))
                    - srec_acc[sse_cnt_d1[$clog2(NE)-1:0]];
    assign diff     = diff_raw >>> SSE_SHIFT;

    // ── Pipeline Stage 1: RECON ───────────────────────────────────
    logic signed [SACC_W-1:0]        p3_mul;
    logic                            p3_valid;
    logic [$clog2(NE)-1:0]           p3_idx;    

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            p3_mul   <= '0;
            p3_valid <= 0;
            p3_idx   <= '0;
        end else begin
            p3_mul   <= SACC_W'(signed'(d_dout)) * SACC_W'(signed'(coef[col_j]));
            p3_valid <= (n_cnt >= 1);
            p3_idx   <= n_cnt_d1[$clog2(NE)-1:0];
        end
    end

    // ── Pipeline Stage 1: SSE ─────────────────────────────────────
    logic signed [SACC_W-1:0] p4_diff;
    logic                     p4_valid;

    // ── Pipeline Stage 2: SSE ─────────────────────────────────────
    logic [63:0]              p4_sq;    // diff^2
    logic                     p4_valid2;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            p4_diff   <= '0;
            p4_valid  <= 0;
            p4_sq     <= '0;
            p4_valid2 <= 0;
        end else begin
            // Stage 1: latch diff
            p4_diff   <= diff;
            p4_valid  <= (sse_cnt >= 1);

            // Stage 2: tính bình phương
            p4_sq     <= 64'(p4_diff * p4_diff);
            p4_valid2 <= p4_valid;
        end
    end

    // ── Sequential ────────────────────────────────────────────────
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_IDLE;
            col_j      <= '0;
            n_cnt      <= '0;
            n_cnt_d1   <= '0;
            sse_cnt    <= '0;
            sse_cnt_d1 <= '0;
            sse        <= '0;
            done       <= 0;
            for (int i = 0; i < NE; i++) srec_acc[i] <= '0;
        end else begin
            done       <= 0;
            n_cnt_d1   <= n_cnt;
            sse_cnt_d1 <= sse_cnt;

            case (state)

            // ── S_IDLE ────────────────────────────────────────────
            S_IDLE: begin
                if (start) begin
                    state <= S_RECON;
                    col_j <= '0;
                    n_cnt <= '0;
                    sse   <= '0;
                    for (int i = 0; i < NE; i++) srec_acc[i] <= '0;
                end
            end

            // ── S_RECON ───────────────────────────────────────────
            // Cycle 0: n_cnt=0, gửi addr → BRAM
            // Cycle 1: d_dout=D[0,col_j], n_cnt_d1=0 → accumulate
            // Cycle NE: accumulate lần cuối → sang cột tiếp hoặc S_SSE
            S_RECON: begin
                n_cnt <= n_cnt + 1;

                if (p3_valid)
                    srec_acc[p3_idx] <= srec_acc[p3_idx] + p3_mul;

                if (n_cnt == NE) begin
                    n_cnt <= '0;
                    if (col_j == NE - 1) begin
                        state   <= S_SSE;
                        sse_cnt <= '0;
                    end else
                        col_j <= col_j + 1;
                end
            end

            // ── S_SSE ─────────────────────────────────────────────
            // Cycle 0: sse_cnt=0, gửi addr → S ROM
            // Cycle 1: s_dout=S_int[0], sse_cnt_d1=0 → tính diff, cộng sse
            // Cycle NE: xong → S_DONE
            S_SSE: begin
                sse_cnt <= sse_cnt + 1;

                if (p4_valid2)
                    sse <= sse + p4_sq;

                if (sse_cnt == NE + 2)
                    state <= S_DONE;
            end

            // ── S_DONE ────────────────────────────────────────────
            S_DONE: begin
                done  <= 1;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule