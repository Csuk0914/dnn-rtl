// This file contains a number of different types of memories
`timescale 1ns/100ps

`define SIM //Comment this for synthesis
`define INITMEMSIZE 2000 //number of elements in gaussian_list

//basic single port memory module
module memory #(
	parameter depth = 2, //No. of cells
	parameter width = 16 //No. of bits in each cell
)(
	input clk,
	input reset,
	input [$clog2(depth)-1:0] address,
	input we, //write enable
	input signed [width-1:0] data_in,
	output logic signed [width-1:0] data_out
);
	
	logic signed [width-1:0] mem [depth-1:0];

	always @(posedge clk) begin
		data_out = mem[address]; //can't hurt to read, even when we=1. If we=1, old value is read out and then new value is written
		if (we)
			mem[address] = data_in;
	end

	//FPGA synth doesn't support initial. [TODO] find how to initialize FPGA RAMs
	`ifdef SIM
		integer i;
		initial begin
			for (i = 0; i < depth; i = i + 1)
				mem[i] = 0;//($random%2)? $random%(2**22):-$random%(2**22);
			data_out = 0;
		end
	`endif
endmodule

//set of identical memory modules, each clocked by same clk. 1 whole set like this is a single collection
module parallel_mem #(
	parameter z = 8, //no. of mems, each having depth cells, each cell has width bits
	parameter depth = 2,
	parameter width = 16
)(	
	input clk,
	input reset,
	input [$clog2(depth)-1:0] address [z-1:0],
	input [z-1:0] we,
	input signed [width-1:0] data_in [z-1:0],
	output signed [width-1:0] data_out [z-1:0]
);

	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : parallel_mem
		memory #(
			.depth(depth),
			.width(width)
		) mem (
			.clk(clk),
			.reset(reset),
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
	input reset,
	input [$clog2(depth)-1:0] address [collection-1:0] [z-1:0],
	input [z-1:0] we [collection-1:0],
	input signed [width-1:0] data_in [collection-1:0] [z-1:0],
	output signed [width-1:0] data_out [collection-1:0] [z-1:0]
);

	genvar gv_i;
	generate for (gv_i = 0; gv_i<collection; gv_i++) begin: mem_collection
		parallel_mem #(
			.z(z), 
			.width(width), 
			.depth(depth)
		) parmem (
			.clk,
			.reset,
			.address(address[gv_i]),
			.we(we[gv_i]),
			.data_in(data_in[gv_i]),
			.data_out(data_out[gv_i])
		);
	end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

//basic dual port memory module
module simple_dual_port_memory #(
	parameter purpose = 1,
	parameter depth = 2,
	parameter width = 16
)(
	input clk,
	input reset,
	input weA,
	input [$clog2(depth)-1:0] addressA,
	input [$clog2(depth)-1:0] addressB,
	input signed [width-1:0] data_inA,
	output logic signed [width-1:0] data_outB
);

	logic signed [width-1:0] mem [depth-1:0];

	always @(posedge clk) begin
		if (weA)
			mem[addressA] = data_inA;
		//As usual, we always read out irrespective of we, because read is not destructive
		data_outB = mem[addressB];
	end

	//FPGA synth doesn't support initial. [TODO] find how to initialize FPGA RAMs
	`ifdef SIM
		integer i;
		initial begin
	    // for weight memory, initialize it to glorot normal distribution with mu = 0, sigma = sqrt[2/(fi+fo)]
        // Marsaglia and Bray method to generate the random number following Gaussian distribution
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


module parallel_simple_dual_port_mem #(
	parameter purpose=1,
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16
)(	
	input clk,
	input reset,
	input [z-1:0] weA,
	input [$clog2(depth)-1:0] addressA [z-1:0],
	input [$clog2(depth)-1:0] addressB [z-1:0],
	input signed [width-1:0] data_inA [z-1:0],
	output signed [width-1:0] data_outB [z-1:0]
);

	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i++) begin: parallel_sdp_mem
		simple_dual_port_memory #(
			.purpose(purpose),
			.depth(depth),
			.width(width)
		) sdpmem (
			.clk,
			.reset,
			.addressA(addressA[gv_i]),
			.weA(weA[gv_i]),
			.data_inA(data_inA[gv_i]),
			.addressB(addressB[gv_i]),
			.data_outB(data_outB[gv_i])
		);
	end
	endgenerate
endmodule



module true_dual_port_memory #(
	parameter depth = 2,
	parameter width = 16
)(
	input clk,
	input reset,
	input weA,
	input weB,
	input [$clog2(depth)-1:0] addressA,
	input [$clog2(depth)-1:0] addressB,
	input signed [width-1:0] data_inA,
	input signed [width-1:0] data_inB,
	output logic signed [width-1:0] data_outA,
	output logic signed [width-1:0] data_outB
);

	logic signed [width-1:0] mem [depth-1:0];

	always @(posedge clk) begin
		if (weA)
			mem[addressA] = data_inA;
		if (weB)
			mem[addressB] = data_inB;
		//As usual, we always read out irrespective of we, because read is not destructive
		data_outA = mem[addressA];
		data_outB = mem[addressB];
	end

	//FPGA synth doesn't support initial. [TODO] find how to initialize FPGA RAMs
	`ifdef SIM
		integer i;
		initial begin
			for (i = 0; i < depth; i = i + 1) begin
				mem[i] = 0;
			end
			data_outA = 0;
			data_outB = 0;
		end
	`endif
endmodule

//set of identical dual port memory modules, each clocked by same clk. 1 whole set like this is a single collection
module parallel_true_dual_port_mem #(
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16
)(	
	input clk,
	input reset,
	input [z-1:0] weA,
	input [z-1:0] weB,
	input [$clog2(depth)-1:0] addressA [z-1:0],
	input [$clog2(depth)-1:0] addressB [z-1:0],
	input signed [width-1:0] data_inA [z-1:0],
	input signed [width-1:0] data_inB [z-1:0],
	output signed [width-1:0] data_outA [z-1:0],
	output signed [width-1:0] data_outB [z-1:0]
);

	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i++) begin: parallel_tdpmem
		true_dual_port_memory #(
			.depth(depth),
			.width(width)
		) tdpmem (
			.clk,
			.reset,
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
module true_dual_port_mem_collection #(	
	parameter collection = 5,
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16
)(
	input clk,
	input reset,
	input [z-1:0] weA [collection-1:0],
	input [z-1:0] weB [collection-1:0],
	input [$clog2(depth)-1:0] addressA [collection-1:0] [z-1:0],
	input [$clog2(depth)-1:0] addressB [collection-1:0] [z-1:0],
	input signed [width-1:0] data_inA [collection-1:0] [z-1:0],
	input signed [width-1:0] data_inB [collection-1:0] [z-1:0],
	output signed [width-1:0] data_outA [collection-1:0] [z-1:0],
	output signed [width-1:0] data_outB [collection-1:0] [z-1:0]
);

	genvar gv_i;	
	generate for (gv_i = 0; gv_i<collection; gv_i++) begin: tdpmem_collection
		parallel_true_dual_port_mem #(
			.z(z), 
			.width(width), 
			.depth(depth)
		) ptdp_mem (
			.clk,
			.reset,
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
