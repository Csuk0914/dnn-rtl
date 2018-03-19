`timescale 1ns / 100ps

module tb_true_dualport_memory #(
	parameter purpose = 91,
	parameter depth = 2,
	parameter width = 4,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
);

	logic clk=1, reset=1;
	logic weA;
	logic weB;
	logic [addrsize-1:0] addressA;
	logic [addrsize-1:0] addressB;
	logic [width-1:0] data_inA;
	logic [width-1:0] data_outA;
	logic [width-1:0] data_inB;
	logic [width-1:0] data_outB;
	
	true_dual_port_memory #(
		.purpose(purpose),
		.depth(depth),
		.width(width)
	) tdpm (
		.clk(clk),
		.reset(reset),
		.weA(weA),
		.weB(weB),
		.addressA(addressA),
		.addressB(addressB),
		.data_inA(data_inA),
		.data_inB(data_inB),
		.data_outA(data_outA),
		.data_outB(data_outB)
	);
	
	always #5 clk=~clk;
	
	initial begin
		weA=1;
		weB=0;
		#4 reset=0;
		addressA = 0;
		addressB = 0;
		data_inA = 4'hf;
		data_inB = 4'hf;
		#10;
		data_inA = 4'ha;
		#10;
		data_inA = 4'h5;
		#30;
		weA = 0;
		weB = 1;
		#25 $stop;
	end
endmodule


module tb_true_dual_port_memcoll #(
	parameter collection = 2, //no. of collections
	parameter z = 2, //no. of mems in each collection
	parameter depth = 2, //no. of cells in each mem
	parameter width = 4, //no. of bits in each cell
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
);

	logic clk=1, reset=1;
	logic [addrsize-1:0] addressA [collection-1:0] [z-1:0], addressB [collection-1:0] [z-1:0];
	logic [z-1:0] weA [collection-1:0], weB [collection-1:0];
	logic [width-1:0] data_inA [collection-1:0] [z-1:0], data_outA [collection-1:0] [z-1:0], data_inB [collection-1:0] [z-1:0], data_outB [collection-1:0] [z-1:0];
	
	true_dual_port_mem_collection #(
		.collection(collection),
		.z(z),
		.depth(depth),
		.width(width)
	) tdpmemcoll (
		.clk,
		.reset,
		.addressA,
		.weA,
		.data_inA,
		.data_outA,
		.addressB,
		.weB,
		.data_inB,
		.data_outB
	);
	
	always #5 clk=~clk;
	
	integer i,j;
	initial begin
		#12 reset=0;
		for (i=0; i<collection; i++) begin
			weA[i] = '1;
			weB[i] = '0;
			for (j=0; j<z; j++) begin
				data_inA[i][j] = i+j+1;
				data_inB[i][j] = i+j+7; //immaterial
				addressA[i][j] = 0;
				addressB[i][j] = 0;
			end
		end
		#2 addressA[1][1] = 1;
		#10; //24
		for (i=0; i<collection; i++) begin
			weA[i] = '0;
			weB[i] = '1;
			for (j=0; j<z; j++) begin
				data_inA[i][j] = i+j+3; //immaterial
				data_inB[i][j] = i+j+5;
				addressA[i][j] = 0;
				addressB[i][j] = 1;
			end
		end
		#14; //38
		for (i=0; i<collection; i++) begin
			weA[i] = 2'b10;
			weB[i] = 2'b01;
			for (j=0; j<z; j++) begin
				data_inB[i][j] = i+j+9;
				if (i==0) begin
					addressA[i][j] = 0;
					addressB[i][j] = 1;
				end else begin
					addressA[i][j] = 1;
					addressB[i][j] = 0;
				end
			end
		end
		#21 $stop; //59
	end
	// Assuming mode read-first
	// Let c=coll, m=mem, s=space(i.e. cell)
	// After 1st clk, out values should be all 0
	// After 2nd clk, out values should be all 0
	// After 2nd clk, A: c0m0 = 1,0, c0m1 = 2,0, c1m0 = 2,0, c1m1 = 0,3, B: all values are still 0
	// After 3rd clk, outA values are 1,2,2,0, outB values are all 0
	// After 3rd clk, A stays as it is, B: c0m0 = 5,0, c0m1 = 6,0, c1m0 = 6,0, c1m1 = 7,0
	// After 4th clk, outA values are 1,2,0,3, outB values are 5,6,0,0
	// After 4th clk, A: c0m0 = 1,0, c0m1 = a,0, c1m0 = 2,0, c1m1 = 0,b, B: c0m0 = 9,0, c0m1 = 6,0, c1m0 = 6,a, c1m1 = 7,0
	// After 5th clk, outA values are 1,a,0,b, outB values are 9,6,a,0

endmodule
