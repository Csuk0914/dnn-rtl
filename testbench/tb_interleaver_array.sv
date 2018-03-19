`timescale 1ns/100ps

module tb_interleaver_array #(
	parameter p  = 64,
	parameter fo = 8,
	parameter z  = 8,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_pfobyz = (p*fo==z) ? 1 : $clog2(p*fo/z)
)(
);

	logic [log_pfobyz-1:0] cycle_index;
	logic reset;
	logic [$clog2(p)-1:0] memory_index [z-1:0];

	initial begin
		reset = 0;
		#10 reset=1;
		#10 reset=0;

		cycle_index = '0;
		forever #10 cycle_index++;
	end

	initial #1000 $stop;

	interleaver_set #(.p(p),.fo(fo),.z(z)) its (.cycle_index, .reset, .memory_index);
endmodule
