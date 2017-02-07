// Sparse interleaved neural network
// Created by Yinan Shao
// Edits by Sourya Dey

`timescale 1ns/100ps

// Depending on the no. of hidden layers desired, mark only 1 of the following as 1, others as 0
// Total no. of layers (L) = No. of hidden layers + 2
`define No_hidden_layer 0
`define hidden_layer_1 1
`define hidden_layer_2 0
// [todo] NEED to include ifdef for conditional compile of hidden layers. Is this one-hot??

module DNN #(
	parameter width = 16, //Bit width
	parameter width_in = 8, //input data width, i.e. no. of bits each input neuron can take in
	parameter int_bits = 5, //no. of integer bits
	parameter frac_bits = 10, //no. of fractional part bits
	parameter L = 3, //Total no. of layers (including input and output)
	// Parameter arrays need to be [31:0] for compilation
	parameter [31:0] fo [0:L-2] = '{2, 2}, //Fanout of all layers except for output
	parameter [31:0] fi [0:L-2]  = '{4, 4}, //Fanin of all layers except for input
	parameter [31:0] z [0:L-2]  = '{8, 4}, //Degree of parallelism of all junctions. No. of junctions = L-1
	parameter [31:0] n [0:L-1] = '{16, 8, 4}, //No. of neurons in every layer
	//parameter eta = `eta, //eta is NOT a parameter any more. See input section for details
	//parameter lamda = 1, //L2 regularization
	parameter cost_type = 1, //0 for quadcost, 1 for xentcost
	parameter maxactL_pos_width = (z[L-2]/fi[L-2]==1) ? 1 : $clog2(z[L-2]/fi[L-2]),
	parameter cpc =  n[0] * fo[0] / z[0] + 2	//clocks per cycle block = Weights/parallelism. 2 extra needed because FF is 3 stage operation
	//Same cpc in different junctions is fine, cpc has to be a (power of 2) + 2
	// [todo future] ADD support for different cpc
)(
	input [width_in*z[0]/fo[0]-1:0] a_in, //Load activations from outside. z[0] weights processed together in first junction => z[0]/fo[0] activations together
	input [z[L-2]/fi[L-2]-1:0] y_in, //Load ideal outputs from outside. z[L-2] weights processed together in last junction => z[L-2]/fi[L-2] ideal outputs together, each is 1b 
	input [width-1:0] eta_in, //learning rate
	// Note that eta is an input, so each training sample can have its own eta. However, all the LAYERS HAVE THE SAME eta for a particular sample
	// By making eta an input, the problem of random weight updates after reset is solved, because each eta is introduced with input data
	input clk,
	input reset, //active high
	output [z[L-2]/fi[L-2]-1:0] y_out, //ideal output (y_in after going through all layers) only for the current z neurons (UNLIKE a_out_alln)
	output reg [n[L-1]-1:0] a_out_alln = 0 //Actual output [Eg: 4/4=1 output neuron processed per clock] for ALL OUTPUT NEURONS
);

	//wire [z[L-2]/fi[L-2]-1:0] a_out; //output from layer_block every clk
	wire cycle_clk;
	wire [$clog2(cpc)-1:0] cycle_index; //Bits to hold cycle number [Eg: 32 weights, z=8 means 32/8+2 = 6 cycles, so cycle_index is 3b]

	/* Treating all the hidden layers as a black box, following are its I/O:
			act1, sp1 are 'inputs' from input layer to black box
			actL, spL are 'outputs' from black box to output layer
			dL is 'input' from output layer to black box
	`		d1 is 'output' from black box to input layer
	So these signals remain same regardless of no. of hidden layers */
	wire [width*z[0]/fi[0]-1:0] act1, sp1, d1; //z[0]/fi[0] is the no. of neurons processed in 1 cycle at the input of the black box, i.e. 1st hidden layer
	wire [width*z[L-2]/fi[L-2]-1:0] actL, spL, dL; //z[L-2]/fi[L-2] is the no. of neurons processed in 1 cycle in the last layer, i.e. output of the black box
	wire [width-1:0] eta1, eta2; //eta is same for all layers, but timestamps are different. eta1 is a delayed version of eta2, see below
	
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
		.clk(clk), .reset(reset), .cycle_index(cycle_index), .cycle_clk(cycle_clk), .eta(eta1), //input control signals
		.act0(a_in), .d1(d1), //input data flow: a_in from outside, d1 from next layer [Eg: d1 is 16b x 2 values since 2 neurons from next layer send it. Basically deln]
		.act1(act1), .sp1(sp1) //output data flow: act1 and sp1 to next layer [Eg: each is 16b x 2 values,since 2 neurons in the next layer get processed at a time. Basically actn]
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
		.clk(clk), .reset(reset), .cycle_index(cycle_index), .cycle_clk(cycle_clk),  .eta(eta2), //input control signals
		.actin(act1), .spin(sp1), .din(dL), //input data flow
		.actout(actL), .spout(spL), .dout(d1) //output data flow
	);
	
	output_layer_block #(
		.p(n[L-1]), 
		.z(z[L-2]/fi[L-2]), //Notice the different format for value of z in output layer
		.width(width),
		.int_bits(int_bits),
		.frac_bits(frac_bits),
		.L(L),
		.cost_type(cost_type)
	) output_layer_block (
		.clk(clk), .reset(reset), .cycle_index(cycle_index), .cycle_clk(cycle_clk), //input control signals
		.actL(actL), .spL(spL), .y(y_in), 	//input data flow [Eg: 16b x 1 value (for 1 neuron).] y_in is input entering fist layer. It goes to last layer through a shift register
		.deltaL(dL), .yL(y_out) //output data flow. dL goes to previous hidden layer, yL goes outside
	);

	wire [width-1:0] maxactL, final_maxactL;
	reg [width-1:0] stored_maxactL;
	wire [maxactL_pos_width-1:0] maxactL_pos;
	reg [$clog2(n[L-1])-1:0] stored_maxactL_pos;
	wire maxactL_singlepos;
	max_finder_set #(.width(width),.N(z[L-2]/fi[L-2])) mfs_actL (.in(actL),.out(maxactL),.pos(maxactL_pos));
	max_finder #(.width(width)) mf_actstored (.a(maxactL),.b(stored_maxactL),.out(final_maxactL),.pos(maxactL_singlepos));
	always @(posedge clk) begin
		if (cycle_index>1) begin //Get chunks of y_out and actL from z/fi output neurons for cpc-2 clocks => Total z/fi*(n*fi/z) = n = No. of output neurons
			stored_maxactL = final_maxactL; //This is the final_maxactL just generated from the new actL values. This line behaves like a DFF
			if (z[L-2]/fi[L-2]>1) begin
				//y_out_alln[z[L-2]/fi[L-2]*(cycle_index-2) +: z[L-2]/fi[L-2]-1] = y_out;
				if (maxactL_singlepos==0) begin
					stored_maxactL_pos[$clog2(n[L-1])-1:$clog2(z[L-2]/fi[L-2])] = cycle_index-2;
					stored_maxactL_pos[$clog2(z[L-2]/fi[L-2])-1:0] = maxactL_pos;
				end //else retain previous value of stored_maxactL_pos
			end
			else begin //if only 1 output neuron gets computed every clk
				//y_out_alln[cycle_index-2] = y_out;
				stored_maxactL_pos = (maxactL_singlepos==0) ? (cycle_index-2) : stored_maxactL_pos;
				/* here maxactL_pos is trivially 0 and carries no information
				since z[L-2]/fi[L-2] = 1, index of current output neuron = cycle_index-2
				if condition is true, then current neuron is max value, so store cycle_index-2
				if condition is false, as usual, retain previous value of stored_maxactL_pos */ 
			end
		end
	end
	always @(posedge cycle_clk) begin
		a_out_alln = {n[L-1]{1'b0}};
		a_out_alln[stored_maxactL_pos] = 1'b1;
		stored_maxactL = {1'b1,{(width-1){1'b0}}}; //most negative value possible
		stored_maxactL_pos = {$clog2(n[L-1]){1'b0}}; //reset to all 0
	end
		

//eta shift register
	shift_reg #( //2nd junction gets updated first - L block cycles after input is fed
		.width(width), 
		.depth(L)
	) eta_SR1 (
		.clk(cycle_clk), 
		.reset(reset), 
		.data_in(eta_in), 
		.data_out(eta2));
	
	shift_reg #( //1st junction gets updated 1 block cycle after 2nd (using same eta)
		.width(width), 
		.depth(1)
	) eta_SR2 (
		.clk(cycle_clk), 
		.reset(reset), 
		.data_in(eta2), 
		.data_out(eta1));	
endmodule

/*integer cycle = 0;
	always @(posedge cycle_clk)
	if (!reset)
		cycle = cycle + 1; */
