`define NOUT 10 //Number of outputs AS IN DATASET
`define TC 12544 //Training cases to be considered in 1 epoch
`define TTC 10*`TC //Total training cases over all epochs

module DNN_top #(
	parameter width = 10,
	parameter width_in = 8,
	parameter int_bits = 2,
	parameter frac_bits = width-int_bits-1,
	parameter L = 3,
	parameter Eta = 2.0**(-1), //Should be a power of 2. Value between 2^(-frac_bits) and 1. DO NOT WRITE THIS AS 2**x, it doesn't work without 2.0
	//parameter lamda = 0.9, //weights are capped at absolute value = lamda*2**int_bits
	parameter [31:0] fo [0:L-2] = '{8, 4},//Fanout of all layers except for output
	parameter [31:0] fi [0:L-2]  = '{128, 4}, //Fanin of all layers except for input
	parameter [31:0] z [0:L-2]  = '{128, 4}, //Degree of parallelism of all junctions. No. of junctions = L-1
	parameter [31:0] n [0:L-1] = '{1024, 64, 64} //No. of neurons in every layer
)(
	input clk,
	input reset,
	input [width_in*z[0]/fo[0]-1:0] act0, //No. of input activations coming into input layer per clock, each having width_in bits
	output [z[L-2]/fi[L-2]-1:0] ansL, //ideal output (ans0 after going through all layers)
	output [n[L-1]-1:0] actL_alln, //Actual output [Eg: 4/4=1 output neuron processed per clock] of ALL output neurons
	output cycle_clk,
	output [$clog2(cpc)-1:0] cycle_index
);

	localparam cpc =  n[0] * fo[0] / z[0] + 2;

	wire [z[L-2]/fi[L-2]-1:0] ans0; //No. of ideal outputs coming into input layer per clock
	wire [`NOUT-1:0] ans_mem;//ideal output
	reg [$clog2(`TC)-1:0] sel_tc = 0; //MUX select to choose training case each block cycle
	wire [$clog2(cpc-2)-1:0] sel_network; //MUX select to choose which input/output pair to feed to network within a block cycle
	wire [n[L-1]-1:0] ans0_tc; //Complete 1b ideal output for 1 training case, i.e. No. of output neurons x 1 x 1

	DNN #(
		.width(width), 
		.width_in(width_in),
		.int_bits(int_bits),
		.frac_bits(frac_bits),
		.L(L), 
		.fo(fo), 
		.fi(fi), 
		.z(z), 
		.n(n)
		//.eta(eta), 
		//.lamda(lamda),
	) DNN (
		.act0(act0),
		.ans0(ans0), 
		.etapos0(2), 
		.clk(clk),
		.reset(reset),
		.ansL(ansL),
		.actL_alln(actL_alln),
		.cycle_clk(cycle_clk),
		.cycle_index(cycle_index)
	);

 	// BRAM for idear out
	ideal_out_mem ideal_out_mem(
		.clka(clk),
		.wea(1'b0),
		.addra(sel_tc),
		.dina(10'b0),
		.douta(ans_mem)
	);

	////////////////////////////////////////////////////////////////////////////////////
	// Training cases Pre-Processing
	////////////////////////////////////////////////////////////////////////////////////
	
	assign sel_network = cycle_index[$clog2(cpc-2)-1:0]-2;
	/* cycle_index goes from 0-17, so its 4 LSB go from 0 to cpc-3 then 0 to 1
	* But nothing happens in the last 2 cycles since pipeline delay is 2
	* So take values of cycle_index from 0-15 and subtract 2 to make its 4 LSB go from 14-15, then 0-13
	* Note that the jumbled order isn't important as long as all inputs from 0-15 are fed */
	always @(posedge cycle_clk) begin
		if(!reset) begin
			sel_tc <= (sel_tc == `TC-1)? 0 : sel_tc + 1;
		end
		else begin
			sel_tc <= 0;
		end
	end
	
	////////////////////////////////////////////////////////////////////////////////////
	// ideal out input logic
	////////////////////////////////////////////////////////////////////////////////////

	mux #( //Choose the required no. of ideal outputs for feeding to DNN
		.width(z[L-2]/fi[L-2]), 
		.N(n[L-1]*fi[L-2]/z[L-2]) //This is basically cpc-2 of the last junction
	) mux_idealoutput_feednetwork (
		ans0_tc, sel_network, ans0);

	genvar ideal_i;
	generate for (ideal_i = 0; ideal_i<n[L-1]; ideal_i = ideal_i + 1)
	begin: ideal_out_input
		assign ans0_tc[ideal_i] = (ideal_i<`NOUT)? ans_mem[ideal_i]:0;
	end
	endgenerate

endmodule