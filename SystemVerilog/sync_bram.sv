module sync_bram #(
    parameter int DATA_W  = 32,    
    parameter int DEPTH   = 4000,  
    parameter     INIT_FILE = ""  
)(
    input  logic                      clk,
    input  logic                      we,      
    input  logic [$clog2(DEPTH)-1:0]  addr,  
    input  logic [DATA_W-1:0]         din,     
    output logic [DATA_W-1:0]         dout    
);

    logic [DATA_W-1:0] mem [0:DEPTH-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    always_ff @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;  
        end
        dout <= mem[addr];      // luôn đọc, trễ 1 cycle
    end

endmodule