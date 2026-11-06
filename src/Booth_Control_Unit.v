`timescale 1ns / 1ps
module Booth_Control_Unit(
    output reg ldAC, clrAC, ldQR,
    ldBR, clrff, cin, decr, ldCNT, done,ashr,addsub_inst,
    input start, clk, q0, qn1, cntz
    );
    reg [2:0] state;
    parameter S0=3'b000, S1=3'b001, S2=3'b010,
              S3=3'b011, S4=3'b100, S5=3'b101, S6=3'b110; 
    initial state=S0;
    always @(posedge clk)
    begin
        case(state)
            S0: if (start) state <= S1;
            S1: state <= S2;
            S2: begin
                if ({q0,qn1} == 2'b01) state <= S3;
                else if ({q0,qn1} == 2'b10) state <= S4;
                else state <= S5;
            end
            S3: state <= S5;
            S4: state <= S5;
            S5: begin
                if (cntz) state <= S6;
                else if ({q0,qn1} == 2'b01) state <= S3;
                else if ({q0,qn1} == 2'b10) state <= S4;
                else state <= S5;
            end
            S6: state <= S6;
            default: state <= S0;
        endcase
     end
    always @(*)
    begin
        {ldAC, clrAC, ldQR,ldBR, clrff, cin, decr, ldCNT, done,addsub_inst,ashr} = 11'b0;
        case (state)
            S0: ; 
            S1: begin ldBR = 1; ldQR = 1; end
            S2: begin clrAC = 1; clrff = 1; ldCNT = 1; end
            S3: begin addsub_inst=1;cin = 0;ldAC = 1; end
            S4: begin addsub_inst=1;cin = 1;ldAC = 1;end
            S5: begin ashr=1;decr=1; end
            S6: begin done = 1; end
        endcase
    end 
endmodule

