`timescale 1ns / 1ps
module Booth_Multiplier #(parameter n = 8)(
    input wire clk,
    input wire start,
    input wire signed [n-1:0] multiplicand,
    input wire signed [n-1:0] multiplier,
    output wire signed [2*n-1:0] product,
    output wire signed [n-1:0] partial_product,
    output wire [n-1:0] SC,
    output wire done
);
    wire ldAC, clrAC, ldQR, ldBR, clrff, cin;
    wire ldCNT, ashr, decr, addsub_inst;
    wire q0, qn1, cntz;
    Booth_Datapath #(n) datapath (
        .clk(clk),.start(start),
        .multiplicand(multiplicand),
        .multiplier(multiplier),
        .ldAC(ldAC), .clrAC(clrAC), .ldQR(ldQR), .ldBR(ldBR), .clrff(clrff),
        .cin(cin), .ldCNT(ldCNT), .ashr(ashr), .decr(decr), .addsub_inst(addsub_inst),
        .q0(q0), .qn1(qn1), .cntz(cntz),.done(done),
        .product(product),.SC(SC), .partial_product(partial_product)
    );
    Booth_Control_Unit control_unit (
        .clk(clk), .start(start), .q0(q0), .qn1(qn1), .cntz(cntz),
        .ldAC(ldAC), .clrAC(clrAC), .ldQR(ldQR), .ldBR(ldBR), .clrff(clrff),
        .cin(cin), .ldCNT(ldCNT), .ashr(ashr), .decr(decr),
        .addsub_inst(addsub_inst), .done(done)
    );
endmodule





