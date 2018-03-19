// THIS MODULE DEFINES THE 3 DIFFERENT TYPES OF LAYERS - INPUT, HIDDEN AND OUTPUT
`timescale 1ns/100ps

/* Notes:
*	coll is at all collections level. All state machine signals are at collection level. Memory input output data is also at collection level
*	mem is at 1 collection, i.e. z memories level. This is usually obtained from passing collection level through a collection-choosing MUX
*	None of the above words implies single value level
*	Variables marked as FF, BP, UP without the prefix r or w (i.e. _BP_, not _rBP_) means input or output to processors
*	act_in in input layer means data is width_in bits as opposed to width bits
*/


module input_layer_block #(
	parameter p = 16,
	parameter fo = 2,
	parameter fi = 4,
	parameter z = 8,
	parameter L = 3, //Total no. of layers in network
	localparam collection = 2*L-1, //size of AM and AMp collection
	
	parameter width_in = 8, //input data width
	parameter width = 12,
	parameter int_bits = 3,
	localparam frac_bits = width-int_bits-1,
	parameter actfn = 0, //activation function for junction 1
	
	parameter ec = 2,
	localparam cpc = p*fo/z + ec, //Total no. of clocks needed to finish processing this junction
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_z = (z==1) ? 1 : $clog2(z)
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk, //1 cycle_clk = cpc clks
	input [$clog2(frac_bits+2)-1:0] etapos, //See tb_DNN for description
	
	input [width_in-1:0] act_in_raw [z/fo-1:0], //No. of UNSIGNED activations coming per clock from external environment, each is width_in bits. z weights processed in 1 cycle, fo weights = 1 activation, hence z/fo
	input signed [width-1:0] del_in [z/fi-1:0], //No. of deln values coming per clock from next layer, each is width bits. z weights processed in 1 cycle, fi weights = 1 del, hence z/fi
	output signed [width-1:0] act_out [z/fi-1:0], //No. of actn values computed per clock and going to next layer, each is width bits. z weights processed in 1 cycle, fi weights = 1 act out, hence z/fi
	output signed [width-1:0] adot_out [z/fi-1:0] //Every act_out has associated adot_out
);

	//State machine IO:
	logic signed [width-1:0] act_in [z/fo-1:0]; //Convert act_in_raw from unsigned width_in to signed width
	logic [log_pbyz-1:0] act_coll_addr [collection-1:0] [z-1:0];
	logic [z-1:0] act_coll_we [collection-1:0];
	logic signed [width-1:0] act_coll_in [collection-1:0] [z-1:0];
	logic [$clog2(collection)-1:0] act_coll_rFF_pt, act_coll_rUP_pt;
	logic [log_z-1:0] muxsel [z-1:0]; //choose memory within collection
	
	//Weight and bias memories are lumped together. z WMs, z/fi BMs, together z+z/fi WBMs, each has p*fo/z elements, each having width bits
	//WBM controller outputs: 
	logic [(z+z/fi)-1:0] wb_mem_weA;
	logic [$clog2(p*fo/z)-1:0] wb_mem_addrA [(z+z/fi)-1:0], wb_mem_addrB [(z+z/fi)-1:0];

	// Managing collections and memories:
	logic signed [width-1:0] act_coll_out [collection-1:0] [z-1:0]; //act memory in/out
	logic signed [width-1:0] act_mem_rFF [z-1:0], act_mem_rUP [z-1:0];	//activation output after collection selected
	
	// Processor set IO:
	logic signed [width-1:0] act_FF_in [z-1:0], act_UP_in [z-1:0];
	logic signed [width-1:0] wt [z-1:0], wt_UP [z-1:0];	//old and new weights
	logic signed [width-1:0] bias [z/fi-1:0], bias_UP [z/fi-1:0]; //old and new biases
	logic signed [width-1:0] wtbias [z+z/fi-1:0], wtbias_UP [z+z/fi-1:0]; //combined weights and biases
	genvar gv_i;
	
	
	//Combine wtbias data, used for reading from and feeding to wbmem
	generate for (gv_i=0; gv_i<z; gv_i++) begin: combine_wt
		assign wt[gv_i] = wtbias[gv_i];
		assign wtbias_UP[gv_i] = wt_UP[gv_i];
	end for (gv_i=0; gv_i<z/fi; gv_i++) begin: combine_bias
		assign bias[gv_i] = wtbias[z+gv_i];
		assign wtbias_UP[z+gv_i] = bias_UP[gv_i];
	end
	endgenerate

	
	// Convert unsigned width_in bits act_in_raw to signed width bits act_in
	/* Take the example of MNIST:
		* Original inputs are in the range 0-1 with 8b precision. So width_in=8
		* These get multiplied by 256 to get 8b numbers in the range 0-255. This faciliates data feeding
		* In the RTL, these need to get converted back to original 0-1 range, and then to width bits with sign, int_bits and frac_bits (Eg: 1+5+10 = 16b)
		* Obviously the sign bit is always 0 and all the int_bits are 0 (since integer part is always 0) => Total (int_bits+1) 0s
		* The 1st 8 frac_bits are the 8b input data and remaining frac_bits are 0
	*/
	generate for (gv_i=0; gv_i<z/fo; gv_i++) begin: act_in_conversion
		if (width_in<=frac_bits) //this means the entire width_in bits of input data can fit in the frac_bits slot
			assign act_in[gv_i] = {{(int_bits+1){1'b0}}, act_in_raw[gv_i], {(frac_bits-width_in){1'b0}}};
		else //all width_in bits of input data cannot fit, so truncate it
			assign act_in[gv_i] = {{(int_bits+1){1'b0}}, act_in_raw[gv_i][width_in-1 -: frac_bits]};
	end
	endgenerate


// Input Layer State Machine (L=1): 
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value
	state 3: cycle counter = 3, read out the 2nd clock value, write the 1st value in del mem
	...
	state n-3: cycle counter = n-3, read out the n-2 clock value, write the n-4 value in del mem 
	state n-2: cycle counter = n-2, write the n-3 value in del mem 
	state n-1: cycle counter = n-1, write the n-2 value in del mem
*/
	input_layer_state_machine #(	
		.width(width),
		.p(p),
		.fo(fo),
		.z(z), 
		.L(L),
		.ec(ec),
		.cpc(cpc)
	) input_layer_state_machine (
		.clk,
		.reset,
		.cycle_index,
		.cycle_clk,
		.act_in,
		.act_coll_addr,
		.act_coll_we,
		.act_coll_in,
		.act_coll_rFF_pt_final(act_coll_rFF_pt),
		.act_coll_rUP_pt_final(act_coll_rUP_pt),
		.muxsel_final(muxsel)
	);

	
// Weight and Bias Memory Controller
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value, write the 1st value in act mem
	state 3: cycle counter = 3, read out the 2nd clock value, write the 2nd value in act mem
*/
	wb_mem_ctr #(
		.p(p),
		.fo(fo),
	 	.z(z+z/fi),
	 	.ec(ec),
	 	.cpc(cpc)
	) input_layer_wbmem_ctr (
		.clk,
		.cycle_index,
		.reset, 
		.weA(wb_mem_weA),
		.r_addr(wb_mem_addrB),
		.w_addr(wb_mem_addrA)
	);


// Memories
	mem_collection #( //AMp collections
		.collection(collection),
		.z(z),
		.depth(p/z),
		.width(width)
	) input_AMp_coll (
		.clk,
		.reset,
		.address(act_coll_addr),
		.we(act_coll_we),
		.data_in(act_coll_in),
		.data_out(act_coll_out)
	);

	parallel_simple_dual_port_mem #( //WBM. Port A used for writing, port B for reading
		.purpose(1), 
		.width(width), 
		.depth(p*fo/z), 
		.z(z+z/fi)
	) input_wb_mem (
		.clk,
		.reset,
		.weA(wb_mem_weA),
		.addressA(wb_mem_addrA),
		.data_inA(wtbias_UP), //Input data to port A are the updated weight and bias values
		.addressB(wb_mem_addrB),
		.data_outB(wtbias) //Output data from port B are the read out existing weight and bias values
	);


// Collection to memories
	generate for (gv_i=0; gv_i<z; gv_i++) begin: act_colltomem
		assign act_mem_rFF[gv_i] = act_coll_out[act_coll_rFF_pt][gv_i];
		assign act_mem_rUP[gv_i] = act_coll_out[act_coll_rUP_pt][gv_i];
	end
	endgenerate

// Memories to single memory: MUXes
	mux_set #(
		.width(width),
		.N(z),
		.M(z)
	) rFF_mux (
		.in(act_mem_rFF),
		.sel(muxsel),
		.out(act_FF_in)
	);

	mux_set #(
		.width(width),
		.N(z),
		.M(z)
	) rUP_mux (
		.in(act_mem_rUP),
		.sel(muxsel),
		.out(act_UP_in)
	);


// Processor Sets
	FF_processor_set #(
	 	.fi(fi), 
	 	.z(z), 
	 	.width(width),
		.int_bits(int_bits), 
		.actfn(actfn)
	) input_FF_processor (
		.clk,
		.act_in(act_FF_in),
		.wt,
		.bias,
		.act_out,
		.adot_out
	);

	UP_processor_set #(
		.fi(fi), 
	 	.z(z), 
	 	.width(width),
		.int_bits(int_bits)
	) input_UP_processor (
		.etapos,
		.act_in(act_UP_in),
		.del_in,
		.wt,
		.bias,
		.wt_UP,
		.bias_UP
	);
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

module hidden_layer_block #(
	parameter p = 8,
	parameter fo = 2,
	parameter fi = 4,
	parameter z = 4,
	parameter L = 3,
	parameter h = 1, //h = 1 means first hidden layer, i.e. 2nd overall layer, and so on
	localparam collection = 2*(L-h) - 1, //No. of AM and ADM collections. Note that no. of DM collections is always 2

	parameter width = 12, 
	parameter int_bits = 3,
	localparam frac_bits = width-int_bits-1,
	parameter actfn = 0, //If this is the final junction, this should NOT be 1 (relu)
	
	parameter ec = 2,
	localparam cpc = p*fo/z + ec,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_z = (z==1) ? 1 : $clog2(z)
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk,
	input [$clog2(frac_bits+2)-1:0] etapos,
	
	input signed [width-1:0] act_in [z/fo-1:0], //from prev
	input signed [width-1:0] adot_in [z/fo-1:0], //from prev
	input signed [width-1:0] del_in [z/fi-1:0], //from next
	output signed [width-1:0] act_out [z/fi-1:0], //to next
	output signed [width-1:0] adot_out [z/fi-1:0], //to next
	output signed [width-1:0] del_out [z/fo-1:0] //to prev
);

	// State machine IO:
	logic [log_pbyz-1:0] act_coll_addr [collection-1:0] [z-1:0];
	logic [z-1:0] act_coll_we [collection-1:0];
	logic signed [width-1:0] act_coll_in [collection-1:0] [z-1:0], adot_coll_in [collection-1:0] [z-1:0];
	logic [$clog2(collection)-1:0] act_coll_rFF_pt, act_coll_rUP_pt; //AMp collection select signals for reading in FF and UP
	logic [log_z-1:0] muxsel [z-1:0]; //choose memory within collection
	
	logic [log_pbyz-1:0] del_coll_addrA [1:0] [z-1:0], del_coll_addrB [1:0] [z-1:0];
	logic [z-1:0] del_coll_weA [1:0], del_coll_weB [1:0];
	logic signed [width-1:0] del_coll_partial_inB [1:0] [z-1:0]; //DMp write back data	
	logic del_coll_rBP_pt; //DMp collection select signal for reading for previous BP. Negation of this is used for writing current BP
	logic [$clog2(cpc)-1:0] cycle_index_delay;
	
	// Weight and bias memories are lumped together. z WMs, z/fi BMs, together z+z/fi WBMs, each has p*fo/z elements, each having width bits
	// WBM controller outputs: 
	logic [(z+z/fi)-1:0] wb_mem_weA;
	logic [$clog2(p*fo/z)-1:0] wb_mem_addrA [(z+z/fi)-1:0], wb_mem_addrB [(z+z/fi)-1:0];

	// Managing collections and memories:
	logic signed [width-1:0] act_coll_out [collection-1:0] [z-1:0], adot_coll_out [collection-1:0] [z-1:0]; //AM and AMp coll in/out
	logic signed [width-1:0] del_coll_inA [1:0] [z-1:0], del_coll_inB [1:0] [z-1:0]; //DMp in/out
	
	logic signed [width-1:0] act_mem_rFF [z-1:0], act_mem_rUP [z-1:0];	//AMp output after collection selected
	logic signed [width-1:0] adot_mem_rBP [z-1:0], del_mem_rBP [z-1:0]; //ADMp and DMp outputs after collection selected, for previous layer BP
	logic signed [width-1:0] del_mem_rBP_fo_partitioned [z/fo-1:0][fo-1:0]; //For feeding to MUX
	logic signed [width-1:0] del_mem_partial_rBP [z-1:0], del_mem_partial_BP [z-1:0]; //DMp after collection selected and after re-ordering, for current layer BP
	logic signed [width-1:0] del_mem_partial_BP_repeated [1:0] [z-1:0]; //for feeding to mem
	
	// Processor set IO:
	logic signed [width-1:0] act_FF_in [z-1:0], act_UP_in [z-1:0], adot_BP_in [z-1:0];
	logic signed [width-1:0] wt [z-1:0], wt_UP [z-1:0];	//old and new weights
	logic signed [width-1:0] bias [z/fi-1:0], bias_UP [z/fi-1:0]; //old and new biases
	logic signed [width-1:0] wtbias [z+z/fi-1:0], wtbias_UP [z+z/fi-1:0]; //combined weights and biases
	logic signed [width-1:0] del_partial_BP_in [z-1:0], del_BP_out [z-1:0]; //partial del in/out for BP_processor
	genvar gv_i, gv_j;
		
		
	//Combine wtbias data, used for reading from and feeding to wbmem
	generate for (gv_i=0; gv_i<z; gv_i++) begin: combine_wt
		assign wt[gv_i] = wtbias[gv_i];
		assign wtbias_UP[gv_i] = wt_UP[gv_i];
	end for (gv_i=0; gv_i<z/fi; gv_i++) begin: combine_bias
		assign bias[gv_i] = wtbias[z+gv_i];
		assign wtbias_UP[z+gv_i] = bias_UP[gv_i];
	end
	endgenerate
	
	//Duplicate del_mem_partial_BP, used for feeding to DM
	generate for (gv_i=0; gv_i<2; gv_i++) begin: combine_dmpBP_coll
		for (gv_j=0; gv_j<z; gv_j++) begin: combine_dmpBP_z
			assign del_mem_partial_BP_repeated[gv_i][gv_j] = del_mem_partial_BP[gv_j];
		end
	end
	endgenerate


// Hidden Layer State Machine
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value
	state 3: cycle counter = 3, read out the 2nd clock value, write the 1st value in del mem
	...
	state n-3: cycle counter = n-3, read out the n-2 clock value, write the n-4 value in del mem 
	state n-2: cycle counter = n-2, write the n-3 value in del mem 
	state n-1: cycle counter = n-1, write the n-2 value in del mem */
	hidden_layer_state_machine #(	
		.width(width),
		.p(p),
		.fo(fo), 
		.z(z), 
		.L(L),
		.h(h),
		.ec(ec),
		.cpc(cpc)
	) hidden_layer_state_machine (
		.clk,
		.reset,
		.cycle_index,
		.cycle_clk,
		.act_in,
		.adot_in,
		.act_coll_addr,
		.act_coll_we,
		.act_coll_in,
		.adot_coll_in, 
		.del_coll_addrA,
		.del_coll_weA,
		.del_coll_addrB,
		.del_coll_weB,
		.del_coll_partial_inB,
		.act_coll_rFF_pt_final(act_coll_rFF_pt),
		.act_coll_rUP_pt_final(act_coll_rUP_pt),
		.del_coll_rBP_pt,
		.cycle_index_delay,
		.muxsel_final(muxsel)
	);

// Weight and Bias Memory Controller
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value, write the 1st value in act mem
	state 3: cycle counter = 3, read out the 2nd clock value, write the 2nd value in act mem */
	wb_mem_ctr #(
		.p(p),
		.fo(fo), 
	 	.z(z+z/fi), 
	 	.ec(ec),
	 	.cpc(cpc)
	) hidden_layer_wbmem_ctr (
		.clk,
		.reset,
		.cycle_index,
		.weA(wb_mem_weA),
		.r_addr(wb_mem_addrB),
		.w_addr(wb_mem_addrA)
	);


// Memories
	/*  act and ADMp have exactly same memory behavior, i.e. same number of collections and sizes
		Both get written into from previous layer when FF is getting computed for current layer. This is done in collection w_pt (internal to hidden_layer_state_machine)
		Both are read from collection act_coll_rUP_pt. Act values compute Update, while adot values compute BP of previous layer
		Only difference is that act is read one more time from collection act_coll_rFF_pt, used to compute FF of next layer. For this reason, do not concatenate act and adot into same memory
		Concatenation can be done, but will make code more complex
	*/
	mem_collection #(
		.collection(collection), 
		.z(z),
		.depth(p/z), 
		.width(width)
	) hidden_AMp_coll (
		.clk,
		.reset,
		.address(act_coll_addr), 
		.we(act_coll_we),
		.data_in(act_coll_in),
		.data_out(act_coll_out)
	);

	mem_collection #(
		.collection(collection), 
		.width(width), 
		.depth(p/z), 
		.z(z)
	) hidden_ADMp_coll (
		.clk,
		.reset, 
		.we(act_coll_we),
		.address(act_coll_addr), 
		.data_in(adot_coll_in),
		.data_out(adot_coll_out)
	);
	
	true_dual_port_mem_collection #( //For detailed DMp behavior, refer to memory_ctr file
		.collection(2), 
		.width(width), 
		.depth(p/z), 
		.z(z)
	) hidden_DMp_coll (
		.clk,
		.reset,
		.weA(del_coll_weA),
		.addressA(del_coll_addrA),
		.data_inA(del_mem_partial_BP_repeated), //Write back replicated value just to make vector widths match. In reality, 1 of the write enables is always 0, so nothing is written
		.data_outA(del_coll_inA), 
		.weB(del_coll_weB),
		.addressB(del_coll_addrB),
		.data_inB(del_coll_partial_inB),
		.data_outB(del_coll_inB)
	);

	parallel_simple_dual_port_mem #(
		.purpose(h+1), 
		.width(width), 
		.depth(p*fo/z), 
		.z(z+z/fi)
	) hidden_wb_mem (
		.clk, 
		.reset,
		.weA(wb_mem_weA),
		.addressA(wb_mem_addrA),
		.data_inA(wtbias_UP), //Input data to port B are the updated weight and bias values
		.addressB(wb_mem_addrB),
		.data_outB(wtbias) //Output data from port A are the read out existing weight and bias values
	);


// Processor Sets
	FF_processor_set #(
	 	.fi(fi), 
	 	.z(z),
	 	.width(width),
		.int_bits(int_bits), 
		.actfn(actfn) //should NOT be 1 = ReLU
	) hidden_FF_processor (
		.clk,
		.act_in(act_FF_in),
		.wt,
		.bias,
		.act_out,
		.adot_out
	);

	UP_processor_set #(
		.fi(fi),
	 	.z(z),
	 	.width(width),
		.int_bits(int_bits)
	) hidden_UP_processor (
		.etapos,
		.act_in(act_UP_in),
		.del_in,
		.wt,
		.bias,
		.wt_UP,
		.bias_UP
	);

	BP_processor_set #(
		.fi(fi),
	 	.z(z), 
	 	.width(width), 
		.int_bits(int_bits)
	) hidden_BP_processor (
		.del_in,
		.adot_in(adot_BP_in),
		.wt,
		.partial_del_out(del_partial_BP_in),
		.del_out(del_BP_out)
	);


// Collection to memories
	generate for (gv_i=0; gv_i<z; gv_i++) begin: colltomem
		assign act_mem_rFF[gv_i] = act_coll_out[act_coll_rFF_pt][gv_i];
		assign act_mem_rUP[gv_i] = act_coll_out[act_coll_rUP_pt][gv_i];
		assign adot_mem_rBP[gv_i] = adot_coll_out[act_coll_rUP_pt][gv_i]; //Note that ADMp for BP also uses act_coll_rUP_pt, same as what was used in AMp for UP
		assign del_mem_partial_rBP[gv_i] = del_coll_inB[~del_coll_rBP_pt][gv_i]; //select DMp collection for current BP
		assign del_mem_rBP[gv_i] = del_coll_inA[del_coll_rBP_pt][gv_i]; //select DMp collection for previous BP
	end
	endgenerate


// Memories to single memory: MUXes
	mux_set #(
		.width(width),
		.N(z),
		.M(z)
	) act_rFF_muxset (
		.in(act_mem_rFF),
		.sel(muxsel),
		.out(act_FF_in)
	);

	mux_set #(
		.width(width),
		.N(z),
		.M(z)
	) act_rUP_muxset (
		.in(act_mem_rUP),
		.sel(muxsel),
		.out(act_UP_in)
	);

	mux_set #(
		.width(width),
		.N(z),
		.M(z)
	) adot_rBP_muxset (
		.in(adot_mem_rBP),
		.sel(muxsel),
		.out(adot_BP_in)
	);

	mux_set #( //Interleaver mux set for read out from BP
		.width(width),
		.N(z),
		.M(z)
	) del_rBP_muxset (
		.in(del_mem_partial_rBP),
		.sel(muxsel),
		.out(del_partial_BP_in)
	);

	mux_set #( //De-Interleaver mux set for write back to BP
		.width(width),
		.N(z),
		.M(z)
	) del_wBP_muxset (
		.in(del_BP_out),
		.sel(muxsel),
		.out(del_mem_partial_BP)
	);

	generate for (gv_i=0; gv_i<z/fo; gv_i++) begin: del_out_gen
		if (fo>1) begin
			for (gv_j=0; gv_j<fo; gv_j++) begin: partition_del_mem_rBP
				assign del_mem_rBP_fo_partitioned[gv_i][gv_j] = del_mem_rBP[gv_i*fo+gv_j];
			end
			mux #(
				.width(width), // This mux is to segment prev mux values into cpc-ec chunks and feed them sequentially to prev layer
				.N(fo)
			) del_out_gen (
				.in(del_mem_rBP_fo_partitioned[gv_i]),
				.sel(cycle_index_delay[$clog2(fo)-1:0]),
				.out(del_out[gv_i])
			);
		end else begin //no mux required since del_out and del_mem_rBP are now both width*z bits
			assign del_out[gv_i] = del_mem_rBP[gv_i];
		end
	end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

module output_layer_block #(
	parameter p = 4, // No. of neurons in output layer. This is denoted as p since we deal with the imaginary junction between last layer and the layer after it
	parameter zbyfi = 1, //No. of neurons getting calculated per clock
	parameter L = 3,
	parameter width = 16,
	parameter int_bits = 5,
	localparam frac_bits = width-int_bits-1,
	parameter costfn = 1, //0 for quadcost, 1 for xentcost
	parameter ec = 2,
	localparam cpc = p/zbyfi + ec
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk,
	input signed [width-1:0] act_in [zbyfi-1:0], //from prev
	input signed [width-1:0] adot_in [zbyfi-1:0], //from prev
	// [TODO] adot_in is only used for quadcost. If xentcost is always used, this can be dispensed with, but may lead to significant code revision
	input [zbyfi-1:0] ans_in, //ideal outputs from beginning
	output signed [width-1:0] del_out [zbyfi-1:0], //to prev
	output [zbyfi-1:0] ans_out //ideal outputs at end. Simply delayed version of ideal outputs from beginning
);

	logic [$clog2(p/zbyfi)-1:0] del_coll_addr [1:0] [zbyfi-1:0];
	logic [zbyfi-1:0] del_coll_we [1:0];
	logic signed [width-1:0] del [zbyfi-1:0]; //computed del value, to be written to DMp
	logic signed [width-1:0] del_coll_in [1:0] [zbyfi-1:0], del_coll_out [1:0] [zbyfi-1:0];
	logic del_coll_rBP_pt; //DMp collection select signal
	logic signed [width-1:0] actans_diff [zbyfi-1:0]; //just what it says. Used in cost calculation
	

// Output Layer State Machine (L=L):
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value
	state 3: cycle counter = 3, read out the 2nd clock value, write the 1st value in act mem
	... */
	output_layer_state_machine #(
		.width(width),
		.p(p),
		.zbyfi(zbyfi), 
		.ec(ec),
		.cpc(cpc)
	) output_layer_state_machine (
		.clk,
		.reset,
		.cycle_index,
		.cycle_clk,
		.del_in(del),
		.del_coll_addr,
		.del_coll_we, 
		.del_coll_in,
		.del_coll_rBP_pt
	);


// Memories
	mem_collection #(
		.collection(2), 
		.width(width), 
		.depth(p/zbyfi), 
		.z(zbyfi)
	) output_DMp_coll (
		.clk, 
		.reset,
		.we(del_coll_we),
		.address(del_coll_addr), 
		.data_in(del_coll_in),
		.data_out(del_coll_out)
	);


// Calculate cost (note that ideal outputs are given at beginning and need to propagate, hence the shift register)
	shift_reg #( //Shift register for ideal outputs y from input layer to output layer
		.width(zbyfi),
		.depth(cpc*(L-1))
	) sr_idealoutputs (
		.clk,
		.reset,
		.d(ans_in),
		.q(ans_out)
	);
		
	costterm_set #(
		.z(zbyfi), 
		.width(width),
		.int_bits(int_bits)
	) costterms (
		.a(act_in),
		.y(ans_out),
		.c(actans_diff)
	);

	//Calculate del, which goes to state machine, from where it goes to DMp
	genvar gv_i;
	generate for (gv_i=0; gv_i<zbyfi; gv_i++) begin: cost_gen
		if (costfn==0) begin //quadcost
			multiplier #( //calculate del by multiplying actans_diff with sigmoid prime
				.width(width),
				.int_bits(int_bits)
			) quadcost_mul (
				.a(actans_diff[gv_i]),
				.b(adot_in[gv_i]),
				.p(del[gv_i])
			);
		end else if (costfn==1) begin //xentcost
			assign del[gv_i] = actans_diff[gv_i]; //del is just act minus ans
		end
	end
	endgenerate


// Collection to memories
	generate for (gv_i=0; gv_i<zbyfi; gv_i++) begin: del_colltomem
		assign del_out[gv_i] = del_coll_out[del_coll_rBP_pt][gv_i]; //choose collection and output chosen del value to previous layer
	end
	endgenerate
endmodule
