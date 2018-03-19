`timescale 1ns / 100ps

module tb_act_functions #(
	parameter width = 12
)(
);

	logic clk=1;
	logic signed [width-1:0] val;
	logic signed [width-1:0] sigmoid_out;
	logic signed [width-1:0] sigmoid_prime_out;
	logic signed [width-1:0] relu_out;
	logic signed [width-1:0] relu_prime_out;
	
	always #5 clk=~clk;
	
	initial begin
		val = 12'b100000000100; //sp = 12'h009
		#33 val = 12'b011111111011; //sp = 12'h009
		#33 val = 12'b100101011000; //sp = 12'h011
		#33 $stop;
	end
	
	sigmoid_all #(.width(width)) sigm (.clk, .val, .sigmoid_out, .sigmoid_prime_out);
	relu_all #(.width(width)) rel (.clk, .val, .relu_out, .relu_prime_out);

endmodule
