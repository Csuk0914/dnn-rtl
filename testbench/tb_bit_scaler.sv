`timescale 1ns / 100ps

module tb_bit_scaler();

	logic signed [25:0] a = 26'b11111111111111111111110010; //-14 in 2,24
	logic signed [23:0] a1; //-14 in 1,23 = 24'hfffff2
	logic signed [23:0] a2; //-14 in 2,6,16 = 24'hf20000
	logic signed [11:0] a3; //-14 in 1,3,8 = 12'h800, neg overflow
	logic signed [27:0] a4; //-14 in 1,27 = 28'hffffff2
	
	logic signed [11:0] b = 12'h7ff; //8 - 2^-8 in 1,3,8
	logic signed [23:0] b1; //8 - 2^-8 in 2,6,16 = 24'h07ff00
	logic signed [25:0] b2; //8 - 2^-8 in 2,8,16 = 26'h007ff00
	logic signed [11:0] b3; //8 - 2^-8 in 1,1,10 = 12'h7ff, pos overflow
	logic signed [8:0] b4; //8 - 2^-8 in 3,4,2 = 9'h020 (rounded up to 8)
	
	logic signed [11:0] c = 12'h2ff; //3 - 2^-8 in 1,3,8
	logic signed [5:0] c1; //3 - 2^-8 in 1,2,3 = 6'b011000 = 6'h18 (rounded up to 3)
	logic signed [15:0] c2; //3 - 2^-8 in 5,2,9 = 16'h05fe (no rounding)
	
	bit_scaler #(.from_width(26),.from_sign_bits(2),.from_int_bits(24), .width(24),.sign_bits(1),.int_bits(23)) bsa1 (.in(a),.out(a1));
	bit_scaler #(.from_width(26),.from_sign_bits(2),.from_int_bits(24), .width(24),.sign_bits(2),.int_bits(6)) bsa2 (.in(a),.out(a2));
	bit_scaler #(.from_width(26),.from_sign_bits(2),.from_int_bits(24), .width(12),.sign_bits(1),.int_bits(3)) bsa3 (.in(a),.out(a3));
	bit_scaler #(.from_width(26),.from_sign_bits(2),.from_int_bits(24), .width(28),.sign_bits(1),.int_bits(27)) bsa4 (.in(a),.out(a4));

	bit_scaler #(.from_width(12),.from_sign_bits(1),.from_int_bits(3), .width(24),.sign_bits(2),.int_bits(6)) bsb1 (.in(b),.out(b1));
	bit_scaler #(.from_width(12),.from_sign_bits(1),.from_int_bits(3), .width(26),.sign_bits(2),.int_bits(8)) bsb2 (.in(b),.out(b2));
	bit_scaler #(.from_width(12),.from_sign_bits(1),.from_int_bits(3), .width(12),.sign_bits(1),.int_bits(1)) bsb3 (.in(b),.out(b3));
	bit_scaler #(.from_width(12),.from_sign_bits(1),.from_int_bits(3), .width(9),.sign_bits(3),.int_bits(4)) bsb4 (.in(b),.out(b4));
	
	bit_scaler #(.from_width(12),.from_sign_bits(1),.from_int_bits(3), .width(6),.sign_bits(1),.int_bits(2)) bsc1 (.in(c),.out(c1));
	bit_scaler #(.from_width(12),.from_sign_bits(1),.from_int_bits(3), .width(16),.sign_bits(5),.int_bits(2)) bsc2 (.in(c),.out(c2));
	
	initial #5 $stop;
endmodule
