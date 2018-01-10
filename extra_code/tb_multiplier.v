`timescale 1ns/100ps

module tb_multiplier #(
	parameter width = 16,
	parameter int_bits = 5
)(
	
);

reg signed [width-1:0] a, b;
wire signed [width-1:0] z;

multiplier #(.width(width),.int_bits(int_bits)) mult (a,b,z);

initial begin
	a = 16'b0101010100000000; //21.25
	b = 16'b0000000010000000; //0.125
	#10; //2.65625
	b = 16'b1111111110000000; //-0.125
	#10; //-2.65625
	a = 16'b0000011000000000; //1.5
	b = 16'b1000100000000000; //-30
	#10; //-45
	b = 16'b0101100000100000; //22.03125
	#10; //33.046875
	a = 16'b1000000000000000; //-32
	b = a; //-32
	#10; //1024
	b = 16'b0111111111111111; //32
	#10; //-1024
	a = b; //32
	#10 $stop; //1024
end
endmodule
