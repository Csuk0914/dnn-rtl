`timescale 1ns/100ps

module tb_sigtables #(
	parameter width = 16,
	parameter int_bits = 3,
	parameter frac_bits = 12
)(

);

reg clk=1;
always #5 clk=~clk;

reg [width-1:0] z;
wire [width-1:0] s;
wire [width-1:0] sp;

sigmoid_t #(.width(width),.int_bits(int_bits),.frac_bits(frac_bits)) stest (.clk(clk),.z(z),.sigmoid_out(s));
sig_prime #(.width(width),.int_bits(int_bits),.frac_bits(frac_bits)) sptest (.clk(clk),.z(z),.sp_out(sp));

initial begin
z = 0;
#2  z = 1;
#6  z = 16'b0001000000000000; //1
#10 z = 16'b1110000000000000; //-2
#10 z = 16'b0000000000000000; //0
#10 z = 16'b0111110000000000; //7.75
#10 z = 16'b1011000000000100; //-5 + 2^-10
#10 $stop;
end

endmodule
