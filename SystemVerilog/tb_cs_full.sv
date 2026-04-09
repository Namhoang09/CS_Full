`timescale 1ns/1ps

module tb_cs_full;
    import mylib::*;

    logic clk, rst, start;
    logic [$clog2(NE)-1:0] best_Nd;
    logic                  best_Nd_valid;

    // ── DUT ───────────────────────────────────────────────────────
    cs_full_top u_dut (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .best_Nd      (best_Nd),
        .best_Nd_valid(best_Nd_valid)
    );

    // ── Clock 100 MHz ─────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk; 

    // ── Stimulus ──────────────────────────────────────────────────
    initial begin
        rst   = 1;
        start = 0;
        repeat(5) @(posedge clk);

        rst = 0;
        @(posedge clk);

        $display("[%0t] Bat dau CS Full...", $time);
        start = 1;
        @(posedge clk);
        start = 0;

        // Chờ kết quả
        @(posedge best_Nd_valid);

        $display("==============================");
        $display("  best_Nd = %0d", best_Nd); 
        $display("  (Nd thuc te = 50)");
        if (best_Nd == 50)
            $display("  >> CHINH XAC!");
        else 
            $display("  >> SAI, can debug!");
        $display("==============================");

        $finish;
    end

    // ── Dump Waveform ─────────────────────────────────────────────
    initial begin
        $dumpfile("tb_cs_full.vcd");
        $dumpvars(0, tb_cs_full);
    end 

endmodule