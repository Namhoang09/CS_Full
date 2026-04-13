module mp_core
    import mylib::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,      
    output logic done,     

    // Streaming từ A_Engine
    input  logic                      A_valid,
    input  logic signed [A_W-1:0]     A_data,
    input  logic [$clog2(M)-1:0]      A_row,
    input  logic [$clog2(NE)-1:0]     A_col_out,
    input  logic                      A_last,

    // Interface với Top FSM
    output logic [1:0]            mp_phase,     
    output logic [$clog2(NE)-1:0] best_col_out,

    // Coef output → Recon_SSE
    output logic signed [COEF_W-1:0] coef [0:NE-1]
);

    // ── Phase encoding cho Top FSM ─────────────────────────────────
    localparam logic [1:0] PHASE_IDLE = 2'd0;
    localparam logic [1:0] PHASE_CALC = 2'd1;  
    localparam logic [1:0] PHASE_UPD  = 2'd2;  

    // ── FSM states ─────────────────────────────────────────────────
    typedef enum logic [3:0] {
        S_IDLE,
        S_INIT_R,      
        S_CALC_INNER,  
        S_FIND_MAX,    
        S_UPD_COEF,    
        S_UPD_R,       
        S_ITER_CHK,    
        S_DONE       
    } state_t;

    state_t state;

    // ── Po BRAM ────────────────────────────────────────────────────
    logic [$clog2(PO_DEPTH)-1:0] po_addr;
    logic signed [PO_W-1:0]      po_dout;

    sync_bram #(
        .DATA_W    (PO_W),
        .DEPTH     (PO_DEPTH),
        .INIT_FILE ("D:/CS_Full/Data/po_vector.txt")
    ) u_po (
        .clk  (clk),
        .we   (1'b0),
        .addr (po_addr),
        .din  ('0),
        .dout (po_dout)
    );

    // ── Data registers ─────────────────────────────────────────────
    logic signed [ACC_W-1:0]  r            [0:M-1];   
    logic signed [ACC_W-1:0]  inner_result [0:NE-1];  
    logic signed [ACC_W-1:0]  inner_acc;              
    logic signed [COEF_W-1:0] alpha;                 
    logic [$clog2(NE)-1:0]    best_col;              
    logic signed [ACC_W-1:0]  best_val;               

    // ── Counters ───────────────────────────────────────────────────
    logic [$clog2(M+1)-1:0]  init_cnt;    // S_INIT_R: 0..M
    logic [$clog2(M+1)-1:0]  init_cnt_d1; // delay 1 cycle bù BRAM latency
    logic [$clog2(NE)-1:0]   col_count;   // số cột đã nhận trong iteration
    logic [$clog2(NE)-1:0]   scan_idx;    // S_FIND_MAX: con trỏ quét
    logic [$clog2(K)-1:0]    iter;        // số vòng lặp đã hoàn tất

    // ── Combinatorial ──────────────────────────────────────────────
    assign po_addr = init_cnt[$clog2(M)-1:0];

    // scan_abs: |inner_result[scan_idx]| dùng cho FIND_MAX
    logic signed [ACC_W-1:0] scan_abs;
    assign scan_abs = inner_result[scan_idx][ACC_W-1] ? -inner_result[scan_idx] : inner_result[scan_idx];

    // mp_phase: Top FSM biết đang ở pha nào
    always_comb begin
        case (state)
            S_CALC_INNER: mp_phase = PHASE_CALC;
            S_UPD_R:      mp_phase = PHASE_UPD;
            default:      mp_phase = PHASE_IDLE;
        endcase
    end

    assign best_col_out = best_col;
    assign done         = (state == S_DONE);

    // ── Pipeline Stage 1: CALC_INNER ──────────────────────────────
    logic signed [ACC_W-1:0]  p1_mul;          // kết quả nhân
    logic                     p1_valid;        // A_valid delay 1
    logic                     p1_row_zero;     // A_row==0 delay 1
    logic                     p1_last;         // A_last delay 1
    logic [$clog2(NE)-1:0]    p1_col;          // A_col_out delay 1

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            p1_mul      <= '0;
            p1_valid    <= 0;
            p1_row_zero <= 0;
            p1_last     <= 0;
            p1_col      <= '0;
        end else begin
            // Latch inputs vào stage 1
            p1_mul      <= ACC_W'(signed'(A_data)) * r[A_row];
            p1_valid    <= A_valid;
            p1_row_zero <= (A_row == 0);
            p1_last     <= A_last;
            p1_col      <= A_col_out;
        end
    end

    // ── Pipeline Stage 1: UPD_R ───────────────────────────────────
    logic signed [ACC_W-1:0] p2_mul;
    logic                    p2_valid;
    logic [$clog2(M)-1:0]    p2_row;
    logic                    p2_last;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            p2_mul   <= '0;
            p2_valid <= 0;
            p2_row   <= '0;
            p2_last  <= 0;
        end else begin
            p2_mul   <= ACC_W'(signed'(alpha)) * ACC_W'(signed'(A_data));
            p2_valid <= A_valid;
            p2_row   <= A_row;
            p2_last  <= A_last;
        end
    end

    // ── Sequential logic ───────────────────────────────────────────
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= S_IDLE;
            init_cnt    <= '0;
            init_cnt_d1 <= '0;
            col_count   <= '0;
            scan_idx    <= '0;
            iter        <= '0;
            inner_acc   <= '0;
            alpha       <= '0;
            best_col    <= '0;
            best_val    <= '0;
            for (int i = 0; i < M;  i++) r[i]            <= '0;
            for (int i = 0; i < NE; i++) inner_result[i] <= '0;
            for (int i = 0; i < NE; i++) coef[i]         <= '0;
        end else begin
            init_cnt_d1 <= init_cnt;

            case (state)
            // ── S_IDLE ────────────────────────────────────────────
            S_IDLE: begin
                if (start) begin
                    state    <= S_INIT_R;
                    init_cnt <= '0;
                    iter     <= '0;
                    for (int i = 0; i < NE; i++) coef[i] <= '0;
                end
            end

            // ── S_INIT_R ──────────────────────────────────────────
            // Nạp Po vào r qua BRAM (latency 1 cycle)
            // Cycle 0: addr=0 gửi, không có data
            // Cycle 1: dout=Po[0], addr=1 → r[0]=sign_ext(Po[0])
            // ...
            // Cycle M: dout=Po[M-1] → r[M-1]=sign_ext(Po[M-1]) → chuyển state
            S_INIT_R: begin
                init_cnt <= init_cnt + 1;

                if (init_cnt >= 1 && init_cnt_d1 < M)
                    r[init_cnt_d1[$clog2(M)-1:0]] <= {{(ACC_W-PO_W){po_dout[PO_W-1]}}, po_dout};

                if (init_cnt == M) begin
                    state     <= S_CALC_INNER;
                    col_count <= '0;
                    init_cnt  <= '0;
                end
            end

            // ── S_CALC_INNER ──────────────────────────────────────
            // Tích lũy corr[col] = Σ_m A[m,col] * r[m]
            // A_row==0: reset inner_acc (bắt đầu cột mới)
            // A_last:   lưu inner_result[col] (dùng inner_acc OLD + tích cuối)
            S_CALC_INNER: begin
                if (p1_valid) begin
                    if (p1_row_zero)
                        inner_acc <= p1_mul; 
                    else
                        inner_acc <= inner_acc + p1_mul;

                    if (p1_last) begin
                        // inner_acc là tổng của row 0..M-2 (OLD, non-blocking)
                        // cộng thêm row M-1 để có tổng đầy đủ
                        inner_result[p1_col] <= inner_acc + p1_mul;
                        col_count <= col_count + 1;

                        if (col_count == NE - 1) begin
                            state    <= S_FIND_MAX;
                            scan_idx <= '0;
                        end
                    end
                end
            end

            // ── S_FIND_MAX ────────────────────────────────────────
            // Cycle 0: khởi tạo best với col 0
            // Cycle 1..NE-1: so sánh col 1..NE-1 với best
            S_FIND_MAX: begin
                if (scan_idx == 0) begin
                    best_col <= '0;
                    best_val <= inner_result[0][ACC_W-1] ? -inner_result[0]
                                                         :  inner_result[0];
                    scan_idx <= 1;
                end else begin
                    if (scan_abs > best_val) begin
                        best_val <= scan_abs;
                        best_col <= scan_idx;
                    end
                    if (scan_idx == NE - 1)
                        state <= S_UPD_COEF;
                    else
                        scan_idx <= scan_idx + 1;
                end
            end

            // ── S_UPD_COEF ────────────────────────────────────────
            // Dùng MUX: Nếu là cột DC (0) thì dịch NORM_SHIFT_DC, ngược lại dịch NORM_SHIFT
            S_UPD_COEF: begin
                if (best_col == 0) begin
                    alpha          <= COEF_W'(inner_result[best_col] >>> NORM_SHIFT_DC);
                    coef[best_col] <= coef[best_col]
                                    + COEF_W'(inner_result[best_col] >>> NORM_SHIFT_DC);
                end else begin
                    alpha          <= COEF_W'(inner_result[best_col] >>> NORM_SHIFT);
                    coef[best_col] <= coef[best_col]
                                    + COEF_W'(inner_result[best_col] >>> NORM_SHIFT);
                end
                state <= S_UPD_R;
            end

            // ── S_UPD_R ───────────────────────────────────────────
            // Nhận replay stream của best_col
            // r[m] -= alpha * A[m, best_col]
            S_UPD_R: begin
                if (p2_valid)
                    r[p2_row] <= r[p2_row] - p2_mul;

                if (p2_last)
                    state <= S_ITER_CHK;
            end

            // ── S_ITER_CHK ────────────────────────────────────────
            S_ITER_CHK: begin
                iter <= iter + 1;
                if (iter == K - 1)
                    state <= S_DONE;
                else begin
                    state     <= S_CALC_INNER;
                    col_count <= '0;
                end
            end

            // ── S_DONE ────────────────────────────────────────────
            // done=1 combinatorial trong 1 cycle này, rồi về IDLE
            S_DONE: state <= S_IDLE;

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule