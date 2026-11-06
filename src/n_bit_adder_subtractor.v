`timescale 1ns / 1ps

module n_bit_adder_subtractor #(parameter n=4)(
    input [n-1:0] a,
    input [n-1:0] b,
    input c,
    input addsub_inst,
    output [n-1:0] sum_diff,
    output car_b
    );
    wire [n:0] carry_bus;
    wire [n-1:0] bxor,band;
    xor x1 [n-1:0](bxor,b,c);
    and a1 [n-1:0](band,bxor,{n{addsub_inst}});
    buf b1(carry_bus[0],c);
    full_adder fa [n-1:0](.a(a),.b(band),.c(carry_bus[n-1:0]),.sum(sum_diff),.carry(carry_bus[n:1]));
    buf b2(car_b,carry_bus[n]);
endmodule

