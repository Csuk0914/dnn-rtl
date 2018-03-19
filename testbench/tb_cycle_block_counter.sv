`timescale 1ns/100ps

module tb_cycle_block_counter #(
	parameter cpc = 18
)(
);

logic clk, reset;
wire cycle_clk;
wire [$clog2(cpc)-1:0] count;

cycle_block_counter #(.cpc(cpc)) cbc (.clk(clk), .reset(reset), .cycle_clk, .count(count));

initial begin
	clk = 0;
	reset = 1;
	#23 reset = 0;
	#250 $stop;
end

always #5 clk=~clk;
	
endmodule
