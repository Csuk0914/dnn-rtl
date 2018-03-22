`timescale 1ns/100ps

`define NOUT 10 //Number of outputs AS IN DATASET
`define TC 12544 //Training cases to be considered in 1 epoch (12544 is a multiple of total bits in 1 input = 768x8)
`define TTC 10*`TC //Total training cases over all epochs

module DNN_top #(
	parameter width_in = 8,
	parameter width = 10,
	parameter int_bits = 2,
	parameter L = 3,
	
	parameter [31:0] n [0:L-1] = '{1024, 64, 64}, //No. of neurons in every layer
	parameter [31:0] fo [0:L-2] = '{8, 4},//Fanout of all layers except for output
	parameter [31:0] fi [0:L-2]  = '{128, 4}, //Fanin of all layers except for input
	parameter [31:0] z [0:L-2]  = '{128, 4}, //Degree of parallelism of all junctions. No. of junctions = L-1
	parameter [31:0] actfn [0:L-2] = '{0,0}, //Activation function for all junctions. 0 = sigmoid, 1 = relu
	parameter costfn = 1, //Cost function for output layer. 0 = quadcost, 1 = xentcost
	
	localparam frac_bits = width-int_bits-1,
	localparam cpc =  n[0] * fo[0] / z[0] + 2
)(
	input [width_in*z[0]/fo[0]-1:0] act0, //No. of input activations coming into input layer per clock, each having width_in bits
	input clk,
	input reset,
	output cycle_clk,
	output [$clog2(cpc)-1:0] cycle_index,
	output [z[L-2]/fi[L-2]-1:0] ansL, //ideal output (ans0 after going through all layers)
	output [n[L-1]-1:0] actL_alln //Actual output [Eg: 4/4=1 output neuron processed per clock] of ALL output neurons
);

	logic [z[L-2]/fi[L-2]-1:0] ans0; //No. of ideal outputs coming into input layer per clock
	logic [`NOUT-1:0] ans_mem; //ideal output
	logic [$clog2(`TC)-1:0] sel_tc = '0; //MUX select to choose training case each block cycle
	logic [$clog2(cpc-2)-1:0] sel_network; //MUX select to choose which input/output pair to feed to network within a block cycle
	logic [n[L-1]-1:0] ans0_tc; //Complete 1b ideal output for 1 training case, i.e. No. of output neurons x 1 x 1

	DNN #(
		.width(width), 
		.width_in(width_in),
		.int_bits(int_bits),
		.L(L), 
		.actfn(actfn),
		.costfn(costfn),
		.n(n),
		.fo(fo), 
		.fi(fi), 
		.z(z)
	) DNN (
		.act0(act0),
		.ans0(ans0), 
		.etapos0(4), 
		.clk(clk),
		.reset(reset),
		.cycle_clk(cycle_clk),
		.cycle_index(cycle_index),
		.ansL(ansL),
		.actL_alln(actL_alln)
	);

 	//ideal out mem
	idealout_singleport_mem #(
		.depth(`TC),
		.width(width)
	) ideal_out_mem (
		.clk(clk),
		.reset(reset),
		.address(sel_tc),
		.we(1'b0),
		.data_in({width{1'b0}}), //doesn't matter because we is always 0
		.data_out(ans_mem)
	);


	/*** Training cases Pre-Processing ***/
	assign sel_network = cycle_index[$clog2(cpc-2)-1:0]-2;
	/* cycle_index goes from 0-17, so its 4 LSB go from 0 to cpc-3 then 0 to 1
	* But nothing happens in the last 2 cycles since pipeline delay is 2
	* So take values of cycle_index from 0-15 and subtract 2 to make its 4 LSB go from 14-15, then 0-13
	* Note that the jumbled order isn't important as long as all inputs from 0-15 are fed */
	
	always @(posedge cycle_clk) begin
		if(!reset) begin
			sel_tc <= (sel_tc == `TC-1)? 0 : sel_tc + 1;
		end else begin
			sel_tc <= 0;
		end
	end
	
	
	/*** ideal out input logic ***/
	genvar gv_i;
	generate for (gv_i = 0; gv_i<n[L-1]; gv_i = gv_i + 1)
	begin: ideal_out_input
		assign ans0_tc[gv_i] = (gv_i<`NOUT) ? ans_mem[gv_i] : 0; //assign unused output neurons to idealout=0
	end
	endgenerate
	
	mux #( //Choose the required no. of ideal outputs for feeding to DNN
		.width(z[L-2]/fi[L-2]), 
		.N(n[L-1]*fi[L-2]/z[L-2]) //This is basically cpc-2 of the last junction
	) mux_idealoutput_feednetwork (
		ans0_tc, sel_network, ans0);

endmodule
