// THIS MODULE DEFINES THE 3 DIFFERENT TYPES OF LAYERS - INPUT, HIDDEN AND OUTPUT
`timescale 1ns/100ps


/* Notes:
*	coll is at all collections level. All state machine signals are at collection level. Memory input output data is also at collection level
*	mem is at 1 collection, i.e. z memories level. This is usually obtained from passing collection level through a collection-choosing MUX
*	None of the above words implies single value level
*	Variables marked as FF, BP, UP without the prefix r or w (i.e. _BP_, not _rBP_) means input or output to processors
*	act_in in input layer means data is width_in bits as opposed to width bits
*/


module hidden_layer_block #(
	parameter p = 8,
	parameter z = 4,
	parameter fi = 4,
	parameter fo = 2,
	parameter L = 2,
	parameter h = 1, //h = 1 means first hidden layer, i.e. 2nd overall layer, and so on
	parameter actfn = 0, //If this is the final junction, this should NOT be 1 (relu)
	parameter width = 16, 
	parameter int_bits = 5, //No. of bits in integer part. Needed for all processors
	localparam frac_bits = width-int_bits-1, //No. of bits in fractional part. Needed for UP_processor
	localparam collection = 2 * (L-h) - 1, //No. of AM and sp collections. Note that no. of DM collections is always 2
	localparam cpc = p/z*fo+2,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_z = (z==1) ? 1 : $clog2(z)
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk,
	input [$clog2(frac_bits+2)-1:0] etapos, //Learning rate
	input [width*z/fo-1:0] act_in, //from prev
	input [width*z/fo-1:0] adot_in, //from prev
	input [width*z/fi-1:0] del_in, //from next
	output [width*z/fi-1:0] act_out, //to next
	output [width*z/fi-1:0] adot_out, //to next
	output [width*z/fo-1:0] del_out //to prev
);

// State machine outputs
	logic [collection*z*log_pbyz-1:0] act_coll_addr;	//AMp collection address
	logic [collection*z-1:0] act_coll_we;	//AMp collection write enable
	logic [2*z*log_pbyz-1:0] del_coll_addrA, del_coll_addrB; //DMp collection address
	logic [2*z-1:0] del_coll_weA, del_coll_weB; //DMp collection write enable
	logic [width*2*z-1:0] del_coll_partial_inB; //DMp write back data
	logic [$clog2(collection)-1:0] act_coll_rFF_pt, act_coll_rUP_pt; //AMp collection select signals for reading in FF and UP
	logic del_coll_rBP_pt; //DMp collection select signal for reading for previous BP. Negation of this is used for writing current BP
	logic [log_z*z-1:0] muxsel; //For interleavers
	logic [$clog2(cpc)-1:0] cycle_index_delay;
	
// Weight and bias memories are lumped together. z WMs, z/fi BMs, together z+z/fi WBMs, each has p*fo/z elements, each having width bits
// WBM controller outputs: 
	logic [(z+z/fi)-1:0] wb_mem_weA;
	logic [(z+z/fi)*$clog2(p*fo/z)-1:0] wb_mem_addrA, wb_mem_addrB;	//weight and bias memory address

// Datapath signals: MUXes, memories, processor sets
	logic [width*z-1:0] act_FF_in, act_UP_in, adot_BP_in; //width bit act values for processor set usage. Note that they are already extended to width bits, unlike input layer
	logic [width*z-1:0] wt, wt_UP;	//old and new weights
	logic [width*z/fi-1:0] bias, bias_UP;	//old and new biases
	logic [width*collection*z-1:0] act_coll_in, act_coll_out; //AMp in/out
	logic [width*z-1:0] act_mem_rFF, act_mem_rUP; //activation output after collection selected
	logic [width*collection*z-1:0] adot_coll_in, adot_coll_out; //SMp in/out
	logic [width*z-1:0] adot_mem_rBP;	//sp output after collection selected
	logic [width*z-1:0] del_mem_rBP;	//del after collection selected for previous layer BP
	logic [width*z-1:0] del_mem_partial_rBP; //del after collection selected to BP_processor for current layer BP
	logic [width*z-1:0] del_partial_BP_in, del_BP_out; //partial del in/out for BP_processor
	logic [width*z*2-1:0] del_coll_inA, del_coll_inB;	//DMp in/out
	logic [width*z-1:0] del_mem_partial_BP; //partial del after re-order to del memory


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
		.fo(fo), 
		.p(p), 
		.z(z), 
		.L(L),
		.h(h),
		.cpc(cpc), 
		.width(width)
	) hidden_layer_state_machine (
		.clk(clk),
		.reset(reset),
		.cycle_index(cycle_index),
		.cycle_clk(cycle_clk),
		.act_in(act_in),
		.adot_in(adot_in),
		.act_coll_addr(act_coll_addr),
		.act_coll_we(act_coll_we),
		.act_coll_in(act_coll_in),
		.adot_coll_in(adot_coll_in), 
		.del_coll_addrA(del_coll_addrA),
		.del_coll_weA(del_coll_weA),
		.del_coll_addrB(del_coll_addrB),
		.del_coll_weB(del_coll_weB),
		.del_coll_partial_inB(del_coll_partial_inB),
		.muxsel_final(muxsel),
		.act_coll_rFF_pt_final(act_coll_rFF_pt),
		.act_coll_rUP_pt_final(act_coll_rUP_pt),
		.del_coll_rBP_pt(del_coll_rBP_pt),
		.cycle_index_delay2(cycle_index_delay)
	);

// Weight and Bias Memory Controller
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value, write the 1st value in act mem
	state 3: cycle counter = 3, read out the 2nd clock value, write the 2nd value in act mem */
	wb_mem_ctr #(
		.fo(fo), 
		.p(p),
		.z(z+z/fi), 
		.cpc(cpc)
	) hidden_layer_wbmem_ctr (
		.clk(clk),
		.cycle_index(cycle_index),
		.reset(reset), 
		.weA(wb_mem_weA),
		.r_addr(wb_mem_addrB),
		.w_addr(wb_mem_addrA)
	);


// Memories
	// act and sp have exactly same memory behavior, i.e. same number of collections and sizes
	// Both get written into from previous layer when FF is getting computed for current layer. This is done in collection w_pt (internal to hidden_layer_state_machine)
	// Both are read from collection act_coll_rUP_pt. Act values compute Update, while sp values compute BP of previous layer
	// Only difference is that act is read one more time from collection act_coll_rFF_pt, used to compute FF of next layer. For this reason, do not concatenate act and sp into same memory
	// Concatenation can be done, but will make code more complex
	collection_singleport_mem #(
		.collection(collection), 
		.width(width), 
		.depth(p/z), 
		.z(z)
	) hidden_AMp_coll (
		.clk(clk), 
		.we_package(act_coll_we),
		.addr_package(act_coll_addr), 
		.data_in_package(act_coll_in),
		.data_out_package(act_coll_out)
	);

	collection_singleport_mem #(
		.collection(collection), 
		.width(width), 
		.depth(p/z), 
		.z(z)
	) hidden_ADMp_coll (
		.clk(clk), 
		.we_package(act_coll_we),
		.addr_package(act_coll_addr), 
		.data_in_package(adot_coll_in),
		.data_out_package(adot_coll_out)
	);

	parallel_simple_dualport_mem #(
		.purpose(2), 
		.width(width), 
		.depth(p*fo/z), 
		.z(z+z/fi)
	) jn12_wb_mem (
		.clk(clk), 
		.weA_package(wb_mem_weA),
		.addressA_package(wb_mem_addrA),
		.data_inA_package({wt_UP, bias_UP}),
		.addressB_package(wb_mem_addrB),
		.data_outB_package({wt, bias})
	);

	collection_true_dualport_mem #( //For detailed DMp behavior, refer to memory_ctr file
		.collection(2), 
		.width(width), 
		.depth(p/z), 
		.z(z)
	) del_mem (
		.clk(clk), 
		.weA_package(del_coll_weA),
		.addrA_package(del_coll_addrA),
		.data_inA_package({del_mem_partial_BP, del_mem_partial_BP}), //Write back replicated value just to make vector widths match. In reality, 1 of the write enables is always 0, so nothing is written
		.data_outA_package(del_coll_inA), 
		.weB_package(del_coll_weB),
		.addrB_package(del_coll_addrB),
		.data_inB_package(del_coll_partial_inB),
		.data_outB_package(del_coll_inB)
	);


// Processor Sets
	FF_processor_set #(
	 	.fi(fi), 
	 	.z(z), 
	 	.width(width),
		.int_bits(int_bits), 
		.actfn(actfn)
	) FF_processor (
		.clk(clk),
		.act_in_package(act_FF_in),
		.wt_package(wt),
		.bias_package(bias),
		.act_out_package(act_out),
		.adot_out_package(adot_out)
	);

	UP_processor_set #(
		.fi(fi), 
	 	.z(z), 
	 	.width(width),
		.int_bits(int_bits)
	) UP_processor (
		.etapos(etapos), 
		.del_in_package(del_in),
		.wt_package(wt),
		.bias_package(bias),
		.act_in_package(act_UP_in),
		.wt_UP_package(wt_UP),
		.bias_UP_package(bias_UP)
	);

	BP_processor_set #(
		.fi(fi), 
	 	.z(z), 
	 	.width(width), 
		.int_bits(int_bits)
	) BP_processor (
		.del_in_package(del_in),
		.adot_out_package(adot_BP_in),
		.wt_package(wt),
		.partial_del_out_package(del_partial_BP_in),
		.del_out_package(del_BP_out)
	);


// MUXes
	mux #(.width(width*z), //select AMp collection for FF
		.N(collection)) FFcoll_sel
		(act_coll_out, act_coll_rFF_pt, act_mem_rFF);

	mux #(.width(width*z), //select AMp collection for UP
		.N(collection)) UPcoll_sel
		(act_coll_out, act_coll_rUP_pt, act_mem_rUP);

	mux_set #(.width(width), //set of MUXes to choose SRAM inside a collection for FF
		.N(z)) rFF_mux
		(act_mem_rFF, muxsel, act_FF_in);

	mux_set #(.width(width), //set of MUXes to choose SRAM inside a collection for UP
		.N(z)) rUP_mux
		(act_mem_rUP, muxsel, act_UP_in);

	mux #(.width(width*z), //select SMp collection for BP. Note that it uses act_coll_rUP_pt, same as what was used in AMp
		.N(collection)) spcoll_sel
		(adot_coll_out, act_coll_rUP_pt, adot_mem_rBP);

	mux_set #(.width(width), //set of MUXes to choose SRAM inside a collection for BP
		.N(z)) adot_rBP_mux
		(adot_mem_rBP, muxsel, adot_BP_in);

	mux #(.width(width*z), //select DMp collection for current BP
		.N(2)) currentBPcoll_sel
		(del_coll_inB, ~del_coll_rBP_pt, del_mem_partial_rBP); //del_coll_inB is output of all collections. del_mem_partial_rBP is output of chosen colleciton

	mux_set #(.width(width), //Interleaver mux set for read out from BP
		.N(z)) del_w_inter
		(del_mem_partial_rBP, muxsel, del_partial_BP_in);

	mux_set #(.width(width), //De-Interleaver mux set for write back to BP
		.N(z)) del_partial_mux
		(del_BP_out, muxsel, del_mem_partial_BP);

	mux #(.width(width*z), //select DMp collecton for previous BP
		.N(2)) previousBPcoll_sel
		(del_coll_inA, del_coll_rBP_pt, del_mem_rBP);

	generate
		if (fo>1)
			mux #(.width(width*z/fo), // This mux is to segment prev mux values into cpc-2 chunks and feed them sequentially to prev layer
				.N(fo)) del_r_sel
				(del_mem_rBP, cycle_index_delay[$clog2(fo)-1:0], del_out);
		else //no mux required since del_out and del_mem_rBP are now both width*z bits
			assign del_out = del_mem_rBP;
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

module input_layer_block #(
	parameter p = 16, //No. of neurons in this input layer
	parameter z = 8, //Degree of parallelism
	parameter fi = 4, //Fan-in of neurons in next layer
	parameter fo = 2, //Fan-out of neurons in this input layer
	parameter L = 3, //Total no. of layers in network
	parameter actfn = 0, //If this is the final junction, this should NOT be 1 (relu)
	parameter width_in = 8, //input data width
	parameter width = 16, //Bit width
	parameter int_bits = 5, //No. of bits in integer part
	localparam frac_bits = width-int_bits-1, //No. of bits in fractional part
	localparam collection = 2 * L - 1, //size of AM and AMp collection
	localparam cpc = p*fo/z + 2, //Total no. of clocks needed to finish processing this junction
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_z = (z==1) ? 1 : $clog2(z)
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index, //Index of clock cycle
	input cycle_clk, //1 cycle_clk = cpc clks
	input [$clog2(frac_bits+2)-1:0] etapos, //See tb_DNN for description
	input [width_in*z/fo-1:0] act_in, //No. of activations coming per clock from external environment, each is width_in bits. z weights processed in 1 cycle, fo weights = 1 activation, hence z/fo
	input [width*z/fi-1:0] del_in, //No. of deln values coming per clock from next layer, each is width bits. z weights processed in 1 cycle, fi weights = 1 del, hence z/fi
	output [width*z/fi-1:0] act_out, //No. of actn values computed per clock and going to next layer, each is width bits. z weights processed in 1 cycle, fi weights = 1 act out, hence z/fi
	output [width*z/fi-1:0] adot_out //Every act_out has associated adot_out
);

//State machine outputs:
	logic [log_z*z-1:0] muxsel; //choose memory within collection
	logic [collection*z*log_pbyz-1:0] act_coll_addr;	//act memory collection address
	logic [collection*z-1:0] act_coll_we;	//act memory collection write enable signal
	logic [$clog2(collection)-1:0] act_coll_rFF_pt, act_coll_rUP_pt; //act memory collection selected signal for FF and UP reads
	
//Weight and bias memories are lumped together. z WMs, z/fi BMs, together z+z/fi WBMs, each has p*fo/z elements, each having width bits
//WBM controller outputs: 
	logic [(z+z/fi)-1:0] wb_mem_weA;
	logic [(z+z/fi)*$clog2(p*fo/z)-1:0] wb_mem_addrA, wb_mem_addrB;	//WBM address

// Datapath signals: MUXes, memories, processor sets
	logic [width_in*z-1:0] act_in_FF_in, act_in_UP_in; //width_in bit activation values
	logic [width*z-1:0] act_FF_in, act_UP_in; //convert to width bits act values for processor set usage
	logic [width*z-1:0] wt, wt_UP;	//old and new weights
	logic [width*z/fi-1:0] bias, bias_UP; //old and new biases
	logic [width_in*collection*z-1:0] act_coll_in, act_coll_out; //act memory in/out
	logic [width_in*z-1:0] act_mem_rFF, act_mem_rUP;	//activation output after collection selected


// Input Layer State Machine (L=1): 
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value
	state 3: cycle counter = 3, read out the 2nd clock value, write the 1st value in del mem
	...
	state n-3: cycle counter = n-3, read out the n-2 clock value, write the n-4 value in del mem 
	state n-2: cycle counter = n-2, write the n-3 value in del mem 
	state n-1: cycle counter = n-1, write the n-2 value in del mem */
	input_layer_state_machine #(	
		.fo(fo), 
		.p(p), 
		.z(z), 
		.L(L), 
		.cpc(cpc), 
		.width(width_in)
	) input_layer_state_machine (
		.clk(clk),
		.reset(reset),
		.cycle_index(cycle_index),
		.cycle_clk(cycle_clk),
		.act_in(act_in),
		.act_coll_addr(act_coll_addr),
		.act_coll_we(act_coll_we),
		.muxsel_final(muxsel), 
		.act_coll_in(act_coll_in),
		.act_coll_rFF_pt_final(act_coll_rFF_pt),
		.act_coll_rUP_pt_final(act_coll_rUP_pt)
	);
	
// Weight and Bias Memory Controller
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value, write the 1st value in act mem
	state 3: cycle counter = 3, read out the 2nd clock value, write the 2nd value in act mem */
	wb_mem_ctr #(
		.fo(fo), 
		.p(p),
		.z(z+z/fi), 
		.cpc(cpc)
	) input_layer_wbmem_ctr (
		.clk(clk),
		.cycle_index(cycle_index),
		.reset(reset), 
		.weA(wb_mem_weA),
		.r_addr(wb_mem_addrB),
		.w_addr(wb_mem_addrA)
	);


// Memories
	collection_singleport_mem #( //AMp collections
		.collection(collection), 
		.width(width_in),
		.depth(p/z), 
		.z(z)
	) input_AMp_coll (
		.clk(clk), 
		.we_package(act_coll_we),
		.addr_package(act_coll_addr), 
		.data_in_package(act_coll_in),
		.data_out_package(act_coll_out)
	);

	parallel_simple_dualport_mem #( //WBM. Just 1 collection. Port A used for readel_ing, port B for writing
		.purpose(1), 
		.width(width), 
		.depth(p*fo/z), 
		.z(z+z/fi)
	) jn01_wb_mem (
		.clk(clk), 
		.weA_package(wb_mem_weA),
		.addressA_package(wb_mem_addrA),
		.data_inA_package({wt_UP, bias_UP}),
		.addressB_package(wb_mem_addrB),
		.data_outB_package({wt, bias})
	);
			
	// Note that there is no DMp collection


// Processor Sets
	genvar gv_i;	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin: processor_in
	// [MAYBE] convert from width_in to width at beginning, as was done in attempted improvements
	/* Take the example of MNIST:
	* Original inputs are in the range 0-1 with 8b precision. So width_in=8
	* These get multiplied by 256 to get 8b numbers in the range 0-255. This faciliates data feeding
	* In the RTL, these need to get converted back to original 0-1 range, and then to width bits with int_bits and frac_bits (Eg: 1+5+10 = 16b)
	* Obviously the sign bit is always 0 and all the int_bits are 0 (since integer part is always 0) => Total (int_bits+1) 0s
	* The 1st 8 fract_bits are the 8b input data and remaining frac_bits are 0 */
		if (width_in<=frac_bits) begin //this means the entire width_in bits of input data can fit in the frac_bits slot
			assign act_FF_in[width*(gv_i+1)-1:width*gv_i] = {{(int_bits+1){1'b0}}, act_in_FF_in[width_in*(gv_i+1)-1:gv_i*width_in], {(frac_bits-width_in){1'b0}}};
			assign act_UP_in[width*(gv_i+1)-1:width*gv_i] = {{(int_bits+1){1'b0}}, act_in_UP_in[width_in*(gv_i+1)-1:gv_i*width_in], {(frac_bits-width_in){1'b0}}};
		end else begin //all width_in bits of input data cannot fit, so truncate it
			assign act_FF_in[width*(gv_i+1)-1:width*gv_i] = {{(int_bits+1){1'b0}}, act_in_FF_in[width_in*(gv_i+1)-1:gv_i*width_in+width_in-frac_bits]};
			assign act_UP_in[width*(gv_i+1)-1:width*gv_i] = {{(int_bits+1){1'b0}}, act_in_UP_in[width_in*(gv_i+1)-1:gv_i*width_in+width_in-frac_bits]};
		end
	end
	endgenerate
	
	FF_processor_set #(
	 	.fi(fi), 
	 	.z(z), 
	 	.width(width),
		.int_bits(int_bits),
		.actfn(actfn) //Change here - 0 for sigmoid, 1 for ReLU, etc
	) L0_FF_processor (
		.clk(clk),
		.act_in_package(act_FF_in),
		.wt_package(wt),
		.bias_package(bias),
		.act_out_package(act_out),
		.adot_out_package(adot_out)
	);

	UP_processor_set #(
		.fi(fi), 
	 	.z(z), 
	 	.width(width),
		.int_bits(int_bits)
	) L0_UP_processor (
		.etapos(etapos), 
		.del_in_package(del_in),
		.wt_package(wt),
		.bias_package(bias),
		.act_in_package(act_UP_in),
		.wt_UP_package(wt_UP),
		.bias_UP_package(bias_UP)
	);


// MUXes	
	mux #( //Select AM collection for FF
		.width(width_in*z), //Read out z activations, each is  width_in bits (since input is width_in bits)
		.N(collection)) FFcoll_sel
		(act_coll_out, act_coll_rFF_pt, act_mem_rFF);

	mux #( //Select AM collection for UP
		.width(width_in*z), 
		.N(collection)) UPcoll_sel
		(act_coll_out, act_coll_rUP_pt, act_mem_rUP);

	mux_set #(
		.width(width_in), //Within collection, select AM for FF
		.N(z)) rFF_mux
		(act_mem_rFF, muxsel, act_in_FF_in);

	mux_set #(.width(width_in), //Within collection, select AM for UP
		.N(z)) rUP_mux
		(act_mem_rUP, muxsel, act_in_UP_in);
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

module output_layer_block #(
	parameter p = 4, // No. of neurons in output layer. This is denoted as p since we deal with the imaginary junction between last layer and the layer after it
	parameter zbyfi = 1,
	parameter L = 3,
	parameter costfn = 1, //0 for quadcost, 1 for xentcost
	parameter width = 16,
	parameter int_bits = 5,
	localparam frac_bits = width-int_bits-1,
	localparam cpc = p/zbyfi + 2 //Since z = z_hidden/fi, cpc = p*fi/z_hidden = p/z
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk,
	input [width*zbyfi-1:0] act_in, //from prev
	input [width*zbyfi-1:0] adot_in, //from prev
	// [MAYBE] adot_in is only used for quadcost. If xentcost is always used, this can be dispensed with, but may lead to significant code revision
	input [zbyfi-1:0] ans_in, //ideal outputs from beginning
	output [width*zbyfi-1:0] del_out, //to prev
	//output [zbyfi-1:0] a_out, //actual computed outputs from whole neural network
	output [zbyfi-1:0] ans_out //ideal outputs at end. Simply delayed version of ideal outputs from beginning
);

//State Machine and cycle_index DFF outputs
	logic [2*zbyfi*$clog2(p/zbyfi)-1:0] del_coll_addr;	//all DMp addresses
	logic [2*zbyfi-1:0] del_coll_we; //all DMp write enable signal
	logic del_coll_rBP_pt; //DMp collection select signal
	logic [$clog2(cpc)-1:0] cycle_index_delay;
	
//Datapath signals: MUXes, memories, cost calculators
	logic [width*zbyfi-1:0] actans_diff; //just what it says. Used in cost calculation
	logic [width*zbyfi-1:0] del; //computed del value, to be written to DMp. This is input to state machine
	logic [width*2*zbyfi-1:0] del_coll_in, del_coll_out;	//del memory in/out


// Output Layer State Machine (L=L):
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value
	state 3: cycle counter = 3, read out the 2nd clock value, write the 1st value in act mem
	... */
	output_layer_state_machine #(	
		.p(p), 
		.zbyfi(zbyfi),
		.cpc(cpc), 
		.width(width)
	) output_layer_state_machine (
		.clk(clk),
		.reset(reset),
		.cycle_index(cycle_index),
		.cycle_clk(cycle_clk),
		.del_in(del),
		.del_coll_addr(del_coll_addr),
		.del_coll_we(del_coll_we), 
		.del_coll_in(del_coll_in),
		.del_coll_rBP_pt(del_coll_rBP_pt)
	);


// Memories
	collection_singleport_mem #(
		.collection(2), 
		.width(width), 
		.depth(p/zbyfi), 
		.z(zbyfi)
	) output_DMp_coll (
		.clk(clk), 
		.we_package(del_coll_we),
		.addr_package(del_coll_addr), 
		.data_in_package(del_coll_in),
		.data_out_package(del_coll_out)
	);


// Calculate cost (note that ideal outputs are given at beginning and need to propagate, hence the shift register)
	shift_reg #( //Shift register for ideal outputs y from input layer to output layer
		.width(zbyfi),
		.depth(cpc*(L-1))
	) sr_idealoutputs (
		.clk(clk),
		.reset(reset),
		.data_in(ans_in),
		.data_out(ans_out)
	);
		
	costterm_set #(
		.z(zbyfi), 
		.width(width),
		.int_bits(int_bits)
	) costterms (
		.a_set(act_in),
		.y_set(ans_out),
		.c_set(actans_diff)
	);

	//Calculate del, which goes to state machine, from where it goes to DMp
	genvar gv_i;
	generate if (costfn==0) begin //quadcost
		for (gv_i=0; gv_i<zbyfi; gv_i++) //calculate del by multiplying actans_diff with sigmoid prime
			multiplier #(.width(width), .int_bits(int_bits)) quadcost_mul (actans_diff[gv_i], adot_in[gv_i], del[gv_i]);
	end else if (costfn==1) begin //xentcost
		assign del = actans_diff; //del is just act minus ans
	end
	endgenerate


// Collection choosing MUX
	mux #(.width(width*zbyfi), 
		.N(2)) r_collection
		(del_coll_out, del_coll_rBP_pt, del_out); //choose collection and output chosen del value to previous layer
endmodule
