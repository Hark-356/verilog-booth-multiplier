`timescale 1ns / 1ps
module Booth_Multiplier_tb;
    parameter n = 5,m=4;
    reg start, clk;
    reg signed [n-1:0] multiplicand, multiplier;
    wire signed [2*n-1:0] product;
    wire signed [n-1:0] partial_product;
    wire [n-1:0] SC;
    wire done;
    Booth_Multiplier #(n,m) uut (
        .clk(clk),
        .start(start),
        .multiplicand(multiplicand),
        .multiplier(multiplier),
        .product(product),
        .partial_product(partial_product),
        .SC(SC),
        .done(done)
    );
    initial clk = 0;
    always #5 clk = ~clk;
    initial begin
        $display("Time\tAC\t\tQR\t\tBR\t\tSC\tqn1\tldAC clrAC ldQR ldBR clrff cin ldCNT ashr decr addsub done\tProduct\tPartial");
        multiplicand = 15;
        multiplier   = -14;
        start = 1;
        #10;  
        start = 0;
        wait (done); 
        #10;
    end

    always @(posedge clk) begin
        $display("%0t\t%b\t%b\t%b\t%d\t%b\t%b  %b    %b   %b     %b     %b   %b     %b    %b     %b\t%b\t%b", 
            $time,
            uut.datapath.AC,
            uut.datapath.QR,
            uut.datapath.BR,
            uut.datapath.SC,
            uut.datapath.qn1,
            uut.control_unit.ldAC,
            uut.control_unit.clrAC,
            uut.control_unit.ldQR,
            uut.control_unit.ldBR,
            uut.control_unit.clrff,
            uut.control_unit.cin,
            uut.control_unit.ldCNT,
            uut.control_unit.ashr,
            uut.control_unit.decr,
            uut.control_unit.addsub_inst,
            uut.control_unit.done,
            product,
            partial_product
        );
    end
endmodule


