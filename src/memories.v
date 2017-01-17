// This file contains a number of different types of memories
`timescale 1ns/100ps

//basic single port memory module
module memory #(
	parameter depth = 2, //No. of cells
	parameter width = 16 //No. of bits in each cell
)(
	input clk,
	input [$clog2(depth)-1:0] address,
	input we, //write enable
	input [width-1:0] data_in,
	output reg[width-1:0] data_out
);
	
	reg [width-1:0] mem [depth-1:0];

	always @(posedge clk) begin
		data_out = mem[address]; //can't hurt to read, even when we=1. If we=1, old value is read out and then new value is written
		if (we)
			mem[address] = data_in;
	end

	//[todo] Find how to initialize FPGA mem and delete initial
	integer i;
	initial begin
		for (i = 0; i < depth; i = i + 1)
			mem[i] = 0;//($random%2)? $random%(2**22):-$random%(2**22);
		data_out = 0;
	end
endmodule

//set of identical memory modules, each clocked by same clk. 1 whole set like this is a single collection
module parallel_mem #(
	parameter z = 8, //no. of mems, each having depth cells, each cell has width bits
	parameter depth = 2,
	parameter width = 16
)(	
	input clk,
	input [$clog2(depth)*z-1:0] address_package,
	input [z-1:0] we,
	input [width*z-1:0] data_in_package,
	output [width*z-1:0] data_out_package
);

	// Unpack
	wire [$clog2(depth)-1:0] address[z-1:0];
	wire [width-1:0] data_in[z-1:0];
	wire [width-1:0] data_out[z-1:0];
	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data_address
		assign data_in[gv_i] = data_in_package[width*(gv_i+1)-1:width*gv_i];
		assign data_out_package[width*(gv_i+1)-1:width*gv_i] = data_out[gv_i];
		assign address[gv_i] = address_package[$clog2(depth)*(gv_i+1)-1:$clog2(depth)*gv_i];
	end
	endgenerate
	// Done unpack

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : parallel_mem
		memory #(
			.depth(depth),
			.width(width)
		) mem (
			.clk(clk),
			.address(address[gv_i]),
			.we(we[gv_i]),
			.data_in(data_in[gv_i]),
			.data_out(data_out[gv_i])
		);
	end
	endgenerate
endmodule

//set of collections. Each collection is a parallel_mem, i.e. a set of memories of identical size and clocked by same clock
module mem_collection #(
	parameter collection = 5, //no. of collections
	parameter z = 8, //no. of mems in each collection
	parameter depth = 2, //no. of cells in each mem
	parameter width = 16 //no. of bits in each cell
)(
	input clk,
	input [collection*z-1:0] we_package,
	input [collection*z*$clog2(depth)-1:0] addr_package,
	input [collection*z*width-1:0] data_in_package,
	output [collection*z*width-1:0] data_out_package
);

	// unpack
	wire [z-1:0] we [collection-1:0];
	wire [$clog2(depth)*z-1:0] addr[collection-1:0];
	wire [width*z-1:0] data_in[collection-1:0];
	wire [width*z-1:0] data_out[collection-1:0];
	genvar gv_i;
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : package_collection
		assign we[gv_i] = we_package[z*(gv_i+1)-1:z*gv_i];
		assign addr[gv_i] = addr_package[z*$clog2(depth)*(gv_i+1)-1:z*$clog2(depth)*gv_i];
		assign data_in[gv_i] = data_in_package[z*width*(gv_i+1)-1:z*width*gv_i];
		assign data_out_package[z*width*(gv_i+1)-1:z*width*gv_i] = data_out[gv_i];
	end
	endgenerate
	// done unpack
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : mem_collection
		parallel_mem #(
			.z(z), 
			.width(width), 
			.depth(depth)
		) mem (
			.clk(clk),
			.address_package(addr[gv_i]),
			.we(we[gv_i]),
			.data_in_package(data_in[gv_i]),
			.data_out_package(data_out[gv_i])
		);
	end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

//basic dual port memory module
module dual_port_memory #(
	parameter depth = 2,
	parameter width = 16, 
	parameter fi = 0, 
	parameter fo = 0
)(
	input clk,
	input weA,
	input weB,
	input [$clog2(depth)-1:0] addressA,
	input [$clog2(depth)-1:0] addressB,
	input [width-1:0] data_inA,
	input [width-1:0] data_inB,
	output reg[width-1:0] data_outA,
	output reg[width-1:0] data_outB
);

	reg [width-1:0] mem [depth-1:0];

	always @(posedge clk) begin
		if (weA)
			mem[addressA] = data_inA;
		if (weB)
			mem[addressB] = data_inB;
		//As usual, we always read out irrespective of we, because read is not destructive
		data_outA = mem[addressA];
		data_outB = mem[addressB];
	end

	//[todo] Find how to initialize FPGA mem and delete initial
	integer i;
	initial begin
	#0.1;
	// for weight memory, initialize it to glorot normal distribution with mu = 0, sigma = 2/(fi+fo)
	// Marsaglia and Bray method to generate the random number following Gaussian distribution
		if(fi != 0) begin
			for (i = 0; i < depth; i = i + 1) begin //
				if((fi+fo)==136)
					#0.1 mem[i] = MNIST_tb.memL1[($random%1000+1000)];
				else if ((fi+fo)==40)
					#0.1 mem[i] = MNIST_tb.memL2[($random%1000+1000)];
			end
		end
		// for other memories, initialize to 0 value by passing parameter fi=0 during instantiation
		else begin
			for (i = 0; i < depth; i = i + 1) begin //
				mem[i] = 0;//($random%2)? $random%(2**23):-$random%(2**23);
			end
		end
		data_outA = mem[addressA];
		data_outB = mem[addressB];
	end
endmodule

//set of identical dual port memory modules, each clocked by same clk. 1 whole set like this is a single collection
module parallel_dual_port_mem #(
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16, 
	parameter fi = 0, 
	parameter fo = 0
)(	
	input clk,
	input [z-1:0] weA,
	input [z-1:0] weB,
	input [$clog2(depth)*z-1:0] addressA_package,
	input [$clog2(depth)*z-1:0] addressB_package,
	input [width*z-1:0] data_inA_package,
	input [width*z-1:0] data_inB_package,
	output [width*z-1:0] data_outA_package,
	output [width*z-1:0] data_outB_package
);

	// unpack
	wire [$clog2(depth)-1:0] addressA[z-1:0], addressB[z-1:0];
	wire [width-1:0] data_inA[z-1:0], data_inB[z-1:0];
	wire [width-1:0] data_outA[z-1:0], data_outB[z-1:0];
	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data_address
		assign data_inA[gv_i] = data_inA_package[width*(gv_i+1)-1:width*gv_i];
		assign data_outA_package[width*(gv_i+1)-1:width*gv_i] = data_outA[gv_i];
		assign addressA[gv_i] = addressA_package[$clog2(depth)*(gv_i+1)-1:$clog2(depth)*gv_i];
		assign data_inB[gv_i] = data_inB_package[width*(gv_i+1)-1:width*gv_i];
		assign data_outB_package[width*(gv_i+1)-1:width*gv_i] = data_outB[gv_i];
		assign addressB[gv_i] = addressB_package[$clog2(depth)*(gv_i+1)-1:$clog2(depth)*gv_i];
	end
	endgenerate
	// done unpack

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : parallel_mem
		dual_port_memory #(
			.depth(depth),
			.width(width), 
			.fi(fi), 
			.fo(fo)
		) dual_port_memory (
			.clk(clk),
			.addressA(addressA[gv_i]),
			.weA(weA[gv_i]),
			.data_inA(data_inA[gv_i]),
			.data_outA(data_outA[gv_i]),
			.addressB(addressB[gv_i]),
			.weB(weB[gv_i]),
			.data_inB(data_inB[gv_i]),
			.data_outB(data_outB[gv_i])
		);
	end
	endgenerate
endmodule

//set of collections. Each collection is a dual port parallel_mem, i.e. a set of memories of identical size and clocked by same clock
module dual_port_mem_collection #(	
	parameter collection = 5,
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16, 
	parameter fi = 0, 
	parameter fo = 0
)(
	input clk,
	input [collection*z-1:0] weA_package,
	input [collection*z-1:0] weB_package,
	input [collection*z*$clog2(depth)-1:0] addrA_package,
	input [collection*z*$clog2(depth)-1:0] addrB_package,
	input [collection*z*width-1:0] data_inA_package,
	input [collection*z*width-1:0] data_inB_package,
	output [collection*z*width-1:0] data_outA_package,
	output [collection*z*width-1:0] data_outB_package
);

	// unpack
	wire [z-1:0] weA[collection-1:0], weB[collection-1:0];
	wire [$clog2(depth)*z-1:0] addrA[collection-1:0], addrB[collection-1:0];
	wire [width*z-1:0] data_inA[collection-1:0], data_inB[collection-1:0];
	wire [width*z-1:0] data_outA[collection-1:0], data_outB[collection-1:0];	
	genvar gv_i;
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : package_collection
		assign weA[gv_i] = weA_package[z*(gv_i+1)-1:z*gv_i];
		assign addrA[gv_i] = addrA_package[z*$clog2(depth)*(gv_i+1)-1:z*$clog2(depth)*gv_i];
		assign data_inA[gv_i] = data_inA_package[z*width*(gv_i+1)-1:z*width*gv_i];
		assign data_outA_package[z*width*(gv_i+1)-1:z*width*gv_i] = data_outA[gv_i];
		assign weB[gv_i] = weB_package[z*(gv_i+1)-1:z*gv_i];
		assign addrB[gv_i] = addrB_package[z*$clog2(depth)*(gv_i+1)-1:z*$clog2(depth)*gv_i];
		assign data_inB[gv_i] = data_inB_package[z*width*(gv_i+1)-1:z*width*gv_i];
		assign data_outB_package[z*width*(gv_i+1)-1:z*width*gv_i] = data_outB[gv_i];
	end
	endgenerate
	// done unpack
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : mem_collection
		parallel_dual_port_mem #(
			.z(z), 
			.width(width), 
			.depth(depth), 
			.fi(fi), 
			.fo(fo)
		) mem (
			.clk(clk),
			.addressA_package(addrA[gv_i]),
			.weA(weA[gv_i]),
			.data_inA_package(data_inA[gv_i]),
			.data_outA_package(data_outA[gv_i]),
			.addressB_package(addrB[gv_i]),
			.weB(weB[gv_i]),
			.data_inB_package(data_inB[gv_i]),
			.data_outB_package(data_outB[gv_i])
		);
	end
	endgenerate
endmodule
