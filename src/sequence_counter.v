`timescale 1ns / 1ps

module sequence_counter #(parameter n=8) (SC, decr, ldCNT, clk);
input decr, clk,ldCNT;
output reg [n-1:0] SC;

always @(posedge clk)
begin
    if (ldCNT) 
        SC <= n;
    else if (decr & SC>0) 
        SC <= SC - 1;
end
endmodule

