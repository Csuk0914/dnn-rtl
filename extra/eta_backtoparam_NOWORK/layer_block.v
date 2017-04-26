// THIS MODULE DEFINES THE 3 DIFFERENT TYPES OF LAYERS - INPUT, HIDDEN AND OUTPUT
`timescale 1ns/100ps

module input_layer_block #(
	parameter p = 16, //No. of neurons in this input layer
	parameter n = 8, //No. of neurons in following layer
	parameter z = 8, //Degree of parallelism
	parameter fi = 4, //Fan-in of neurons in next layer
	parameter fo = 2, //Fan-out of neurons in this input layer
	parameter eta = 4, //Learning rate
	//parameter lamda = 1, //Regularization parameter
	parameter width = 16, //Bit width
	parameter width_in = 8, //input data width
	parameter int_bits = 5, //No. of bits in integer part
	parameter frac_bits = 10, //No. of bits in fractional part
	parameter L = 2, //Total no. of layers in network
	parameter collection = 2 * L - 1, //size of AM collection
	parameter cpc = p*fo/z + 2 //Total no. of clocks needed to finish processing this junction
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index, //Index of clock cycle
	input cycle_clk, //1 cycle_clk = cpc clks
	//input signed [width-1:0] eta, //Learning rate
	input eta_en,
	input [width_in*z/fo-1:0] act0, //No. of activations coming per clock from external environment, each is width_in bits. z weights processed in 1 cycle, fo weights = 1 activation, hence z/fo
	input [width*z/fi-1:0] d1, //No. of deln values coming per clock from next layer, each is width bits. z weights processed in 1 cycle, fi weights = 1 delta, hence z/fi
	output [width*z/fi-1:0] act1, //No. of actn values computed per clock and going to next layer, each is width bits. z weights processed in 1 cycle, fi weights = 1 act out, hence z/fi
	output [width*z/fi-1:0] sp1 //Every act1 has associated sp1
);

//State machine outputs:
	wire [$clog2(z)*z-1:0] mux_sel;
	wire [collection*z*$clog2(p/z)-1:0] act0_addr;	//act memory collection address
	wire [collection*z-1:0] act_we;	//act memory collection write enable signal
	wire [$clog2(collection)-1:0] rFF_pt, rUP_pt; //act memory collection selected signal for FF and UP reads
	
//Weight and bias memories are lumped together. z WMs, z/fi BMs, together z+z/fi WBMs, each has p*fo/z elements, each having width bits
//WBM controller outputs: 
	wire [(z+z/fi)-1:0] wb_weA, wb_weB;	//WBM write enable signal. A and B because there are 2 ports
	wire [(z+z/fi)*$clog2(p*fo/z)-1:0] wb_addrA, wb_addrB;	//WBM address

// Datapath signals: MUXes, memories, processor sets
	wire [width_in*z-1:0] act0_FF, act0_UP; //width_in bit activation values
	wire [width*z-1:0] act0_FF_in, act0_UP_in; //convert to width bits act values for processor set usage
	wire [width*z-1:0] w, w_UP;	//old and new weights
	wire [width*z/fi-1:0] b, b_UP; //old and new biases
	wire [width_in*collection*z-1:0] act0_mem_in, act_mem_out; //act memory in/out
	wire [width_in*z-1:0] act_rFF_raw, act_rUP_raw;	//activation output after collection selected


// Input Layer State Machine (L=1): 
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value
	state 3: cycle counter = 3, read out the 2nd clock value, write the 1st value in delta mem
	...
	state n-3: cycle counter = n-3, read out the n-2 clock value, write the n-4 value in delta mem 
	state n-2: cycle counter = n-2, write the n-3 value in delta mem 
	state n-1: cycle counter = n-1, write the n-2 value in delta mem */
	input_layer_state_machine #(	
		.fo(fo), 
		.fi(fi), 
		.p(p), 
		.n(n), 
		.z(z), 
		.L(L), 
		.cpc(cpc), 
		.width(width_in), 
		.collection(collection)
	) input_layer_state_machine (
		.clk(clk),
		.reset(reset),
		.cycle_index(cycle_index),
		.cycle_clk(cycle_clk),
		.data_in(act0),
		.act_addr_package(act0_addr),
		.act_we_package(act_we),
		.actual_mux_sel(mux_sel), 
		.data_in_mem(act0_mem_in),
		.actual_rFF_pt(rFF_pt),
		.actual_rUP_pt(rUP_pt)
	);
	
// Weight and Bias Memory Controller
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value, write the 1st value in act mem
	state 3: cycle counter = 3, read out the 2nd clock value, write the 2nd value in act mem */
	w_mem_ctr #(
		.fo(fo), 
		.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z+z/fi), 
	 	.cpc(cpc)
	) input_layer_wbmem_ctr (
		.clk(clk),
		.cycle_index(cycle_index),
		.reset(reset), 
		.weA(wb_weA),
		.weB(wb_weB),
		.r_addr(wb_addrA),
		.w_addr(wb_addrB)
	);


// Memories
	mem_collection #( //AMp collections
		.collection(collection), 
		.width(width_in),
		.depth(p/z), 
		.z(z)
	) AMp_coll (
		.clk(clk), 
		.we_package(act_we),
		.addr_package(act0_addr), 
		.data_in_package(act0_mem_in),
		.data_out_package(act_mem_out)
	);

	dual_port_mem_collection #( //WBM. Just 1 collection. Port A used for reading, port B for writing
		.collection(1), 
		.width(width), 
		.depth(p*fo/z), 
		.z(z+z/fi), 
		.fi(fi), 
		.fo(fo)
	) wb_mem (
		.clk(clk), 
		.weA_package(wb_weA),
		.weB_package(wb_weB),
		.addrA_package(wb_addrA),
		.addrB_package(wb_addrB),
		// There is no data_inA_package
		.data_outA_package({w, b}), //Output data from port A are the read out existing weight and bias values
		.data_inB_package({w_UP, b_UP}) //Input data to port B are the updated weight and bias values
		// There is no data_outB_package
	);
			
	// Note that there is no DMp collection


// Processor Sets
	genvar gv_i;	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin: processor_in
	/* Take the example of MNIST:
	* Original inputs are in the range 0-1 with 8b precision. So width_in=8
	* These get multiplied by 256 to get 8b numbers in the range 0-255. This faciliates data feeding
	* In the RTL, these need to get converted back to original 0-1 range, and then to width bits with int_bits and frac_bits (Eg: 1+5+10 = 16b)
	* Obviously the sign bit is always 0 and all the int_bits are 0 (since integer part is always 0) => Total (int_bits+1) 0s
	* The 1st 8 fract_bits are the 8b input data and remaining frac_bits are 0 */
		if (width_in<=frac_bits) begin //this means the entire width_in bits of input data can fit in the frac_bits slot
			assign act0_FF_in[width*(gv_i+1)-1:width*gv_i] = {{(int_bits+1){1'b0}}, act0_FF[width_in*(gv_i+1)-1:gv_i*width_in], {(frac_bits-width_in){1'b0}}};
			assign act0_UP_in[width*(gv_i+1)-1:width*gv_i] = {{(int_bits+1){1'b0}}, act0_UP[width_in*(gv_i+1)-1:gv_i*width_in], {(frac_bits-width_in){1'b0}}};
		end else begin //all width_in bits of input data cannot fit, so truncate it
			assign act0_FF_in[width*(gv_i+1)-1:width*gv_i] = {{(int_bits+1){1'b0}}, act0_FF[width_in*(gv_i+1)-1:gv_i*width_in+width_in-frac_bits]};
			assign act0_UP_in[width*(gv_i+1)-1:width*gv_i] = {{(int_bits+1){1'b0}}, act0_UP[width_in*(gv_i+1)-1:gv_i*width_in+width_in-frac_bits]};
		end
	end
	endgenerate
	
	FF_processor_set #(
		.fo(fo), 
	 	.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z), 
	 	.width(width),
		.int_bits(int_bits), 
		.frac_bits(frac_bits)
	) L0_FF_processor (
		.clk(clk),
		.a_package(act0_FF_in),
		.w_package(w),
		.b_package(b),
		.sigmoid_package(act1),
		.sp_package(sp1)
	);

	UP_processor_set #(
		.fo(fo), 
		.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z), 
	 	.eta(eta), 
	 	//.lamda(lamda),
	 	.width(width),
		.int_bits(int_bits),
		.frac_bits(frac_bits)
	) L0_UP_processor (
		//.eta(eta),
		.eta_en(eta_en), 
		.delta_package(d1),
		.w_package(w),
		.b_package(b),
		.a_package(act0_UP_in),
		.w_UP_package(w_UP),
		.b_UP_package(b_UP)
	);


// MUXes	
	mux #( //Select AM collection for FF
		.width(width_in*z), //Read out z activations, each is  width_in bits (since input is width_in bits)
		.N(collection)) FFcoll_sel
		(act_mem_out, rFF_pt, act_rFF_raw);

	mux #( //Select AM collection for UP
		.width(width_in*z), 
		.N(collection)) UPcoll_sel
		(act_mem_out, rUP_pt, act_rUP_raw);

	mux_set #(
		.width(width_in), //Within collection, select AM for FF
		.N(z)) rFF_mux
		(act_rFF_raw, mux_sel, act0_FF);

	mux_set #(.width(width_in), //Within collection, select AM for UP
		.N(z)) rUP_mux
		(act_rUP_raw, mux_sel, act0_UP);
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

module hidden_layer_block #(
	parameter p = 8,
	parameter n = 4,
	parameter z = 4,
	parameter fi = 4,
	parameter fo = 2,
	parameter eta = 4,
	//parameter lamda = 1,
	parameter width = 16, 
	parameter int_bits = 5, //No. of bits in integer part. Needed for all processors
	parameter frac_bits = 10, //No. of bits in fractional part. Needed for UP_processor
	parameter L = 2,
	parameter h = 1, //h = 1 means first hidden layer, i.e. 2nd overall layer, and so on
	parameter collection = 2 * (L-h) - 1, //No. of AM and sp collections. Note that no. of DM collections is always 2
	parameter cpc = p/z*fo+2
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk,
	//input signed [width-1:0] eta, //Learning rate
	input eta_en,
	input [width*z/fo-1:0] actin, //from prev
	input [width*z/fo-1:0] spin, //from prev
	input [width*z/fi-1:0] din, //from next
	output [width*z/fi-1:0] actout, //to next
	output [width*z/fi-1:0] spout, //to next
	output [width*z/fo-1:0] dout //to prev
);

// State machine outputs
	wire [collection*z*$clog2(p/z)-1:0] actin_addr;	//AMp collection address
	wire [collection*z-1:0] act_we;	//AMp collection write enable
	wire [2*z*$clog2(p/z)-1:0] d_addrA, d_addrB; //DMp collection address
	wire [2*z-1:0] d_weA, d_weB; //DMp collection write enable
	wire [width*2*z-1:0] d_mem_inB; //DMp write back data
	wire [$clog2(collection)-1:0] rFF_pt, rUP_pt; //AMp collection select signals for reading in FF and UP
	wire d_r_pt; //DMp collection select signal for reading for previous BP. Negation of this is used for writing current BP
	wire [$clog2(z)*z-1:0] mux_sel, d_mux_sel; //For interleavers
	wire [$clog2(cpc)-1:0] cycle_index_delay;
	
// Weight and bias memories are lumped together. z WMs, z/fi BMs, together z+z/fi WBMs, each has p*fo/z elements, each having width bits
// WBM controller outputs: 
	wire [(z+z/fi)-1:0] wb_weA, wb_weB;	//weight and bias memory write enable
	wire [(z+z/fi)*$clog2(p*fo/z)-1:0] wb_addrA, wb_addrB;	//weight and bias memory address

// Datapath signals: MUXes, memories, processor sets
	wire [width*z-1:0] actin_FF_in, actin_UP_in, spin_BP_in; //width bit act values for processor set usage. Note that they are already extended to width bits, unlike input layer
	wire [width*z-1:0] w, w_UP;	//old and new weights
	wire [width*z/fi-1:0] b, b_UP;	//old and new biases
	wire [width*collection*z-1:0] actin_mem_in, act_mem_out; //AMp in/out
	wire [width*z-1:0] act_rFF_raw, act_rUP_raw; //activation output after collection selected
	wire [width*collection*z-1:0] spin_mem_in, sp_mem_out; //SMp in/out
	wire [width*z-1:0] sp_rBP_raw;	//sp output after collection selected
	wire [width*z-1:0] dout_raw;	//delta after collection selected for previous layer BP
	wire [width*z-1:0] partial_d_raw; //delta after collection selected to BP_processor for current layer BP
	wire [width*z-1:0] partial_d, acc_d; //partial delta in/out for BP_processor
	wire [width*z*2-1:0] d_dataA, d_dataB;	//DMp in/out
	wire [width*z-1:0] writeback_d; //partial delta after re-order to delta memory


// Hidden Layer State Machine
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value
	state 3: cycle counter = 3, read out the 2nd clock value, write the 1st value in delta mem
	...
	state n-3: cycle counter = n-3, read out the n-2 clock value, write the n-4 value in delta mem 
	state n-2: cycle counter = n-2, write the n-3 value in delta mem 
	state n-1: cycle counter = n-1, write the n-2 value in delta mem */
	hidden_layer_state_machine #(	
		.fo(fo), 
		.fi(fi), 
		.p(p), 
		.n(n), 
		.z(z), 
		.L(L),
		.h(h),
		.cpc(cpc), 
		.width(width), 
		.collection(collection)
	) hidden_layer_state_machine (
		.clk(clk),
		.reset(reset),
		.cycle_index(cycle_index),
		.cycle_clk(cycle_clk),
		.act_data_in(actin),
		.sp_data_in(spin),
		.act_addr_package(actin_addr),
		.act_we_package(act_we),
		.act_data_in_mem(actin_mem_in),
		.sp_data_in_mem(spin_mem_in), 
		.d_addrA_package(d_addrA),
		.d_weA_package(d_weA),
		.d_addrB_package(d_addrB),
		.d_weB_package(d_weB),
		.d_mem_inB(d_mem_inB),
		.actual_mux_sel(mux_sel),
		.actual_d_mux_sel(d_mux_sel),
		.actual_rFF_pt(rFF_pt),
		.actual_rUP_pt(rUP_pt),
		.d_r_pt(d_r_pt),
		.cycle_index_delay(cycle_index_delay)
	);

// Weight and Bias Memory Controller
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value, write the 1st value in act mem
	state 3: cycle counter = 3, read out the 2nd clock value, write the 2nd value in act mem */
	w_mem_ctr #(
		.fo(fo), 
		.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z+z/fi), 
	 	.cpc(cpc)
	) hidden_layer_wbmem_ctr (
		.clk(clk),
		.cycle_index(cycle_index),
		.reset(reset), 
		.weA(wb_weA),
		.weB(wb_weB),
		.r_addr(wb_addrA),
		.w_addr(wb_addrB)
	);


// Memories
	// act and sp have exactly same memory behavior, i.e. same number of collections and sizes
	// Both get written into from previous layer when FF is getting computed for current layer. This is done in collection w_pt (internal to hidden_layer_state_machine)
	// Both are read from collection rUP_pt. Act values compute Update, while sp values compute BP of previous layer
	// Only difference is that act is read one more time from collection rFF_pt, used to compute FF of next layer. For this reason, do not concatenate act and sp into same memory
	// Concatenation can be done, but will make code more complex
	mem_collection #(
		.collection(collection), 
		.width(width), 
		.depth(p/z), 
		.z(z)
	) AMp (
		.clk(clk), 
		.we_package(act_we),
		.addr_package(actin_addr), 
		.data_in_package(actin_mem_in),
		.data_out_package(act_mem_out)
	);

	mem_collection #(
		.collection(collection), 
		.width(width), 
		.depth(p/z), 
		.z(z)
	) sp_mem (
		.clk(clk), 
		.we_package(act_we),
		.addr_package(actin_addr), 
		.data_in_package(spin_mem_in),
		.data_out_package(sp_mem_out)
	);

	dual_port_mem_collection #(
		.collection(1), 
		.width(width), 
		.depth(p*fo/z), 
		.z(z+z/fi), 
		.fi(fi), 
		.fo(fo)
	) wb_mem (
		.clk(clk), 
		.weA_package(wb_weA),
		.weB_package(wb_weB),
		.addrA_package(wb_addrA),
		.addrB_package(wb_addrB),
		// There is no data_inA_package
		.data_outA_package({w, b}), //Output data from port A are the read out existing weight and bias values
		.data_inB_package({w_UP, b_UP}) //Input data to port B are the updated weight and bias values
		// There is no data_outB_package
	);

	dual_port_mem_collection #( //For detailed DMp behavior, refer to memory_ctr file
		.collection(2), 
		.width(width), 
		.depth(p/z), 
		.z(z)
	) delta_mem (
		.clk(clk), 
		.weA_package(d_weA),
		.addrA_package(d_addrA),
		.data_inA_package({writeback_d, writeback_d}), //Write back replicated value just to make vector widths match. In reality, 1 of the write enables is always 0, so nothing is written
		.data_outA_package(d_dataA), 
		.weB_package(d_weB),
		.addrB_package(d_addrB),
		.data_inB_package(d_mem_inB),
		.data_outB_package(d_dataB)
	);


// Processor Sets
	FF_processor_set #(
		.fo(fo), 
	 	.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z), 
	 	.width(width),
		.int_bits(int_bits), 
		.frac_bits(frac_bits)
	) FF_processor (
		.clk(clk),
		.a_package(actin_FF_in),
		.w_package(w),
		.b_package(b),
		.sigmoid_package(actout),
		.sp_package(spout)
	);

	UP_processor_set #(
		.fo(fo), 
		.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z), 
	 	.eta(eta), 
	 	//.lamda(lamda),
	 	.width(width),
		.int_bits(int_bits),
		.frac_bits(frac_bits)
	) UP_processor (
		//.eta(eta), 
		.eta_en(eta_en),
		.delta_package(din),
		.w_package(w),
		.b_package(b),
		.a_package(actin_UP_in),
		.w_UP_package(w_UP),
		.b_UP_package(b_UP)
	);

	BP_processor_set #(
		.fo(fo), 
		.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z), 
	 	.width(width), 
		.int_bits(int_bits), 
		.frac_bits(frac_bits)
	) BP_processor (
		.deltan_package(din),
		.sp_package(spin_BP_in),
		.w_package(w),
		.partial_d_package(partial_d),
		.deltap_package(acc_d)
	);


// MUXes
	mux #(.width(width*z), //select AMp collection for FF
		.N(collection)) FFcoll_sel
		(act_mem_out, rFF_pt, act_rFF_raw);

	mux #(.width(width*z), //select AMp collection for UP
		.N(collection)) UPcoll_sel
		(act_mem_out, rUP_pt, act_rUP_raw);

	mux_set #(.width(width), //set of MUXes to choose SRAM inside a collection for FF
		.N(z)) rFF_mux
		(act_rFF_raw, mux_sel, actin_FF_in);

	mux_set #(.width(width), //set of MUXes to choose SRAM inside a collection for UP
		.N(z)) rUP_mux
		(act_rUP_raw, mux_sel, actin_UP_in);

	mux #(.width(width*z), //select SMp collection for BP. Note that it uses rUP_pt, same as what was used in AMp
		.N(collection)) spcoll_sel
		(sp_mem_out, rUP_pt, sp_rBP_raw);

	mux_set #(.width(width), //set of MUXes to choose SRAM inside a collection for BP
		.N(z)) sp_rBP_mux
		(sp_rBP_raw, mux_sel, spin_BP_in);

	mux #(.width(width*z), //select DMp collection for current BP
		.N(2)) currentBPcoll_sel
		(d_dataB, ~d_r_pt, partial_d_raw); //d_dataB is output of all collections. partial_d_raw is output of chosen colleciton

	mux_set #(.width(width), //Interleaver mux set for read out from BP
		.N(z)) d_w_inter
		(partial_d_raw, mux_sel, partial_d);

	mux_set #(.width(width), //De-Interleaver mux set for write back to BP
		.N(z)) d_writeback_mux
		(acc_d, d_mux_sel, writeback_d);

	mux #(.width(width*z), //select DMp collecton for previous BP
		.N(2)) previousBPcoll_sel
		(d_dataA, d_r_pt, dout_raw);

	mux #(.width(width*z/fo), // This mux is to segment prev mux values into cpc-2 chunks and feed them sequentially to prev layer
		.N(fo)) d_r_sel
		(dout_raw, cycle_index_delay[$clog2(fo)-1:0], dout);
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

module output_layer_block #(
	parameter p = 4, // No. of neurons in output layer. This is denoted as p since we deal with the imaginary junction between last layer and the layer after it
	parameter z = 1, //IMPORTANT: z for last layer is no. of neurons getting calculated per clock, NOT number of weights. So z = z_hidden/fi
	parameter width = 16,
	parameter int_bits = 5,
	parameter frac_bits = 10,
	parameter L = 3,
	parameter cost_type = 1, //0 for quadcost, 1 for xentcost
	parameter cpc = p/z+2 //Since z = z_hidden/fi, cpc = p*fi/z_hidden = p/z
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk,
	input [width*z-1:0] actL, //from prev
	input [width*z-1:0] spL, //from prev
	// [todo] spL is only used for quadcost. If xentcost is always used, this can be dispensed with, but may lead to significant code revision
	input [z-1:0] y, //ideal outputs from beginning
	output [width*z-1:0] deltaL, //to prev
	//output [z-1:0] a_out, //actual computed outputs from whole neural network
	output [z-1:0] yL //ideal outputs at end. Simply delayed version of ideal outputs from beginning
);

//State Machine and cycle_index DFF outputs
	wire [2*z*$clog2(p/z)-1:0] delta_addr;	//all DMp addresses
	wire [2*z-1:0] delta_we; //all DMp write enable signal
	wire r_pt; //DMp collection select signal
	wire [$clog2(cpc)-1:0] cycle_index_delay;
	
//Datapath signals: MUXes, memories, cost calculators
	wire [width*z-1:0] a_minus_y; //just what it says. Used in cost calculation
	wire [width*z-1:0] delta; //computed delta value, to be written to DMp. This is input to state machine
	wire [width*2*z-1:0] deltaL_mem_in, deltaL_mem_out;	//delta memory in/out

	//max activation value computation
	wire [width-1:0] maxact;
	reg [width-1:0] stored_maxact = {1'b1,{(width-1){1'b0}}}; //least (i.e. most negative) value possible in width bits
	wire [width-1:0] final_maxact;


// Output Layer State Machine (L=L):
/* After reset:
	state 0: cycle counter = 0, 
	state 1: cycle counter = 1, read out the 1st clock value
	state 2: cycle counter = 2, read out the 2nd clock value
	state 3: cycle counter = 3, read out the 2nd clock value, write the 1st value in act mem
	... */
	output_layer_state_machine #(	
		.p(p), 
		.z(z), 
		.L(L), 
		.cpc(cpc), 
		.width(width)
		// Note that parameter fi is not passed. This is because fi is only used inside output_layer_state_machine to calculate cpc. But we are already passing cpc
	) output_layer_state_machine (
		.clk(clk),
		.reset(reset),
		.cycle_index(cycle_index),
		.cycle_clk(cycle_clk),
		.data_in(delta),
		.addr_package(delta_addr),
		.we_package(delta_we), 
		.data_in_mem_package(deltaL_mem_in),
		.r_pt(r_pt)
	);
	
// Delay cycle_index
	DFF #(
		.width($clog2(cpc))
	) DFF_cycle_index (
		.clk(clk),
		.reset(reset),
		.d(cycle_index),
		.q(cycle_index_delay)
	);


// Memories
	mem_collection #(
		.collection(2), 
		.width(width), 
		.depth(p/z), 
		.z(z)
	) DMp_coll (
		.clk(clk), 
		.we_package(delta_we),
		.addr_package(delta_addr), 
		.data_in_package(deltaL_mem_in),
		.data_out_package(deltaL_mem_out)
	);


// Calculate cost (note that ideal outputs are given at beginning and need to propagate, hence the shift register)
	shift_reg #( //Shift register for ideal outputs y from input layer to output layer
		.width(z),
		.depth(cpc*(L-1))
	) sr_idealoutputs (
		.clk(clk),
		.reset(reset),
		.data_in(y),
		.data_out(yL)
	);
		
	costterm_set #(
		.z(z), 
		.width(width),
		.int_bits(int_bits),
		.frac_bits(frac_bits)
	) costterms (
		.a_set(actL),
		.y_set(yL),
		.c_set(a_minus_y)
	);

	generate //Calculate delta, which goes to state machine, from where it goes to DMp
		if (cost_type==0) begin //quadcost
			multiplier_set #( //calculate delta by multiplying a_minus_y with sigmoid prime
				.z(z), 
				.width(width),
				.int_bits(int_bits)
			) L_delta_processor (
				a_minus_y, spL, delta
			);
		end else begin //xentcost
			assign delta = a_minus_y; //delta is just a minus y
		end
	endgenerate


// Collection choosing MUX
	mux #(.width(width*z), 
		.N(2)) r_collection
		(deltaL_mem_out, r_pt, deltaL); //choose collection and output chosen delta value to previous layer


	// Threshold width bit outputs to get 1b outputs (DEPENDING ON ACTIVATION)
	// Right now this supports activations with only nonnegative values (like sigmoid and relu)
	// [todo] add support for negative activations like tanh if needed
	/* genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
		begin : a_output //[todo] Insert ifdef for different activations
		// For sigmoid:
		//assign a_out[gv_i] = actL[gv_i*width+frac_bits-1]|| actL[gv_i*width+frac_bits]; //This picks out the fractional part MSB. Use that to threshold, i.e. if >=0.5, output=1, if <0.5, output is 0	
		// More general condition
			assign a_out[gv_i] = (actL[(gv_i+1)*width-1:gv_i*width+frac_bits-1] != 0)? 1 : 0;//if actL>=0.5, output=1, if actL<0.5, output is 0
	end
	endgenerate */
endmodule
