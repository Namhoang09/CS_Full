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

    // Psi ROM shared
    logic [$clog2(Psi_DEPTH)-1:0] A_Psi_addr;
    logic [$clog2(Psi_DEPTH)-1:0] recon_Psi_addr;
    logic [$clog2(Psi_DEPTH)-1:0] Psi_addr_mux;
    logic signed [Psi_W-1:0]      Psi_dout;

    // LFSR
    logic g_bit, lfsr_en;

    // A_Engine
    logic                      gwin_fill_en, gwin_done;
    logic                      A_busy;
    logic [$clog2(NE)-1:0]     Nd_hyp;
    logic                      compute_start;
    logic [$clog2(NE)-1:0]     col_req;
    logic                      A_valid;
    logic signed [A_W-1:0]     A_data;
    logic [$clog2(M)-1:0]      A_row;
    logic [$clog2(NE)-1:0]     A_col_out;
    logic                      A_last;

    // MP_Core
    logic                     mp_start, mp_done;
    logic [1:0]               mp_phase;
    logic [$clog2(NE)-1:0]    best_col_out;
    logic signed [COEF_W-1:0] coef [0:NE-1];

    // Recon_SSE
    logic        recon_start, recon_done;
    logic [63:0] sse;

    // ── Psi ROM mux (khai báo xong rồi mới assign) ──────────────────
    assign Psi_addr_mux = A_busy ? A_Psi_addr : recon_Psi_addr;

    // ── Instances ─────────────────────────────────────────────────
    sync_bram #(
        .DATA_W    (Psi_W),
        .DEPTH     (Psi_DEPTH),
        .INIT_FILE ("Data/Psi_matrix.txt")
    ) u_Psi_rom (
        .clk  (clk),
        .we   (1'b0),
        .addr (Psi_addr_mux),
        .din  ('0),
        .dout (Psi_dout)
    );

    lfsr_32 u_lfsr (
        .clk   (clk),
        .rst   (rst),
        .en    (lfsr_en),
        .g_bit (g_bit)
    );

    A_engine u_A (
        .clk           (clk),
        .rst           (rst),
        .g_bit         (g_bit),
        .gwin_fill_en  (gwin_fill_en),
        .gwin_done     (gwin_done),
        .lfsr_en       (lfsr_en),
        .busy          (A_busy),
        .Nd_hyp        (Nd_hyp),
        .compute_start (compute_start),
        .col_req       (col_req),
        .Psi_addr      (A_Psi_addr),
        .Psi_dout      (Psi_dout),
        .A_valid       (A_valid),
        .A_data        (A_data),
        .A_row         (A_row),
        .A_col_out     (A_col_out),
        .A_last        (A_last)
    );

    mp_core u_mp (
        .clk           (clk),
        .rst           (rst),
        .start         (mp_start),
        .done          (mp_done),
        .A_valid       (A_valid),
        .A_data        (A_data),
        .A_row         (A_row),
        .A_col_out     (A_col_out),
        .A_last        (A_last),
        .mp_phase      (mp_phase),
        .best_col_out  (best_col_out),
        .coef          (coef)
    );

    recon_sse u_recon (
        .clk      (clk),
        .rst      (rst),
        .start    (recon_start),
        .coef     (coef),
        .Psi_addr (recon_Psi_addr),
        .Psi_dout (Psi_dout),
        .done     (recon_done),
        .sse      (sse)
    );

    top_fsm u_top_fsm (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .gwin_fill_en  (gwin_fill_en),
        .gwin_done     (gwin_done),
        .A_busy        (A_busy),
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