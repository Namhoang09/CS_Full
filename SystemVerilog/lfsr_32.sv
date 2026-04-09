module lfsr_32 (
    input  logic clk,
    input  logic rst,
    input  logic en,          
    output logic g_bit      
);

    // Đa thức LFSR 32-bit tối ưu: x^32 + x^22 + x^2 + x^1 + 1
    localparam logic [31:0] POLYNOMIAL = 32'h80200003;
    
    // Seed khởi tạo (BẮT BUỘC KHÁC 0)
    localparam logic [31:0] SEED = 32'hDEADBEEF; 

    logic [31:0] lfsr_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr_reg <= SEED;
        end else if (en) begin
            // Thuật toán Galois LFSR
            if (lfsr_reg[0] == 1'b1)
                lfsr_reg <= (lfsr_reg >> 1) ^ POLYNOMIAL;
            else
                lfsr_reg <= (lfsr_reg >> 1);
        end
    end

    // Ngõ ra là bit LSB
    assign g_bit = lfsr_reg[0];

endmodule