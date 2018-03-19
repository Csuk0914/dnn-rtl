`timescale 1ns / 100ps

`define CLOCKPERIOD 10

module tb_wb_mem_ctr #(
	parameter p = 64,
	parameter fo = 8,
	parameter z = 32,
	parameter ec = 2,
	parameter cpc = p*fo/z + ec
)(
);

	logic clk=1;
	logic reset=0;
	logic cycle_clk;
	logic [$clog2(cpc)-1:0] cycle_index;
	logic [z-1:0] weA;
	logic [$clog2(p*fo/z)-1:0] r_addr [z-1:0]; //p*fo/z cells in each weight memory, and there are z mems
	logic [$clog2(p*fo/z)-1:0] w_addr [z-1:0];
	
	always #(`CLOCKPERIOD/2) clk=~clk;
	
	cycle_block_counter #(
		.cpc(cpc)
	) cbc (
		.clk,
		.reset,
		.cycle_clk,
		.count(cycle_index)
	);
	
	wb_mem_ctr #(
		.p(p),
		.fo(fo),
		.z(z),
		.ec(ec),
		.cpc(cpc)
	) wbmc (
		.clk,
		.reset,
		.cycle_index,
		.weA,
		.r_addr,
		.w_addr
	);
	
	initial #(cpc*`CLOCKPERIOD) $stop;
	
endmodule