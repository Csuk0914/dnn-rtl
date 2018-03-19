`timescale 1ns / 1ps

module tb_max_finder_set #(
	parameter width = 13,
	parameter N = 37,
	parameter poswidth = $clog2(N)
)(
);

	logic signed [width-1:0] in [N-1:0];
	logic signed [width-1:0] out;
	logic [poswidth-1:0] pos;

	max_finder_set #(.width(width),.N(N),.poswidth(poswidth)) mfs (.in,.out,.pos);

	initial begin
		integer i;
		for (i=0; i<N; i++) begin
			 in[i] = $random%4096;
		end
		#10 $stop;
	end
endmodule
