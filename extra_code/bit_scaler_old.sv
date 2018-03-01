// Scales DOWN {from_sign_bits,from_int_bits,from_frac_bits} input to {sign_bits,int_bits,frac_bits} output
// {from_sign_bits,from_int_bits,from_frac_bits} respectively >= {sign_bits,int_bits,frac_bits}
// Assumes all from_sign bits are the same. If different (exception), the desired output is the max positive value possible
// Eg: Converting from {2,6,16} to {1,3,8}. If the input is 2^6 = 24'b010000..., then the sign bits are not the same. In this case, output is 2^3-1 = 12'b01111...
module bit_reducer #(
	//Input bit widths
	parameter from_width = 26,
	parameter from_sign_bits = 2,
	parameter from_int_bits = 8,
	localparam from_frac_bits = from_width-from_sign_bits-from_int_bits,
	
	// Output bit widths
	parameter width = 12,
	parameter sign_bits = 1,
	parameter int_bits = 3,
	localparam frac_bits = width-sign_bits-int_bits
)(
	input signed [from_width-1:0] in,
	output signed [width-1:0] out
);
	logic signed [width-1:0] p_temp; //Holds truncated output before rounding
	logic signed [from_int_bits:0] p_int; //Holds LSB sign bit and all integer bits of input
	
	assign p_int = in[(from_width-from_sign_bits) -: (from_int_bits+1)];
		
	assign p_temp = (in[from_width-1] != in[from_width-from_sign_bits]) ? {{sign_bits{1'b0}},{(width-sign_bits){1'b1}}} : //handling exception, set output to max positive
					(p_int > 2**int_bits-1) ? {{sign_bits{1'b0}},{(width-sign_bits){1'b1}}} : //positive overflow, set output to max positive
					(p_int < -2**int_bits) ? {{sign_bits{1'b1}},{(width-sign_bits){1'b0}}} : //negative overflow, set output to max negative
					{in[from_width-1 -: sign_bits] , in[from_frac_bits+int_bits-1 -: (width-sign_bits)]}; //normal case: sign bits + int_bits LSB of integer portion + frac_bits MSB of fractional portion
	
	assign out = (in[from_frac_bits-frac_bits-1]==0 || p_temp == {{sign_bits{1'b0}},{(width-sign_bits){1'b1}}} ) ? //check MSB of left-out frac part in in. If that is 0, out=p_temp.
				// If that is 1, but p_temp is max positive value, then also out=p_temp (because we don't want overflow)
				p_temp : p_temp+1; //otherwise round up out to p_temp+1, like 0.5 becomes 1
endmodule


// Scales UP {from_sign_bits,from_int_bits,from_frac_bits} input to {sign_bits,int_bits,frac_bits} output
// {from_sign_bits,from_int_bits,from_frac_bits} respectively <= {sign_bits,int_bits,frac_bits}
// Assumes all from_sign bits are the same
module bit_expander #(
	//Input bit widths
	parameter from_width = 12,
	parameter from_sign_bits = 1,
	parameter from_int_bits = 3,
	localparam from_frac_bits = from_width-from_sign_bits-from_int_bits,
	
	// Output bit widths
	parameter width = 24,
	parameter sign_bits = 2,
	parameter int_bits = 6,
	localparam frac_bits = width-sign_bits-int_bits
)(
	input signed [from_width-1:0] in,
	output signed [width-1:0] out
);
	//For positive numbers, add 0s at beginning. For negative numbers, add 1s at beginning
	//Always add 0s in frac portion at end
	assign out = (in>=0) ?
				{ {(sign_bits+int_bits-from_int_bits-1){1'b0}}, in, {(frac_bits-from_frac_bits){1'b0}} } :
				{ {(sign_bits+int_bits-from_int_bits-1){1'b1}}, in, {(frac_bits-from_frac_bits){1'b0}} };
endmodule
