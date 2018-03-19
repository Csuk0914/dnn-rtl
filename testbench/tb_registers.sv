`timescale 1ns / 100ps

module tb_registers #(
	parameter width = 8,
	depth = 5
);

logic clk=0, reset=0;
logic [width-1:0] d = 8'h01;
logic [width-1:0] qsync, qasync, qsr;

DFF_syncreset #(
	.width(width)
) dff_syncreset (
	.clk,
	.reset,
	.d,
	.q(qsync)
);

DFF #(
	.width(width)
) dff_asyncreset (
	.clk,
	.reset,
	.d,
	.q(qasync)
);

shift_reg #(
	.width(width),
	.depth(depth)
) sr (
	.clk,
	.reset,
	.d,
	.q(qsr)
);

always #5 clk=~clk;
always #10 d++;

initial begin
	#23 reset = 1;
	#10 reset=0;
	#75 reset=1; //t=108
	#75 reset=0; //t=183
	#67 $stop; //t=250
end
endmodule
