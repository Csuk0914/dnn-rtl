// Sparse interleaved neural network
// Yinan Shao, Sourya Dey

`timescale 1ns/100ps

//`define MULTIOUT //Uncomment this if z[L-2]/fi[L-2] > 1. Check tb params for z and fi

//[TODO] Add code for customizable no. of hidden layers

module DNN #( // Parameter arrays need to be [31:0] for compilation
	parameter width = 10, //Bit width
	parameter width_in = 8, //input data width, i.e. no. of bits each input neuron can take in
	parameter int_bits = 2, //no. of integer bits
	parameter frac_bits = width-int_bits-1, //no. of fractional part bits
	parameter L = 3, //Total no. of layers (including input and output)
	
	// FOR MNIST:
	parameter [31:0] fo [0:L-2] = '{8, 8}, //Fanout of all layers except for output
	parameter [31:0] fi [0:L-2]  = '{128, 32}, //Fanin of all layers except for input
	parameter [31:0] z [0:L-2]  = '{512, 32}, //Degree of parallelism of all junctions. No. of junctions = L-1
	parameter [31:0] n [0:L-1] = '{1024, 64, 16}, //No. of neurons in every layer
	
	// FOR SMALL TEST NETWORK:
	/*parameter [31:0] fo [0:L-2] = '{2, 2},
	parameter [31:0] fi [0:L-2]  = '{8, 8},
	parameter [31:0] z [0:L-2]  = '{32, 8},
	parameter [31:0] n [0:L-1] = '{64, 16, 4},*/
	
	//parameter eta = `eta, //eta is NOT a parameter any more. See input section for details
	//parameter lamda = 1, //L2 regularization
	localparam max_actL1_pos_width = (z[L-2]/fi[L-2]==1) ? 1 : $clog2(z[L-2]/fi[L-2]), //position of maximum neuron every clk cycle
	localparam cpc =  n[0] * fo[0] / z[0] + 2	//clocks per cycle block = Weights/parallelism. 2 extra needed because FF is 3 stage operation
	//Same cpc in different junctions is fine, cpc has to be a (power of 2) + 2
	// [TODO] ADD support for different cpc
)(
	input [width_in*z[0]/fo[0]-1:0] act0, //Load activations from outside. z[0] weights processed together in first junction => z[0]/fo[0] activations together
	input [z[L-2]/fi[L-2]-1:0] ans0, //Load ideal outputs from outside. z[L-2] weights processed together in last junction => z[L-2]/fi[L-2] ideal outputs together, each is 1b 
	input [$clog2(frac_bits+2)-1:0] etapos0, //see tb_DNN for description
	// Note that etapos is an input, so each training sample can have its own etapos. However, all the LAYERS HAVE THE SAME etapos for a particular sample
	// By making etapos an input, the problem of random weight updates after reset is solved, because each etapos is introduced with input data
	input clk,
	input reset, //active high
	output [z[L-2]/fi[L-2]-1:0] ansL, //ideal output (ans0 after going through all layers) only for the current z neurons (UNLIKE actL_alln)
	output reg [n[L-1]-1:0] actL_alln = 0, //Actual output [Eg: 4/4=1 output neuron processed per clock] for ALL OUTPUT NEURONS
	//wire [z[L-2]/fi[L-2]-1:0] actL1; //output from layer_block every clk
	output cycle_clk,
	output [$clog2(cpc)-1:0] cycle_index //Bits to hold cycle number [Eg: 32 weights, z=8 means 32/8+2 = 6 cycles, so cycle_index is 3b]
);

	
	/* Treating all the hidden layers as a black box, following are its I/O:
			act1, adot1 are 'inputs' from input layer to black box
			actL1, adotL1 are 'outputs' from black box to output layer
			delL1 is 'input' from output layer to black box
	`		del1 is 'output' from black box to input layer
	So these signals remain same regardless of no. of hidden layers */
	wire [width*z[0]/fi[0]-1:0] act1, adot1, del1; //z[0]/fi[0] is the no. of neurons processed in 1 cycle at the input of the black box, i.e. 1st hidden layer
	wire [width*z[L-2]/fi[L-2]-1:0] actL1, adotL1, delL1; //z[L-2]/fi[L-2] is the no. of neurons processed in 1 cycle in the last layer, i.e. output of the black box
	wire [$clog2(frac_bits+2)-1:0] etapos1, etaposL1; //etapos is same for all layers, but timestamps are different. etapos1 is a delayed version of etaposL1, see below
	
	cycle_block_counter #(
		.cpc(cpc)
	) cycle_counter (
		.clk(clk),
		.reset(reset),
		.cycle_clk(cycle_clk),
		.count(cycle_index)
	);


//the neuron network has 1 input layer, N hidden layer and one output layer. N = (0, 1, 2....)
//hidden layer number = L - 2
	input_layer_block #(
		.p(n[0]), 
		.n(n[1]), 
		.z(z[0]), 
		.fi(fi[0]), 
		.fo(fo[0]), 
		//.eta(eta), 
		//.lamda(lamda), 
		.width(width), 
		.width_in(width_in),
		.int_bits(int_bits),
		.frac_bits(frac_bits),
		.L(L)
	) input_layer_block (
		.clk(clk), .reset(reset), .cycle_index(cycle_index), .cycle_clk(cycle_clk), .etapos(etapos1), //input control signals
		.act_in(act0), .del_in(del1), //input data flow: act0 from outside, del1 from next layer [Eg: del1 is 16b x 2 values since 2 neurons from next layer send it. Basically deln]
		.act_out(act1), .adot_out(adot1) //output data flow: act1 and adot1 to next layer [Eg: each is 16b x 2 values,since 2 neurons in the next layer get processed at a time. Basically actn]
	);

	hidden_layer_block #(
		.p(n[1]), 
		.n(n[2]), 
		.z(z[1]), 
		.fi(fi[1]), 
		.fo(fo[1]), 
		//.eta(eta), 
		//.lamda(lamda), 
		.width(width),
		.int_bits(int_bits),
		.frac_bits(frac_bits),
		.L(L), 
		.h(1) //index of hidden layer
	) hidden_layer_block_1 (
		.clk(clk), .reset(reset), .cycle_index(cycle_index), .cycle_clk(cycle_clk),  .etapos(etaposL1), //input control signals
		.act_in(act1), .adot_in(adot1), .del_in(delL1), //input data flow
		.act_out(actL1), .adot_out(adotL1), .del_out(del1) //output data flow
	);
	
	output_layer_block #(
		.p(n[L-1]), 
		.z(z[L-2]/fi[L-2]), //Notice the different format for value of z in output layer
		.width(width),
		.int_bits(int_bits),
		.frac_bits(frac_bits),
		.L(L)
	) output_layer_block (
		.clk(clk), .reset(reset), .cycle_index(cycle_index), .cycle_clk(cycle_clk), //input control signals
		.act_in(actL1), .adot_in(adotL1), .ans_in(ans0), 	//input data flow [Eg: 16b x 1 value (for 1 neuron).] ans0 is input entering fist layer. It goes to last layer through a shift register
		.del_out(delL1), .ans_out(ansL) //output data flow. delL1 goes to previous hidden layer, yL goes outside
	);

	// Max act logic
	wire [width-1:0] max_actL1, //local max act every cycle
				     final_max_actL1; //global max act every cpc cycles
	reg [width-1:0] stored_max_actL1; //current global max act in the middle of a block cycle
	wire [max_actL1_pos_width-1:0] max_actL1_pos;
	reg [$clog2(n[L-1])-1:0] stored_max_actL1_pos;
	wire max_actL1_singlepos; //compares local with global

	// max_finder_set gets local max act and its pos from z[L-2]/fi[L-2] activations after every clk cycle
	// max_finder compares this max act with the stored global max act from previous cycles and outputs final max act after cpc cycles, i.e. max act from n[L-2] output neurons
	max_finder_set #(.width(width),.N(z[L-2]/fi[L-2])) mfs_actL1 (.in(actL1),.out(max_actL1),.pos(max_actL1_pos));
	max_finder #(.width(width)) mf_actstored (.a(max_actL1),.b(stored_max_actL1),.out(final_max_actL1),.pos(max_actL1_singlepos));
	// always @(posedge clk, posedge cycle_clk) begin
	// 	if (cycle_clk) begin //Assign 1 output to the max position and then reset variables
	// 		actL_alln = {n[L-1]{1'b0}};
	// 		actL_alln[stored_max_actL1_pos] = 1'b1;
	// 		stored_max_actL1 = {1'b1,{(width-1){1'b0}}}; //most negative value possible
	// 		stored_max_actL1_pos = {$clog2(n[L-1]){1'b0}}; //reset to all 0
	// 	end
	// 	else if (cycle_index>1) begin //1st 2 cycles are garbage
	// 		stored_max_actL1 = final_max_actL1; //This is the final_max_actL1 just generated from the new actL1 values. This line behaves like a DFF
	// 		`ifdef MULTIOUT 
	// 			//ansL_alln[z[L-2]/fi[L-2]*(cycle_index-2) +: z[L-2]/fi[L-2]-1] = ansL;
	// 			if (max_actL1_singlepos==0) begin
	// 				stored_max_actL1_pos[$clog2(n[L-1])-1:$clog2(z[L-2]/fi[L-2])] = cycle_index-2;
	// 				stored_max_actL1_pos[$clog2(z[L-2]/fi[L-2])-1:0] = max_actL1_pos;
	// 			end //else retain previous value of stored_max_actL1_pos
	// 		`else //if only 1 output neuron gets computed every clk
	// 			//ansL_alln[cycle_index-2] = ansL;
	// 			stored_max_actL1_pos = (max_actL1_singlepos==0) ? (cycle_index-2) : stored_max_actL1_pos;
	// 			/* here max_actL1_pos is trivially 0 and carries no information
	// 			since z[L-2]/fi[L-2] = 1, index of current output neuron = cycle_index-2
	// 			if condition is true, then current neuron is max value, so store cycle_index-2
	// 			if condition is false, as usual, retain previous value of stored_max_actL1_pos */
	// 		`endif
	// 	end
	// end
	
	always @(posedge clk) 
	begin
		if (cycle_index == cpc-1) 
		begin //Assign 1 output to the max position and then reset variables
			actL_alln <= {n[L-1]{1'b0}};
			actL_alln[stored_max_actL1_pos] <= 1'b1;
			stored_max_actL1 <= {1'b1,{(width-1){1'b0}}}; //most negative value possible
			stored_max_actL1_pos <= {$clog2(n[L-1]){1'b0}}; //reset to all 0
		end
		else if (cycle_index>1) 
		begin //1st 2 cycles are garbage
			stored_max_actL1 <= final_max_actL1; //This is the final_max_actL1 just generated from the new actL1 values. This line behaves like a DFF
			`ifdef MULTIOUT 
				//ansL_alln[z[L-2]/fi[L-2]*(cycle_index-2) +: z[L-2]/fi[L-2]-1] = ansL;
				if (max_actL1_singlepos==0) 
				begin
					stored_max_actL1_pos[$clog2(n[L-1])-1:$clog2(z[L-2]/fi[L-2])] <= cycle_index-2;
					stored_max_actL1_pos[$clog2(z[L-2]/fi[L-2])-1:0] <= max_actL1_pos;
				end //else retain previous value of stored_max_actL1_pos
			`else //if only 1 output neuron gets computed every clk
				//ansL_alln[cycle_index-2] = ansL;
				stored_max_actL1_pos <= (max_actL1_singlepos==0) ? (cycle_index-2) : stored_max_actL1_pos;
				/* here max_actL1_pos is trivially 0 and carries no information
				since z[L-2]/fi[L-2] = 1, index of current output neuron = cycle_index-2
				if condition is true, then current neuron is max value, so store cycle_index-2
				if condition is false, as usual, retain previous value of stored_max_actL1_pos */
			`endif
		end
	end

//etapos shift register
	shift_reg #( //2nd junction gets updated first - L block cycles after input is fed
		.width($clog2(frac_bits+2)), 
		.depth(L)
	) etapos_SRL1 (
		.clk(cycle_clk), 
		.reset(reset), 
		.data_in(etapos0), 
		.data_out(etaposL1));

	DFF_no_reset #( //1st junction gets updated 1 block cycle after 2nd (using same etapos)
		.width($clog2(frac_bits+2))
	) etapos_DFF (
		.clk(cycle_clk),
		//.reset(reset),
		.d(etaposL1),
		.q(etapos1)
	);
endmodule

/*integer cycle = 0;
	always @(posedge cycle_clk)
	if (!reset)
		cycle = cycle + 1; */

