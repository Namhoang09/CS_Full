module theta_engine
    import mylib::*;
(
    input  logic clk,
    input  logic rst,

    // Giai đoạn INIT
    input  logic g_bit,
    input  logic gwin_fill_en,
    output logic gwin_done,
    output logic lfsr_en,  
    output logic busy,      // = 1 khi đang ACCUM hoặc STREAM

    // Giai đoạn COMPUTE
    input  logic [$clog2(NE)-1:0] Nd_hyp,
    input  logic                  compute_start,
    input  logic [$clog2(NE)-1:0] col_req,

    // D ROM (external, column-major: addr = col*NE + n)
    output logic [$clog2(D_DEPTH)-1:0] d_addr,
    input  logic signed [D_W-1:0]      d_dout,

    // Streaming output → MP_Core
    output logic                      theta_valid,
    output logic signed [THETA_W-1:0] theta_data,
    output logic [$clog2(M)-1:0]      theta_row,
    output logic [$clog2(NE)-1:0]     theta_col_out,
    output logic                      theta_last
);

    // G-Win Buffer [M][GWIN_W] ≈ 1 KB
    logic [GWIN_W-1:0] g_win [0:M-1];

    // M accumulators
    logic signed [TACC_W-1:0] acc [0:M-1];

    // FSM
    typedef enum logic [2:0] {
        S_IDLE, S_CAP, S_SKIP, S_ACCUM, S_STREAM
    } state_t;
    state_t state;

    // Counters fill
    logic [$clog2(M)-1:0]         m_fill;
    logic [$clog2(GWIN_W+1)-1:0]  cap_cnt;
    logic [17:0]                  skip_cnt;

    // Counters compute
    logic [$clog2(NE+1)-1:0] n_cnt;
    logic [$clog2(NE+1)-1:0] n_cnt_d1;
    logic [$clog2(M)-1:0]    m_stream;
    logic [$clog2(NE)-1:0]   col_lat;

    // Combinatorial
    assign lfsr_en = (state == S_CAP) || (state == S_SKIP);
    assign busy    = (state == S_ACCUM) || (state == S_STREAM);

    // D ROM address (column-major)
    assign d_addr = ($clog2(D_DEPTH))'(col_lat) * ($clog2(D_DEPTH))'(NE)
                  + ($clog2(D_DEPTH))'(n_cnt);

    // G-Win index
    logic [$clog2(GWIN_W)-1:0] g_idx;
    assign g_idx = ($clog2(GWIN_W))'(Nd_hyp) + ($clog2(GWIN_W))'(n_cnt_d1);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= S_IDLE;
            gwin_done     <= 0;
            m_fill        <= '0;
            cap_cnt       <= '0;
            skip_cnt      <= '0;
            n_cnt         <= '0;
            n_cnt_d1      <= '0;
            m_stream      <= '0;
            col_lat       <= '0;
            theta_valid   <= 0;
            theta_last    <= 0;
            theta_data    <= '0;
            theta_row     <= '0;
            theta_col_out <= '0;
            for (int i = 0; i < M;  i++) g_win[i] <= '0;
            for (int i = 0; i < M;  i++) acc[i]   <= '0;
        end else begin
            theta_valid <= 0;
            theta_last  <= 0;
            n_cnt_d1    <= n_cnt;

            case (state)

            S_IDLE: begin
                if (!gwin_done && gwin_fill_en) begin
                    state   <= S_CAP;
                    m_fill  <= '0;
                    cap_cnt <= '0;
                end else if (gwin_done && compute_start) begin
                    state   <= S_ACCUM;
                    col_lat <= col_req;
                    n_cnt   <= '0;
                    for (int i = 0; i < M; i++) acc[i] <= '0;
                end
            end

            S_CAP: begin
                g_win[m_fill][cap_cnt[$clog2(GWIN_W)-1:0]] <= g_bit;
                if (cap_cnt == GWIN_W - 1) begin
                    cap_cnt <= '0;
                    if (m_fill == M - 1) begin
                        gwin_done <= 1;
                        state     <= S_IDLE;
                    end else begin
                        skip_cnt <= '0;
                        state    <= S_SKIP;
                    end
                end else
                    cap_cnt <= cap_cnt + 1;
            end

            S_SKIP: begin
                if (skip_cnt == GWIN_GAP - 1) begin
                    m_fill   <= m_fill + 1;
                    cap_cnt  <= '0;
                    state    <= S_CAP;
                end else
                    skip_cnt <= skip_cnt + 1;
            end

            S_ACCUM: begin
                n_cnt <= n_cnt + 1;
                if (n_cnt >= 1) begin
                    for (int m = 0; m < M; m++) begin
                        if (g_win[m][g_idx])
                            acc[m] <= acc[m] + TACC_W'(signed'(d_dout));
                    end
                end
                if (n_cnt == NE) begin
                    state    <= S_STREAM;
                    m_stream <= '0;
                    n_cnt    <= '0;
                end
            end

            S_STREAM: begin
                theta_valid   <= 1;
                theta_data    <= THETA_W'(signed'(acc[m_stream]));
                theta_row     <= m_stream;
                theta_col_out <= col_lat;
                if (m_stream == M - 1) begin
                    theta_last <= 1;
                    state      <= S_IDLE;
                end else
                    m_stream <= m_stream + 1;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule