`timescale 1ns / 100ps

module tb_singleport_memcoll #(
	parameter collection = 2, //no. of collections
	parameter z = 2, //no. of mems in each collection
	parameter depth = 2, //no. of cells in each mem
	parameter width = 4, //no. of bits in each cell
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
);

	logic clk=1, reset=1;
	logic [addrsize-1:0] address [collection-1:0] [z-1:0];
	logic [z-1:0] we [collection-1:0];
	logic [width-1:0] data_in [collection-1:0] [z-1:0], data_out [collection-1:0] [z-1:0];
	
	mem_collection #(
		.collection(collection),
		.z(z),
		.depth(depth),
		.width(width)
	) memcoll (
		.clk,
		.reset,
		.address,
		.we,
		.data_in,
		.data_out
	);
	
	always #5 clk=~clk;
	
	integer i,j;
	initial begin
		#12 reset=0;
		for (i=0; i<collection; i++) begin
			we[i] = '1;
			for (j=0; j<z; j++) begin
				data_in[i][j] = i+j+1;
				address[i][j] = 0;
			end
		end
		#2 address[1][1] = 1;
		#10; //24
		for (i=0; i<collection; i++) begin
			we[i] = '0;
			for (j=0; j<z; j++) begin
				data_in[i][j] = i+j+5;
				address[i][j] = 0;
			end
		end
		#14; //38
		for (i=0; i<collection; i++) begin
			we[i] = 2'b10;
			for (j=0; j<z; j++) begin
				data_in[i][j] = i+j+9;
				if (i==0)
					address[i][j] = 0;
				else
					address[i][j] = 1;
			end
		end
		#21 $stop; //59
	end
	// Assuming mode read-first
	// Let c=coll, m=mem, s=space(i.e. cell)
	// After 1st clk, out values should be all 0
	// After 2nd clk, out values should be all 0
	// After 2nd clk, c0m0 = 1,0, c0m1 = 2,0, c1m0 = 2,0, c1m1 = 0,3
	// After 3rd clk, out values are 1,2,2,0
	// After 4th clk, out values sre 1,2,0,3
	// After 4th clk, c0m0 = 1,0, c0m1 = a,0, c1m0 = 2,0, c1m1 = 0,b
	// After 5th clk, out values are 1,a,0,b

endmodule
