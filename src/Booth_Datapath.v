`timescale 1ns / 1ps
module Booth_Datapath #(
    parameter n = 8
) (
    input wire clk,
    input wire start,
    input wire signed [n-1:0] multiplicand,
    input wire signed [n-1:0] multiplier,
    input wire ldAC,ldBR,ldQR,clrAC,clrff,cin,ldCNT,ashr,decr,addsub_inst,done,
    output signed [2*n-1:0] product,
    output reg signed [n-1:0] partial_product,
    output wire [n-1:0] SC,
    output wire cntz,q0,
    output reg qn1     
);
    reg [n-1:0] AC,BR,QR; wire [n-1:0] AC2;
    reg ashred=0;
    //wire [2*n-1:0] product_wire;
    assign cntz = (SC==0);
    assign q0=QR[0];
    assign product = {2*n{done}} & {AC,QR};
    always @(posedge clk) begin
        if (ldBR)
            BR <= multiplicand;
        if (ldQR)
            QR <= multiplier;
        if (clrAC)
            AC <= 0;
        if (ldAC)
            AC <= AC2;
        if (clrff && ~ashr)
            qn1 <= 0;
        if (ashr) begin
           {AC,QR,qn1} <= {AC[n-1],AC,QR};
           ashred <= 1'b1;
        end
        else ashred<=1'b0;
     end
    always @(posedge clk) begin
        if (ashred)
            partial_product <= AC;
       // if(ashred & cntz)
         //   product<={AC,QR};
    end
    n_bit_adder_subtractor #(n) as (.a(AC),.b(BR),.c(cin),.sum_diff(AC2),.addsub_inst(addsub_inst));
    sequence_counter #(n) cnt(.ldCNT(ldCNT),.clk(clk),.decr(ashred),.SC(SC)); 
endmodule
     
     
     
     