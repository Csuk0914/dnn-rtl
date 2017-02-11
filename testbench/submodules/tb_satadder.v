// Testbench for saturating adder
`timescale 1ns/1ps
module tb_satadder #(
	parameter width = 8
)(
);

reg [width-1:0] a,b;
wire [width-1:0] z;

adder #(.width(width)) satadd (a,b,z);

initial begin
a = 8'b00001111;
b = a;
#10 a = 8'b01010101;
b = a;
#10 a = 8'b11000000;
b = a;
#10 a = 8'b10111111;
b = a;
#10 a = 8'b00000000;
b = 8'b10000000;
#10 a = 8'b10000000;
b = 8'b00000000;
#10 a = 8'b01111111;
b = a;
#10 a = 8'b10101010;
b = a;
#10 $stop;
end

endmodule
