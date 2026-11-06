`timescale 1ns / 1ps

module full_adder(
    input a,
    input b,
    input c,
    output sum,
    output carry
    );
    wire w1,w2,w3;
    xor x1(sum,a,b,c);
    and 
        a1(w1,a,b),
        a2(w2,b,c),
        a3(w3,c,a);
    or o1(carry,w1,w2,w3);
endmodule

