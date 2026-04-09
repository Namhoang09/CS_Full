package mylib;

    // ── Kích thước ma trận ─────────────────────────────────────────────────
    parameter int M   = 20;     
    parameter int NE  = 200;    
    parameter int K   = 10;  

    // ── Tham số hệ thống ───────────────────────────────────────────────────
    parameter int NC  = 200000;

    // ── G-Win Buffer ───────────────────────────────────────────────────────
    parameter int GWIN_W   = 2 * NE - 1;   
    parameter int GWIN_GAP = NC - GWIN_W;  

    // ── Độ rộng bit ────────────────────────────────────────────────────────
    parameter int D_W     = 16;  // D_INT: int16 (Q1.14 sau scaling)
    parameter int THETA_W = 32;  // output Theta stream: int32
    parameter int PO_W    = 32;  // Po vector: int32
    parameter int S_W     = 32;  // S_int: int32
    parameter int COEF_W  = 32;  // coef output MP_Core
    parameter int ACC_W   = 64;  // accumulator MP_Core (r, inner_result)
    parameter int TACC_W  = 32;  // accumulator Theta_Engine
    parameter int SACC_W  = 64;  // accumulator srec trong Recon_SSE

    // ── Fixed-point ────────────────────────────────────────────────────────
    parameter int FRAC_D      = 14;  
    parameter int FRAC_S      = 15;  
    parameter int NORM_SHIFT  = 28; 
    parameter int NORM_SHIFT_DC = 36;
    parameter int SSE_SHIFT   = 15; 

    // ── Hằng số depth BRAM ─────────────────────────────────────────────────
    parameter int D_DEPTH  = NE * NE;  
    parameter int PO_DEPTH = M;        
    parameter int S_DEPTH  = NE;    

endpackage