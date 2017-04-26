`timescale 1ns/100ps

module tb_cycle_block_counter();

reg clk=1, reset=1;
wire cycle_clk;
wire [2:0] count;

//cycle_block_counter_old #(.clk_per_block(6)) cbc (.clk(clk), .reset(reset), .cycle_clk(cycle_clk), .count(count));
cycle_block_counter #(.cpc(6)) cbc (.clk(clk), .reset(reset), .cycle_clk(cycle_clk), .count(count));

always #5 clk = ~clk;

initial begin
	#48 reset=0;
	#200 $stop;
end
endmodule


// Original Yinan's cycle block counter
module cycle_block_counter_old #(
	parameter ini = 0,
	parameter clk_per_block = 4 //expected cpc
)(
	input clk,
	input reset,
	output reg cycle_clk = clk_per_block-1, //this is the block cycle clock
	output reg [$clog2(clk_per_block)-1:0] count = ini
);

	always @(posedge clk) begin
		if (reset)
			count <= clk_per_block-1; //count goes to highest value on reset, so that it becomes 0 on next clk
		else begin
			if((count + 1) == clk_per_block)			
				count <= 0;
			else
				count <= count + 1;
		end

		if (count == clk_per_block-1) //This is regardless of reset
			cycle_clk = 1;
		else
			cycle_clk = 0;
	end
endmodule
