module cs_full_top
    import mylib::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,

    output logic [$clog2(NE)-1:0] best_Nd,
    output logic                  best_Nd_valid
);

    // ── Khai báo tất cả signals ───────────────────────────────────

    // D ROM shared
    logic [$clog2(D_DEPTH)-1:0] theta_d_addr;
    logic [$clog2(D_DEPTH)-1:0] recon_d_addr;
    logic [$clog2(D_DEPTH)-1:0] d_addr_mux;
    logic signed [D_W-1:0]      d_dout;

    // LFSR
    logic g_bit, lfsr_en;

    // Theta_Engine
    logic                      gwin_fill_en, gwin_done;
    logic                      theta_busy;
    logic [$clog2(NE)-1:0]     Nd_hyp;
    logic                      compute_start;
    logic [$clog2(NE)-1:0]     col_req;
    logic                      theta_valid;
    logic signed [THETA_W-1:0] theta_data;
    logic [$clog2(M)-1:0]      theta_row;
    logic [$clog2(NE)-1:0]     theta_col_out;
    logic                      theta_last;

    // MP_Core
    logic                     mp_start, mp_done;
    logic [1:0]               mp_phase;
    logic [$clog2(NE)-1:0]    best_col_out;
    logic signed [COEF_W-1:0] coef [0:NE-1];

    // Recon_SSE
    logic        recon_start, recon_done;
    logic [63:0] sse;

    // ── D ROM mux (khai báo xong rồi mới assign) ──────────────────
    assign d_addr_mux = theta_busy ? theta_d_addr : recon_d_addr;

    // ── Instances ─────────────────────────────────────────────────
    sync_bram #(
        .DATA_W    (D_W),
        .DEPTH     (D_DEPTH),
        .INIT_FILE ("D:/CS_Full/Data/d_matrix.txt")
    ) u_d_rom (
        .clk  (clk),
        .we   (1'b0),
        .addr (d_addr_mux),
        .din  ('0),
        .dout (d_dout)
    );

    lfsr_32 u_lfsr (
        .clk   (clk),
        .rst   (rst),
        .en    (lfsr_en),
        .g_bit (g_bit)
    );

    theta_engine u_theta (
        .clk           (clk),
        .rst           (rst),
        .g_bit         (g_bit),
        .gwin_fill_en  (gwin_fill_en),
        .gwin_done     (gwin_done),
        .lfsr_en       (lfsr_en),
        .busy          (theta_busy),
        .Nd_hyp        (Nd_hyp),
        .compute_start (compute_start),
        .col_req       (col_req),
        .d_addr        (theta_d_addr),
        .d_dout        (d_dout),
        .theta_valid   (theta_valid),
        .theta_data    (theta_data),
        .theta_row     (theta_row),
        .theta_col_out (theta_col_out),
        .theta_last    (theta_last)
    );

    mp_core u_mp (
        .clk           (clk),
        .rst           (rst),
        .start         (mp_start),
        .done          (mp_done),
        .theta_valid   (theta_valid),
        .theta_data    (theta_data),
        .theta_row     (theta_row),
        .theta_col_out (theta_col_out),
        .theta_last    (theta_last),
        .mp_phase      (mp_phase),
        .best_col_out  (best_col_out),
        .coef          (coef)
    );

    recon_sse u_recon (
        .clk    (clk),
        .rst    (rst),
        .start  (recon_start),
        .coef   (coef),
        .d_addr (recon_d_addr),
        .d_dout (d_dout),
        .done   (recon_done),
        .sse    (sse)
    );

    top_fsm u_top_fsm (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .gwin_fill_en  (gwin_fill_en),
        .gwin_done     (gwin_done),
        .theta_busy    (theta_busy),
        .Nd_hyp        (Nd_hyp),
        .compute_start (compute_start),
        .col_req       (col_req),
        .mp_start      (mp_start),
        .mp_done       (mp_done),
        .mp_phase      (mp_phase),
        .best_col_out  (best_col_out),
        .recon_start   (recon_start),
        .recon_done    (recon_done),
        .sse           (sse),
        .best_Nd       (best_Nd),
        .best_Nd_valid (best_Nd_valid)
    );

endmodule