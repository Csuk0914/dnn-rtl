// Top level module for whole DNN
// Yinan Shao, Sourya Dey, USC

`timescale 1ns/100ps
//[TODO] Add code for customizable no. of hidden layers

module DNN #(
	// Parameter arrays need to be [31:0] for compilation
	parameter width_in = 8, //input data width, i.e. no. of bits each input neuron can take in
	parameter width = 12, //Bit width
	parameter int_bits = 3, //no. of integer bits
	localparam frac_bits = width-int_bits-1, //no. of fractional bits
	
	parameter L = 3, //Total no. of layers (including input and output)
	parameter [31:0] actfn [0:L-2] = '{1,0}, //Activation function for all junctions. 0 = sigmoid, 1 = relu
	parameter costfn = 1, //Cost function for output layer. 0 = quadcost, 1 = xentcost
	parameter ec = 2, //Number of extra cycles in each block cycle (basically number of clock delays within proessing each input). 2 because FF needs 2 extra cycle - 1 for reading mems, 1 for computing act
	
	// FOR MNIST:
	parameter [31:0] n [0:L-1] = '{1024, 64, 64}, //No. of neurons in every layer
	parameter [31:0] fo [0:L-2] = '{8, 4}, //Fanout of all layers except for output
	parameter [31:0] fi [0:L-2]  = '{128, 4}, //Fanin of all layers except for input
	parameter [31:0] z [0:L-2]  = '{128, 4}, //Degree of parallelism of all junctions. No. of junctions = L-1
	
	// FOR SMALL TEST NETWORK:
	/*
	parameter [31:0] n [0:L-1] = '{64, 16, 4},
	parameter [31:0] fo [0:L-2] = '{2, 2},
	parameter [31:0] fi [0:L-2]  = '{8, 8},
	parameter [31:0] z [0:L-2]  = '{32, 8},
	*/
	
	localparam cpc =  n[0]*fo[0]/z[0] + ec,	//clocks per cycle block = Weights/parallelism + extra. [TODO] ADD support for different cpc
	localparam log_zLbyfiL = (z[L-2] == fi[L-2]) ? 1 : $clog2(z[L-2]/fi[L-2])
)(
	input clk,
	input reset, //active high
	input [$clog2(frac_bits+2)-1:0] etapos0, /*etapos = -log2(Eta)+1. Eg: If Eta=2^-4, etapos=5
		Min allowable value of Eta = 2^(-frac_bits) => Max value of etapos = frac_bits+1, which needs log2(frac_bits+2) bits to store (e.g. if frac_bits=7, then we need log(9)=4 bits to store the max value of 8 = 1000)
		Max allowable value of Eta = 1 => Min value of etapos = 1. So etapos is never 0
		Note that etapos is an input, so each training sample can have its own etapos. However, all the LAYERS HAVE THE SAME etapos for a particular sample
		By making etapos an input, the problem of random weight updates after reset is solved, because each etapos is introduced with input data
		eta can ONLY BE A POWER OF 2. If anything else, it is rounded down to a power of 2, e.g. 0.3 becomes 0.25
		[TODO] ADD support for arbitrary eta (needs modifying etapos logic) */
	input [width_in-1:0] act0 [z[0]/fo[0]-1:0], //Load activations from outside. z[0] weights processed together in first junction => z[0]/fo[0] activations together
	input [z[L-2]/fi[L-2]-1:0] ans0, //Load ideal outputs from outside. z[L-2] weights processed together in last junction => z[L-2]/fi[L-2] ideal outputs together, each is 1b 
	output [z[L-2]/fi[L-2]-1:0] ansL, //ideal output (ans0 after going through all layers) only for the current z neurons (UNLIKE actL_alln)
	output [n[L-1]-1:0] actL_alln //Actual output [Eg: 4/4=1 output neuron processed per clock] for ALL OUTPUT NEURONS
);

	//logic [z[L-2]/fi[L-2]-1:0] actL1; //output from layer_block every clk
	logic cycle_clk;
	logic [$clog2(cpc)-1:0] cycle_index; //Bits to hold cycle number [Eg: 32 weights, z=8, ec=2 means 32/8+2 = 6 cycles, so cycle_index is 3b]
	//IMPORTANT: effective cycle_index is a term used to denote all bits of cycle_index except for MSB

	/* Treating all the hidden layers as a black box, following are its I/O:
			act1, adot1 are 'inputs' from 1st junction to black box
			actL1, adotL1 are 'outputs' from black box to last junction
			delL1 is 'input' from last junction to black box
	`		del1 is 'output' from black box to 1st junction
	So these signals remain same regardless of no. of hidden layers */
	logic signed [width-1:0] act1 [z[0]/fi[0]-1:0], adot1 [z[0]/fi[0]-1:0], del1 [z[0]/fi[0]-1:0]; //z[0]/fi[0] is the no. of neurons processed in 1 cycle at the input of the black box, i.e. 1st hidden layer
	logic signed [width-1:0] actL1 [z[L-2]/fi[L-2]-1:0], adotL1 [z[L-2]/fi[L-2]-1:0], delL1 [z[L-2]/fi[L-2]-1:0]; //z[L-2]/fi[L-2] is the no. of neurons processed in 1 cycle in the last layer, i.e. output of the black box
	logic [$clog2(frac_bits+2)-1:0] etapos1, etaposL1; //etapos is same for all layers, but timestamps are different. etapos1 is a delayed version of etaposL1, see below
	
	cycle_block_counter #(
		.cpc(cpc)
	) cycle_block_counter (
		.clk,
		.reset,
		.cycle_clk,
		.count(cycle_index)
	);

	input_layer_block #(
		.p(n[0]), 
		.z(z[0]), 
		.fi(fi[0]), 
		.fo(fo[0]), 
		.L(L),
		.width(width), 
		.width_in(width_in),
		.int_bits(int_bits),
		.actfn(actfn[0]),
		.ec(ec)
	) input_layer (
		//input control signals
		.clk,
		.reset,
		.cycle_index,
		.cycle_clk,
		.etapos(etapos1),
		//input data flow: act0 from outside, del1 from next layer [Eg: del1 is 16b x 2 values since 2 neurons from next layer send it. Basically deln]
		.act_in_raw(act0),
		.del_in(del1),
		//output data flow: act1 and adot1 to next layer [Eg: each is 16b x 2 values,since 2 neurons in the next layer get processed at a time. Basically actn]
		.act_out(act1),
		.adot_out(adot1)
	);

	hidden_layer_block #(
		.p(n[1]), 
		.z(z[1]), 
		.fi(fi[1]), 
		.fo(fo[1]), 
		.L(L), 
		.h(1), //index of hidden layer
		.width(width),
		.int_bits(int_bits),
		.actfn(actfn[1]),
		.ec(ec)
	) hidden_layer_1 (
		//input control signals
		.clk,
		.reset,
		.cycle_index,
		.cycle_clk, 
		.etapos(etaposL1),
		//input data flow
		.act_in(act1),
		.adot_in(adot1),
		.del_in(delL1),
		//output data flow
		.act_out(actL1),
		.adot_out(adotL1),
		.del_out(del1) 
	);
	
	output_layer_block #(
		.p(n[L-1]), 
		.zbyfi(z[L-2]/fi[L-2]),
		.L(L),
		.width(width),
		.int_bits(int_bits),
		.costfn(costfn),
		.ec(ec)
	) output_layer (
		//input control signals
		.clk,
		.reset,
		.cycle_index,
		.cycle_clk,
		//input data flow [Eg: 16b x 1 value (for 1 neuron).] ans0 is input entering fist layer. It goes to last layer through a shift register 
		.act_in(actL1),
		.adot_in(adotL1),
		.ans_in(ans0), 
		//output data flow. delL1 goes to previous hidden layer, yL goes outside
		.del_out(delL1),
		.ans_out(ansL) 
	);

	// Max act logic
	logic signed [width-1:0] max_actL1, //local max act every cycle
						stored_max_actL1, //current global max act in the middle of a block cycle
						final_max_actL1; //global max act every cpc cycles
	logic [log_zLbyfiL-1:0] max_actL1_pos; //position of ideal max act every cycle
	logic [$clog2(n[L-1])-1:0] stored_max_actL1_pos; //position of global max act in the middle of a block cycle
	logic max_actL1_singlepos; //compares local with global

	// max_finder_set gets local max act and its pos from z[L-2]/fi[L-2] activations after every clk cycle
	// max_finder compares this max act with the stored global max act from previous cycles and outputs final max act after cpc cycles, i.e. max act from n[L-1] output neurons
	max_finder_set #(
		.width(width),
		.N(z[L-2]/fi[L-2]),
		.poswidth(log_zLbyfiL)
	) mfs_actL1 (
		.in(actL1),
		.out(max_actL1),
		.pos(max_actL1_pos)
	);
	max_finder #(
		.width(width)
	) mf_actstored (
		.a(max_actL1),
		.b(stored_max_actL1),
		.out(final_max_actL1),
		.pos(max_actL1_singlepos)
	);
	
	assign actL_alln = (cycle_index==cpc-1 || cycle_index==0) ? 1<<stored_max_actL1_pos : 0;
	
	always @(posedge clk) begin
		if (cycle_index == ec-1) begin //reset variables
			stored_max_actL1 <= {1'b1,{(width-1){1'b0}}}; //most negative value possible
			stored_max_actL1_pos <= 0; //all 0
		end
		/*else if (cycle_index==cpc-1)
			actL_alln = 1<<stored_max_actL1_pos;*/
		else if (cycle_index > ec-1) begin //1st ec cycles are garbage
			stored_max_actL1 <= final_max_actL1; //This is the final_max_actL1 just generated from the new actL1 values. This line behaves like a DFF
			if (z[L-2]/fi[L-2]>1) begin //>1 output neuron computed every clk
				if (max_actL1_singlepos==0)
					stored_max_actL1_pos <= {(cycle_index-ec),max_actL1_pos};
				//else retain previous value of stored_max_actL1_pos
			end else begin //only 1 output neuron computed every clk
				stored_max_actL1_pos <= (max_actL1_singlepos==0) ? (cycle_index-ec) : stored_max_actL1_pos;
				/* here max_actL1_pos is trivially 0 and carries no information
				since z[L-2]/fi[L-2] = 1, index of current output neuron = cycle_index-2
				if condition is true, then current neuron is max value, so store cycle_index-2
				if condition is false, as usual, retain previous value of stored_max_actL1_pos */
			end
		end
	end


//etapos shift register
	shift_reg #( //2nd junction gets updated first - L block cycles after input is fed
		.width($clog2(frac_bits+2)), 
		.depth(L)
	) etapos_SRL1 (
		.clk(cycle_clk), 
		.reset, 
		.d(etapos0), 
		.q(etaposL1));

	DFF #( //1st junction gets updated 1 block cycle after 2nd (using same etapos)
		.width($clog2(frac_bits+2))
	) etapos_DFF (
		.clk(cycle_clk),
		.reset,
		.d(etaposL1),
		.q(etapos1)
	);
endmodule
