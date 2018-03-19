`timescale 1ns / 1ps

module tb_parallel_simple_dual_port_mem #(
	parameter purpose=1,
	parameter z = 2, //no. of mems in each collection
	parameter depth = 16, //no. of cells in each mem
	parameter width = 12, //no. of bits in each cell
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
);

	logic clk=1, reset=1;
	logic [addrsize-1:0] addressA [z-1:0], addressB [z-1:0];
	logic [z-1:0] weA;
	logic [width-1:0] data_inA [z-1:0], data_outB [z-1:0];
	
	parallel_simple_dual_port_mem #(
		.purpose(purpose),
		.z(z),
		.depth(depth),
		.width(width)
	) psdpmem (
		.clk,
		.reset,
		.addressA,
		.weA,
		.data_inA,
		.addressB,
		.data_outB
	);
	
	always #5 clk=~clk;
	
	integer j;
	initial begin
		#12 reset=0;
		weA = '0;
		for (j=0; j<z; j++) begin
			data_inA[j] = j+1;
			addressA[j] = 0;
			addressB[j] = j+5;
		end
		#12; //24
		weA = '1;
		for (j=0; j<z; j++) begin
			data_inA[j] = j+5;
			addressA[j] = j;
		end
		#14; //38
		weA = 2'b10;
		for (j=0; j<z; j++) begin
			addressB[j] = j;
			data_inA[j] = j+99;
			addressA[j] = j;
		end
		#20 addressB[0] = 4'hf;
		#11 $stop; //69
	end
	// Assuming mode read-first
	// After 1st clk, out values should be all 0
	// After 2nd clk, out values are FD7,FF0
	// After 3rd clk, out values are FD7,FF0
	// After 3rd clk, m0 cell0 has 5, m1 cell1 has 6
	// After 4th clk, out values are 005,006
	// After 4th clk, m0 retains all, m1 cell1 has 064
	// After 5th clk, out values are 005,064
	// After 6th clk, out values are FEE,064

endmodule
