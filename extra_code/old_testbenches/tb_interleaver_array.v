`timescale 1ns/100ps

module tb_interleaver_array #(
	parameter fo = 2,
	parameter p = 32,
	parameter z = 8,
	// => p/z = 4, total weights = 64, cpc = 8
	parameter [$clog2(p/z)-1:0] sweepstart [0:fo*z-1] = '{2'd1,2'd3,2'd2,2'd0,2'd0,2'd2,2'd1,2'd3,2'd2,2'd0,2'd3,2'd1,2'd3,2'd1,2'd0,2'd2}
);

	reg [$clog2(fo*p/z)-1:0] cycle_index; //000 -> ... -> 111
	wire [$clog2(p)*z-1:0] memory_index_package;
	interleaver_set #(.fo(fo), .p(p), .z(z), .sweepstart(sweepstart)) inter (.cycle_index(cycle_index), .memory_index_package(memory_index_package));

	reg clk;
	always #5 clk=~clk;
	always @(posedge clk) cycle_index = cycle_index+1;

	initial begin
		clk = 1'b1;
		cycle_index = 3'b111;
		#101 $stop;
	end

endmodule
