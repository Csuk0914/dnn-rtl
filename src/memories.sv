// This file contains a number of different types of memories
`timescale 1ns/100ps

`define SIM //Comment this for synthesis
`define INITMEMSIZE 2000 //number of elements in gaussian_list

//basic single port memory module
module singleport_mem #(
	parameter depth = 2, //No. of cells
	parameter width = 16, //No. of bits in each cell
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input [addrsize-1:0] address,
	input we, //write enable
	input [width-1:0] data_in,
	output logic [width-1:0] data_out = '0
);
	
	logic [width-1:0] mem [depth-1:0];

	always @(posedge clk) begin
		data_out = mem[address]; //can't hurt to read, even when we=1. If we=1, old value is read out and then new value is written
		if (we)
			mem[address] = data_in;
	end

	`ifdef SIM
		integer i;
		initial begin
			for (i = 0; i < depth; i = i + 1)
				mem[i] = '0;//($random%2)? $random%(2**22):-$random%(2**22);
			data_out = '0;
		end
	`endif
endmodule


module parallel_singleport_mem #(
	parameter z = 8, //no. of mems, each having depth cells, each cell has width bits
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(	
	input clk,
	input [addrsize*z-1:0] address_package,
	input [z-1:0] we,
	input [width*z-1:0] data_in_package,
	output [width*z-1:0] data_out_package
);

	// Unpack
	logic [addrsize-1:0] address[z-1:0];
	logic [width-1:0] data_in[z-1:0];
	logic [width-1:0] data_out[z-1:0];
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data_address
		assign data_in[gv_i] = data_in_package[width*(gv_i+1)-1:width*gv_i];
		assign data_out_package[width*(gv_i+1)-1:width*gv_i] = data_out[gv_i];
		assign address[gv_i] = address_package[addrsize*(gv_i+1)-1:addrsize*gv_i];
	end
	endgenerate
	// Done unpack

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : parallel_singleport_mem
		singleport_mem #(
			.depth(depth),
			.width(width)
		) singleport_mem (
			.clk(clk),
			.address(address[gv_i]),
			.we(we[gv_i]),
			.data_in(data_in[gv_i]),
			.data_out(data_out[gv_i])
		);
	end
	endgenerate
endmodule


module collection_singleport_mem #(
	parameter collection = 5, //no. of collections
	parameter z = 8, //no. of mems in each collection
	parameter depth = 2, //no. of cells in each mem
	parameter width = 16, //no. of bits in each cell
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input [collection*z-1:0] we_package,
	input [collection*z*addrsize-1:0] addr_package,
	input [collection*z*width-1:0] data_in_package,
	output [collection*z*width-1:0] data_out_package
);

	// unpack
	logic [z-1:0] we [collection-1:0];
	logic [addrsize*z-1:0] addr[collection-1:0];
	logic [width*z-1:0] data_in[collection-1:0];
	logic [width*z-1:0] data_out[collection-1:0];
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : package_collection
		assign we[gv_i] = we_package[z*(gv_i+1)-1:z*gv_i];
		assign addr[gv_i] = addr_package[z*addrsize*(gv_i+1)-1:z*addrsize*gv_i];
		assign data_in[gv_i] = data_in_package[z*width*(gv_i+1)-1:z*width*gv_i];
		assign data_out_package[z*width*(gv_i+1)-1:z*width*gv_i] = data_out[gv_i];
	end
	endgenerate
	// done unpack
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : collection_singleport_mem
		parallel_singleport_mem #(
			.z(z), 
			.width(width), 
			.depth(depth)
		) parallel_singleport_mem (
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

module simple_dualport_mem #(
	parameter purpose = 1,
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input weA,
	input [addrsize-1:0] addressA,
	input [addrsize-1:0] addressB,
	input [width-1:0] data_inA,
	output logic [width-1:0] data_outB = '0
);

	logic [width-1:0] mem [depth-1:0];

	always @(posedge clk) begin
		if (weA)
			mem[addressA] = data_inA;
		data_outB = mem[addressB]; //As usual, we always read out irrespective of we, because read is not destructive
	end

	`ifdef SIM
		integer i;
		initial begin
			#0.1; //memJ1 and memJ2 are read in the testbench at t=0. So wait a small while before reading from them
			for (i = 0; i < depth; i = i + 1) begin
				if (purpose==1)
					#0.1 mem[i] = tb_DNN.memJ1[($random%(`INITMEMSIZE/2)+(`INITMEMSIZE/2))]; //apparently $random%1000 gives a number in +/-999, so adding 1000 gives a number in [1,1999] as per the data file requirement
				else if (purpose==2)
					#0.1 mem[i] = tb_DNN.memJ2[($random%(`INITMEMSIZE/2)+(`INITMEMSIZE/2))];
			end
			data_outB = mem[addressB];
		end
	`endif
endmodule


module parallel_simple_dualport_mem #(
	parameter purpose = 1,
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(	
	input clk,
	input [z-1:0] weA_package,
	input [addrsize*z-1:0] addressA_package,
	input [addrsize*z-1:0] addressB_package,
	input [width*z-1:0] data_inA_package,
	output [width*z-1:0] data_outB_package
);

	// unpack
	logic [addrsize-1:0] addressA[z-1:0], addressB[z-1:0];
	logic [width-1:0] data_inA[z-1:0], data_inB[z-1:0];
	logic [width-1:0] data_outA[z-1:0], data_outB[z-1:0];
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data_address
		assign data_inA[gv_i] = data_inA_package[width*(gv_i+1)-1:width*gv_i];
		assign addressA[gv_i] = addressA_package[addrsize*(gv_i+1)-1:addrsize*gv_i];
		assign data_outB_package[width*(gv_i+1)-1:width*gv_i] = data_outB[gv_i];
		assign addressB[gv_i] = addressB_package[addrsize*(gv_i+1)-1:addrsize*gv_i];
	end
	endgenerate
	// done unpack

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : parallel_simple_dualport_mem
		simple_dualport_mem #(
			.purpose(purpose),
			.depth(depth),
			.width(width)
		) simple_dualport_mem (
			.clk(clk),
			.weA(weA_package[gv_i]),
			.addressA(addressA[gv_i]),
			.addressB(addressB[gv_i]),
			.data_inA(data_inA[gv_i]),
			.data_outB(data_outB[gv_i])
		);
	end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

module true_dualport_mem #(
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input weA,
	input weB,
	input [addrsize-1:0] addressA,
	input [addrsize-1:0] addressB,
	input [width-1:0] data_inA,
	input [width-1:0] data_inB,
	output logic [width-1:0] data_outA = '0,
	output logic [width-1:0] data_outB = '0
);

	logic [width-1:0] mem [depth-1:0];

	always @(posedge clk) begin
		if (weA)
			mem[addressA] = data_inA;
		if (weB)
			mem[addressB] = data_inB;
		//As usual, we always read out irrespective of we, because read is not destructive
		data_outA = mem[addressA];
		data_outB = mem[addressB];
	end

	`ifdef SIM
		integer i;
		initial begin
			for (i = 0; i < depth; i = i + 1) begin //
				mem[i] = '0;//($random%2)? $random%(2**23):-$random%(2**23);
			end
			data_outA = '0;
			data_outB = '0;
		end
	`endif
endmodule


module parallel_true_dualport_mem #(
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(	
	input clk,
	input [z-1:0] weA,
	input [z-1:0] weB,
	input [addrsize*z-1:0] addressA_package,
	input [addrsize*z-1:0] addressB_package,
	input [width*z-1:0] data_inA_package,
	input [width*z-1:0] data_inB_package,
	output [width*z-1:0] data_outA_package,
	output [width*z-1:0] data_outB_package
);

	// unpack
	logic [addrsize-1:0] addressA[z-1:0], addressB[z-1:0];
	logic [width-1:0] data_inA[z-1:0], data_inB[z-1:0];
	logic [width-1:0] data_outA[z-1:0], data_outB[z-1:0];
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data_address
		assign data_inA[gv_i] = data_inA_package[width*(gv_i+1)-1:width*gv_i];
		assign data_outA_package[width*(gv_i+1)-1:width*gv_i] = data_outA[gv_i];
		assign addressA[gv_i] = addressA_package[addrsize*(gv_i+1)-1:addrsize*gv_i];
		assign data_inB[gv_i] = data_inB_package[width*(gv_i+1)-1:width*gv_i];
		assign data_outB_package[width*(gv_i+1)-1:width*gv_i] = data_outB[gv_i];
		assign addressB[gv_i] = addressB_package[addrsize*(gv_i+1)-1:addrsize*gv_i];
	end
	endgenerate
	// done unpack

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : parallel_true_dualport_mem
		true_dualport_mem #(
			.depth(depth),
			.width(width)
		) true_dualport_mem (
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


module collection_true_dualport_mem #(	
	parameter collection = 5,
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input [collection*z-1:0] weA_package,
	input [collection*z-1:0] weB_package,
	input [collection*z*addrsize-1:0] addrA_package,
	input [collection*z*addrsize-1:0] addrB_package,
	input [collection*z*width-1:0] data_inA_package,
	input [collection*z*width-1:0] data_inB_package,
	output [collection*z*width-1:0] data_outA_package,
	output [collection*z*width-1:0] data_outB_package
);

	// unpack
	logic [z-1:0] weA[collection-1:0], weB[collection-1:0];
	logic [addrsize*z-1:0] addrA[collection-1:0], addrB[collection-1:0];
	logic [width*z-1:0] data_inA[collection-1:0], data_inB[collection-1:0];
	logic [width*z-1:0] data_outA[collection-1:0], data_outB[collection-1:0];	
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : package_collection
		assign weA[gv_i] = weA_package[z*(gv_i+1)-1:z*gv_i];
		assign addrA[gv_i] = addrA_package[z*addrsize*(gv_i+1)-1:z*addrsize*gv_i];
		assign data_inA[gv_i] = data_inA_package[z*width*(gv_i+1)-1:z*width*gv_i];
		assign data_outA_package[z*width*(gv_i+1)-1:z*width*gv_i] = data_outA[gv_i];
		assign weB[gv_i] = weB_package[z*(gv_i+1)-1:z*gv_i];
		assign addrB[gv_i] = addrB_package[z*addrsize*(gv_i+1)-1:z*addrsize*gv_i];
		assign data_inB[gv_i] = data_inB_package[z*width*(gv_i+1)-1:z*width*gv_i];
		assign data_outB_package[z*width*(gv_i+1)-1:z*width*gv_i] = data_outB[gv_i];
	end
	endgenerate
	// done unpack
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin : collection_true_dualport_mem
		parallel_true_dualport_mem #(
			.z(z), 
			.width(width), 
			.depth(depth)
		) parallel_true_dualport_mem (
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
