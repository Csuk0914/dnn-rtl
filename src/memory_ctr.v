`timescale 1ns/100ps

module w_mem_ctr #( //Controller for weight and bias memories
	parameter p = 16,
	parameter n = 8,
	parameter z = 10,
	parameter fi = 4,
	parameter fo = 2,
	parameter cpc = p*fo/z + 2
)(
	input clk,
	input [$clog2(cpc)-1:0] cycle_index,
	input reset,
	output [z-1:0] weA, //2 write enables because dual port
	output [z-1:0] weB, //Each write enable has z bits because there are z memories of each type => ONE HOT encoding
	output [$clog2(p*fo/z)*z-1:0] r_addr, //Address is a = log(p*fo/z) = log(cpc-2) bits, since there are p*fo/z cells in each weight memory
	output [$clog2(p*fo/z)*z-1:0] w_addr //Lump all the addresses together. Since there are z memories, there are z a-bit addresses
);

	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1) //This loop packs the WEs and read address for all z memories into big 1D vectors
	begin: ctr_generate
		assign weA[gv_i] = 1'b0; //All weA = 0 because port A is always used to read, never to write
		assign weB[gv_i] = (cycle_index>0 && cycle_index<= cpc-2)? ~reset : 0; //If cycle_index has a valid value and reset is OFF, then all weB = 1
		assign r_addr[$clog2(cpc-2)*(gv_i+1)-1:$clog2(cpc-2)*gv_i] = cycle_index[$clog2(cpc-2)-1:0]; //All read addresses = cycle_index, since we read the same entry from all memories
		//Note that when p*fo/z is a power of 2, the RHS above is all the bits of cycle_index except for the MSB
		// This is because the MSB simply accounts for the pipeline delay, the real cycle_index is 2nd MSB to LSB
	end
	endgenerate

	DFF #(
		.width(z*$clog2(cpc-2))
	) dff_memaddr (
		.clk(clk),
		.reset(reset),
		.d(r_addr),
		.q(w_addr)
	); //Because whatever entry we read from all the WMs, same entries are updated 1 cycle later
endmodule


module output_layer_state_machine #( //This is a state machine, so it controls last layer by giving all memory and data control signals
	parameter z = 1,
	parameter p = 4, //Number of neurons in last layer
	parameter fi = 2,
	parameter L = 3,
	parameter width = 16,
	parameter cpc = p/z*fi+2
	//There is no param for collection because delta memory always has 2 collections in output layer. Each collection is a bunch of z memories, each of size p*fo/z
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index, //This is used for reading in cycles 0,...,cpc-3
	input cycle_clk, //1 cycle_clk = cpc clks
	input [width*z-1:0] data_in, //delta, after it finishes computation from cost terms
	output [2*z*$clog2(p/z)-1:0] addr_package, //lump all addresses together: collections * mem/collection * addr_bits/mem
	// Note that these addresses are for AM, so they are log(p/z) bits
	output [2*z-1:0] we_package,
	output [2*z*width-1:0] data_in_mem_package,
	output r_pt //selects 1 collection. 1b because no. of DM collections is always 2
);

	wire actual_coll_wpt, initial_coll_wpt; //1b because no. of DM collections is always 2
	//initial_coll_wpt is collection which will be written in this cycle_clk (cost collection). actual_coll_wpt is same thing, delayed by 1-2 clocks because write does not start until clk 2.
	wire [$clog2(cpc)-1:0] cycle_index_delay; //Delayed version of cycle_index by 2 clocks. Used for writing in cycles 2,...,cpc-1
	
	// Unpack all collections together 1D array into 2D array, with 1 dimension exclusively for collection
	// Note that the other dimension still packs stuff for all z memories in a collection
	wire [z-1:0] we[1:0];
	wire [z*$clog2(p/z)-1:0] addr[1:0];
	wire [z*width-1:0] data_in_mem[1:0];
	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: package_collection
		assign data_in_mem_package[width*z*(gv_i+1)-1:width*z*gv_i] = data_in_mem[gv_i];
		assign addr_package[$clog2(p/z)*z*(gv_i+1)-1:$clog2(p/z)*z*gv_i] = addr[gv_i];
		assign we_package[z*(gv_i+1)-1:z*gv_i] = we[gv_i];
	end
	endgenerate
	// Done unpack

	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: data_collections
		assign data_in_mem[gv_i] = data_in; //assign input data to memories in both collections, later mux will select 1
	end
	endgenerate

	// Generate write enables
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: enable_set
		for (gv_j = 0; gv_j<z; gv_j = gv_j + 1)
		begin: enable
			assign we[gv_i][gv_j] = actual_coll_wpt==gv_i && cycle_index>1? ~reset : 0; //1st cycle is only for read. Write starting from 2nd cycle
			assign addr[gv_i][$clog2(p/z)*(gv_j+1)-1:$clog2(p/z)*gv_j] = 
			actual_coll_wpt==gv_i ? cycle_index_delay[$clog2(p/z)-1:0] : cycle_index[$clog2(p/z)-1:0];
			//If actual_coll_wpt equals collection ID (0 or 1), then memory is being written. Write in cycles 2,3,...,cpc-1. Otherwise memory is being read. Read in cycles 0,1,...,cpc-3
		end
	end
	endgenerate

	counter #(.max(2), //Counter for DM collections. After every cpc clocks (i.e. 1 cycle_clk), changes from 0->1 or 1->0
			.ini(0)) delta_r_pt
			(cycle_clk, reset, initial_coll_wpt);
	// Note that counter output is initial_coll_wpt, which initially points to collection to be written into

	DFF #(
		.width(1)
	) dff_pointer (
		.clk(clk),
		.reset(reset),
		.d(initial_coll_wpt),
		.q(actual_coll_wpt)
	); //1 DFF is enough because mem remains idle. 2 is also fine
	assign r_pt = ~initial_coll_wpt; //Read pointer points to the other collection, form where I'm reading values and computing BP for prev layer

	shift_reg #(
		.width($clog2(cpc)), 
		.depth(2)
	) cycle_index_reg (
		.clk(clk),
		.reset(reset),
		.data_in(cycle_index),
		.data_out(cycle_index_delay)
	);
endmodule


module hidden_layer_state_machine #( // This is state machinw, so it will input data and output all mem data and control signals, i.e. for AMp, AMn, DMp, DMn
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 8,
	parameter n  = 4,
	parameter z  = 4,
	parameter L = 3,
	parameter h = 1, //Index. Layer after input has h = 1, then 2 and so on
	parameter cpc = p/z*fo+2,
	parameter width = 1,
	parameter collection = 2*(L-h) - 1 //No. of AM and SM collections (SM means sigmoid prime memory)
	// Note that no. of DM collections is always 2
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk,
	
	input [width*z/fo-1:0] act_data_in, //z weights processed together and since fo weights = 1 neuron, z/fo activations processed together
	input [width*z/fo-1:0] sp_data_in, //Same as act
	output [collection*z*$clog2(p/z)-1:0] act_addr_package, //AMp collections, each has z AMs, each AM has p/z entries, so total address bits = collection*z*log(p/z)
	output [collection*z-1:0] act_we_package, //Each AM has 1 we
	output [collection*z*width-1:0] act_data_in_mem, //Output data from a particular cell of all AMs
	output [collection*z*width-1:0] sp_data_in_mem, //Each read out datum from AM must have associated sp
	// For following DM parameters, replace collection with 2. Also, DM is dual port, so we need 2 addresses and 2 write enables
	output [2*z*$clog2(p/z)-1:0] d_addrA_package, //DMp collections
	output [2*z-1:0] d_weA_package,
	output [2*z*$clog2(p/z)-1:0] d_addrB_package,
	output [2*z-1:0] d_weB_package,
	output [2*z*width-1:0] d_mem_inB, //Data to be written into DM port B
	
	output [$clog2(z)*z-1:0] actual_mux_sel, //Goes to AMp, SMp. z MUXes, each of size z, i.e. log(z) select bits
	output [$clog2(z)*z-1:0] actual_d_mux_sel,	//Goes to DMp. When writing back to DMp, we need to reverse permutation. These are also z MUXes, each of size z, i.e. log(z) select bits
	
	//Reads are done for FF and UP (i.e. AMs). Following pointers are for reading 1 out of 2(L-h)-1 collections
	output [$clog2(collection)-1:0] actual_rFF_pt, //goes to FF
	output [$clog2(collection)-1:0] actual_rUP_pt, //goes to UP
	
	//Both read and write is done for BP (i.e. DMs). Following pointers are for reading/writing from 1 out of 2 collections (that's why they are only 1 bit)
	output d_r_pt, //choose collection from which read is done for preivous BP. Negation of this will be for write.
	output [$clog2(cpc)-1:0] cycle_index_delay
);	

	wire [$clog2(p)*z-1:0] memory_index; //Output of z interlavers. Points to all z neurons in p layer from which activations are to be taken for FF
	wire [$clog2(p/z)*z-1:0] r_address_raw; //z read addresses from all AMp for FF and UP
	//Note that same mem adresses are used for FF collection and UP collection, just because they are different collections, they need different r_pt values
	wire [$clog2(z)*z-1:0] initial_mux_sel, initial_d_mux_sel; //z MUXes, each z-to-1, i.e. log(z) select bits
	wire [$clog2(collection)-1:0] initial_rFF_pt, initial_rUP_pt; //AM collections used for FF and UP

	// Set of z interleaver blocks. Takes cycle index as input, computes interleaved output
	interleaver_set #(
		.fo(fo), 
	 	.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z)
	) interlever (
		.cycle_index(cycle_index[$clog2(cpc-2)-1:0]), //if cpc = 3, then $clog2(cpc-2)-1 = -1. For Verilog, a[-1:0] is a syntax error. So cpc must be > 3
		.memory_index_package(memory_index)
	);

	address_decoder #(
		.fo(fo), 
	 	.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z)
	) address_decoder (
		.memory_index_package(memory_index),
		.address_package(r_address_raw),
		.mux_sel_package(initial_mux_sel),
		.d_mux_sel_package(initial_d_mux_sel)
	);

	act_sp_ctr #(
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
	) act_sp_ctr (
		.clk(clk),
		.reset(reset),
		.cycle_clk(cycle_clk),
		.cycle_index(cycle_index),
		.r_address_raw(r_address_raw),
		.act_data_in(act_data_in),
		.sp_data_in(sp_data_in),
		.act_addr_package(act_addr_package),
		.act_we_package(act_we_package),
		.act_data_in_mem(act_data_in_mem),
		.sp_data_in_mem(sp_data_in_mem), 
		.d_addrA_package(d_addrA_package),
		.d_weA_package(d_weA_package),
		.d_addrB_package(d_addrB_package),
		.d_weB_package(d_weB_package),
		.d_mem_inB(d_mem_inB), 
		.rFF_pt(initial_rFF_pt),
		.rUP_pt(initial_rUP_pt),
		.d_rBP_pt(d_r_pt),
		.cycle_index_d(cycle_index_delay)
	);

	//DFFs used to delay control signals one clock, since memory needs 1 cycle to operate
	DFF #(.width($clog2(z)*z)) DFF_mux_sel (.clk(clk), .reset(reset), .d(initial_mux_sel), .q(actual_mux_sel));	
	DFF #(.width($clog2(z)*z)) DFF_d_mux_sel (.clk(clk), .reset(reset), .d(initial_d_mux_sel), .q(actual_d_mux_sel));	
	DFF #(.width($clog2(collection))) DFF_rFF_pt (.clk(clk), .reset(reset), .d(initial_rFF_pt), .q(actual_rFF_pt));
	DFF #(.width($clog2(collection))) DFF_rUP_pt (.clk(clk), .reset(reset), .d(initial_rUP_pt), .q(actual_rUP_pt));
endmodule


module act_sp_ctr #(
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 16,
	parameter n  = 8,
	parameter z  = 8,
	parameter L = 3,
	parameter h = 1,
	parameter cpc = p/z*fo+2,
	parameter width = 16,
	parameter collection = 2*(L-h)-1
)(
	input clk,
	input reset,
	input cycle_clk,
	input [$clog2(cpc)-1:0]cycle_index,
	input [$clog2(p/z)*z-1:0] r_address_raw, //output of address decoder
	
	//Next 2 inputs are from FF processor of previous layer. Total no. of clocks = p*fo/z. Total act and sp to be inputted = p. So no. of values reqd in each clk = p / p*fo/z = z/fo
	// z/fo memories together is defined as a part. So act_data_in and sp_data_in hold all the data for 1 cell of all z/fo memories in a part
	input [width*z/fo-1:0] act_data_in,
	input [width*z/fo-1:0] sp_data_in,

	// Next 4 signals are for AMp
	output [collection*z*$clog2(p/z)-1:0] act_addr_package,
	output [collection*z-1:0] act_we_package,
	output [collection*z*width-1:0] act_data_in_mem, // All data to be written into AM and sp mem in 1 clock. 1 clock writes 1 cell in all memories of each collection
	output [collection*z*width-1:0] sp_data_in_mem,
	
	// Next 5 signals are for DMp
	output [2*z*$clog2(p/z)-1:0] d_addrA_package,
	output [2*z-1:0] d_weA_package,
	output [2*z*$clog2(p/z)-1:0] d_addrB_package,
	output [2*z-1:0] d_weB_package,
	output [2*z*width-1:0] d_mem_inB,
	
	output [$clog2(collection)-1:0] rFF_pt, //AM collection from which FF is computed for next layer
	output [$clog2(collection)-1:0] rUP_pt,	//AM collection used for UP. IMPORTANT: Also collection which provides sp values for current layer BP
	output d_rBP_pt,	//DM collection from which BP is computed for previous layer
	output [$clog2(cpc)-1:0] cycle_index_d	//1 cycle delay of cycle_index, used for read-modify-write in DM
);

	wire [$clog2(cpc)-1:0]cycle_index_delay; //2 cycle delay of cycle_index, used for writing to AM
	wire [$clog2(collection)-1:0]w_pt; //AM collection whose FF is being computed in current layer. IMPORTANT: Also SM collection currently being written into
	wire [$clog2(p/z)*z-1:0] w_address_raw; //interleaved addresses for writing FF being computed
	
	wire [$clog2(p/z)*z-1:0] act_addr [collection-1:0]; //unpacked AMp addresses
	wire [z-1:0] act_we [collection-1:0]; //unpacked AMp write enables
	
	wire [$clog2(p/z)*z-1:0] d_addrA[1:0], d_addrB[1:0]; //unpacked DMp addresses. [1:0] is used because there are 2 collections
	wire [$clog2(p/z)*z-1:0] d_r_addr, d_r_addr_delay; //see below
	wire [$clog2(p/z)*z-1:0] r_address_raw_delay;

	genvar gv_i, gv_j, gv_k;
	
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: act_addr_collection
		assign act_addr[gv_i] = (gv_i == w_pt)? w_address_raw : r_address_raw; //basically if you are not writing to a collection, you can read from it. Read is not destructive
	end
	endgenerate
	
	// Pack write enables into 1D layer for outputting to hidden layer memories
	//the z parallel memory will be divided into (fo) parts. all parts will be loaded in sequence (p/z) times.
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1) //choose collection out of collection collections
	begin: act_we_collections
		for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1) //choose part out of fo parts in a collection
		begin: act_we_one_collection
			for (gv_k = 0; gv_k<(z/fo); gv_k = gv_k + 1) //choose memory out of z/fo memories in a part
			begin: act_we_one_cycle
				assign act_we[gv_i][gv_j*z/fo+gv_k] = 
					((cycle_index_delay<p/z*fo) && //check that there are clocks left in cycle
					(gv_j==cycle_index_delay[$clog2(p/z*fo/2)-1:0]) && //check that current clock is referencing correct part
					(gv_i==w_pt) && (!reset))? 1: 0; //check that correct collection is selected and reset is off
			end
		end
	end
	endgenerate
		
	//this generate block assigns the raw write address by cycle index. z DMp addresses, each = log(p/z) bits
	//raw write address means the address is the write address for selected collection memory
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin: raw_address_generator
		assign  w_address_raw[$clog2(p/z)*(gv_i+1)-1:$clog2(p/z)*gv_i] 
			= cycle_index_delay[$clog2(p/z*fo)-1:$clog2(fo)]; //Take all MSB of cycle_index_delay except for log(fo) LSB. This is the cell address for writing
			/* [Eg: If p*fo = 4096, z = 64, fo=4, then 1 AMp collection has 4 parts, each part has 16 memories, each memory has 16 entries.
			   cpc = 64. So in 1st cycle, write cell 0 of 1st 16 memories, then cell0 of next 16 memories in next cycle and so on.
			   So cell number remains constant for 4 cycles, so we discard 2 LSB]. Same thing for BP */
		assign d_r_addr[$clog2(p/z)*(gv_i+1)-1:$clog2(p/z)*gv_i] 
			= cycle_index[$clog2(p/z*fo)-1:$clog2(fo)];
	end
	endgenerate
	
	// This is for unpacking 'collection' AM collections
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: package_collection
		assign act_addr_package[z*$clog2(p/z)*(gv_i+1)-1:z*$clog2(p/z)*gv_i] = act_addr[gv_i];
		assign act_we_package[z*(gv_i+1)-1:z*gv_i] = act_we[gv_i];
	end
	endgenerate

 /* Pack act and sp input data from previous layer into 1D array for outputting to hidden layer memories
	in one clock, (z/fo) [Eg=16] activations will be loaded to activation memory
	memory parallelism is z [Eg=64], and clocks per cycle is (p/z*fo) [Eg=64]
	the z [Eg=64] parallel memories will be divided into fo [Eg=4] parts. Each part will load a value, i.e. 16 values total
	each memory should be loaded p/z [Eg=16] times */
	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: data_collections
		 for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1)
		begin: data_one_collection
			assign act_data_in_mem[(z*gv_i + z/fo*(gv_j+1)) * width -1:(z*gv_i+z/fo*gv_j)*width] = act_data_in;
			// z*gv_i sweeps collections. There are fo parts, each part having z/fo memories. z/fo*gv_j sweeps parts.
			// act_data_in contains all entries for 1 cell in a part, i.e. z/fo memories * width data
			// Same for sp_data_in below
			assign sp_data_in_mem[(z*gv_i+z/fo*(gv_j+1))*width-1:(z*gv_i+z/fo*gv_j)*width] = sp_data_in;
		end
	end
	endgenerate
		
/*  Delta memory working:
	There are 2 collections, each has ports A and B, each can read and write enable and so has write enables
	Assume d_rBP_pt = 1, so collection 1 is being read to compute BP for previous layer, while collection 0 is doing read-modify-write for BP of current layer
	Port A of coll 1 will always be read, so its weA = 0
	Port B of coll 1 must be used for writing. We should write 0 here because this will be the R-M-W collection for the next cycle_clk and will accumulate partial_d, so must start from 0
		So weB will be 1 after 1 clock delay
	Port B of coll 0 will always be read for the R in R-M-W. So its weB = 0
		Note that 0 will be attempted to be written to port B of both collections, but will only succeed for coll 1 because weB of coll 0 = 0
	Port A of coll 0 must be used for the W in R-M-W. So its weA will be 1 after a clk delay
*/
	
	// This is for unpacking 2 DM collections
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: package_delta
		assign d_addrA_package[(gv_i+1)*z*$clog2(p/z)-1:z*$clog2(p/z)*gv_i] = d_addrA[gv_i];
		assign d_addrB_package[(gv_i+1)*z*$clog2(p/z)-1:z*$clog2(p/z)*gv_i] = d_addrB[gv_i];
		for (gv_j = 0; gv_j<z; gv_j = gv_j + 1)
		//begin: package_delta_data
			assign d_mem_inB[width*(gv_i*z+gv_j+1)-1:width*(gv_i*z+gv_j)] = 0; //Attempt to write 0 to port B of both collections
	end
	endgenerate

	// DM weA
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: d_control
		for (gv_j = 0; gv_j<z; gv_j = gv_j + 1)
		begin: d_control_one_collection
			assign d_weA_package[gv_i*z+gv_j] = 
			((gv_i == d_rBP_pt)||(cycle_index == 0)||(cycle_index>p/z*fo)) ? 0 : 1;
			//From the example in comments, weA of rBP_pt collection = 0 and weA of ~rBP_pt collection = 1, unless it's the 0th clk.
			//We cannot write after cycles are exceeded, so weA will also be 0 for this occasion
		end
	end
	endgenerate

	// DM weB
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
		for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1) //choose part out of fo parts in a collection
			for (gv_k = 0; gv_k<(z/fo); gv_k = gv_k + 1) //choose memory out of z/fo memories in a part
				assign d_weB_package[gv_i*z+gv_j*(z/fo)+gv_k] = 
					((cycle_index_d < cpc-2) &&
					((gv_j)==cycle_index_d[$clog2(fo)-1:0]) && //check for part match
					(gv_i==d_rBP_pt))? 1: 0;

	// generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	// 	for (gv_j = 0; gv_j<p/z*fo; gv_j = gv_j + 1)
	// 		for (gv_k = 0; gv_k<(z/(cpc-2)); gv_k = gv_k + 1)
	// 			assign d_weB_package[gv_i*z+gv_j*z/(cpc-2)+gv_k] = 
	// 			((cycle_index_d < cpc-2) &&
	// 			(gv_j==cycle_index_d[$clog2(p/z*fo)-1:0]) && //check for part match
	// 			(gv_i==d_rBP_pt))? 1: 0;
				// From the example in comments, weB of ~rBP_pt will be 0
				// weB of rBP_pt will be 1 only after 1 clock delay, that is why we use cycle_index_d in the comparison, and not cycle_index
				// (cycle_index can be used of course, but that would lead to the additional condition of it needing to be greater than 0)
				// Writing 0 is done part by part, so we need to check for part match and write for exactly cpc-2 cycles, otherwise no. of parts will overshoot
	endgenerate

	// DM Addresses
	generate for (gv_i = 0; gv_i<2; gv_i = gv_i + 1)
	begin: d_addr
		assign d_addrA[gv_i] = (gv_i == d_rBP_pt)? d_r_addr : r_address_raw_delay;
		assign d_addrB[gv_i] = (gv_i == d_rBP_pt)? d_r_addr_delay: r_address_raw;
		/*  For rBP_pt coll, port A (read) address is the one sequentially computed from cycle index, i.e. the one that goes part by part.
				This is because we read DM in sequence for previous layer BP
			For the other (i.e. R-M-W) coll, port A (write) address is as generated from the interleaver, delayed by 1
			For rBP_pt coll, port B (write 0) address = Same as its port A (read) address, delayed by 1
			For the other (i.e. R-M-W) coll, port B (read) address is as generated from the interleaver */
	end
	endgenerate

	// Set pointers for AM and DM collections:
	counter #(.max(2*(L-h)-1), 
		.ini(0)) act_rFF
		(cycle_clk, reset, rFF_pt); //AM collection read pointer for next layer FF. Starts from 0, cycles through all collections

	counter #(.max(2*(L-h)-1), 
		.ini(1)) act_wFF
		(cycle_clk, reset, w_pt); //AM collection write pointer for FF being computed from previous layer. Always the coll after rFF

	counter #(.max(2*(L-h)-1), 
		.ini(2)) act_rUP
		(cycle_clk, reset, rUP_pt); //AM collection read pointer for UP (also gives SP for current layer BP). Always the coll 2 after FF

	counter #(.max(2), 
			.ini(0)) delta_r
			(cycle_clk, reset, d_rBP_pt); //DM collection read pointer for previous layer BP

	shift_reg #(
		.width($clog2(cpc)), 
		.depth(2)
	) cycle_index_reg (
		.clk(clk),
		.reset(reset),
		.data_in(cycle_index),
		.data_out(cycle_index_delay)
	);

	DFF #(.width($clog2(p/z)*z)) DFF_r_address_raw (.clk(clk), .reset(reset), .d(r_address_raw), .q(r_address_raw_delay));
	DFF #(.width($clog2(p/z)*z)) DFF_r_addr (.clk(clk), .reset(reset), .d(d_r_addr), .q(d_r_addr_delay));
	DFF #(.width($clog2(cpc))) DFF_cycle_index (.clk(clk), .reset(reset), .d(cycle_index), .q(cycle_index_d));
endmodule


// first_layer_state_machine is a subset of hidden_layer_state_machine, without DMs
module input_layer_state_machine #(
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 16,
	parameter n  = 8,
	parameter z  = 8,
	parameter L = 3,
	parameter cpc = p/z*fo+2,
	parameter width = 1,
	parameter collection = 2*L - 1
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	input cycle_clk,
	input [width*z/fo-1:0] data_in,
	output [collection*z*$clog2(p/z)-1:0] act_addr_package,
	output [collection*z-1:0] act_we_package,
	output [$clog2(z)*z-1:0] actual_mux_sel,
	output [collection*z*width-1:0] data_in_mem,
	output [$clog2(collection)-1:0] actual_rFF_pt,
	output [$clog2(collection)-1:0] actual_rUP_pt
);

	wire [$clog2(p)*z-1:0] memory_index;
	wire [$clog2(p/z)*z-1:0] act_addr;
	wire [$clog2(p/z)*z-1:0] r_address_raw;
	wire [$clog2(z)*z-1:0] initial_mux_sel;
	wire [$clog2(collection)-1:0] initial_rFF_pt, initial_rUP_pt;

	interleaver_set #(
		.fo(fo), 
	 	.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z)
	) interleaver (
		.cycle_index(cycle_index[$clog2(cpc-2)-1:0]),
		.memory_index_package(memory_index)
	);

	address_decoder #(
		.fo(fo), 
	 	.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z)
	) address_decoder (
		.memory_index_package(memory_index),
		.address_package(r_address_raw),
		.mux_sel_package(initial_mux_sel)
		//note that initial_d_mux_sel doesn't exist, so the final port is unconnected
	); 

	act_ctr	 #(
		.fo(fo), 
		.fi(fi), 
		.p (p), 
		.n(n), 
		.z(z), 
		.L(L), 
		.cpc(cpc), 
		.width(width), 
		.collection(collection)
	) act_ctr (
		.clk(clk),
		.reset(reset),
		.cycle_clk(cycle_clk),
		.cycle_index(cycle_index),
		.r_address_raw(r_address_raw),
		.data_in(data_in), 
		.act_addr_package(act_addr_package),
		.act_we_package(act_we_package),
		.data_in_mem(data_in_mem), 
		.rFF_pt(initial_rFF_pt),
		.rUP_pt(initial_rUP_pt)
	);

	DFF #(.width($clog2(z)*z)) DFF_mux_sel (.clk(clk), .reset(reset), .d(initial_mux_sel), .q(actual_mux_sel));	
	DFF #(.width($clog2(collection))) DFF_rFF_pt (.clk(clk), .reset(reset), .d(initial_rFF_pt), .q(actual_rFF_pt));
	DFF #(.width($clog2(collection))) DFF_rUP_pt (.clk(clk), .reset(reset), .d(initial_rUP_pt), .q(actual_rUP_pt));
endmodule


// act_ctr is a subset of act_sp_ctr, without sigmoid prime
module act_ctr #(
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 16,
	parameter n  = 8,
	parameter z  = 8,
	parameter L = 3,
	parameter cpc = 6,
	parameter width = 16,
	parameter collection = 2*L-1
)(
	input clk,
	input reset,
	input cycle_clk,
	input [$clog2(cpc)-1:0] cycle_index,
	input [$clog2(p/z)*z-1:0] r_address_raw,
	input [width*z/fo-1:0] data_in,
	// input [z*width-1] w_data,
	// input [collection*z*width-1:0] read_raw,
	// output [z*width-1] r0_data, r1_data,
	// output [collection*z*width-1:0] write_raw,
	output [collection*z*$clog2(p/z)-1:0] act_addr_package,
	output [collection*z-1:0] act_we_package,
	output [collection*z*width-1:0] data_in_mem,
	output [$clog2(collection)-1:0] rFF_pt,
	output [$clog2(collection)-1:0] rUP_pt
);

	wire [$clog2(collection)-1:0]w_pt;
	wire [$clog2(cpc)-1:0]cycle_index_delay;
	wire [$clog2(p/z)*z-1:0] w_address_raw;
	wire [$clog2(p/z)*z-1:0] act_addr[collection-1:0];
	wire [z-1:0] act_we[collection-1:0];

	genvar gv_i, gv_j, gv_k;

	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: package_collection
		assign act_addr_package[z*$clog2(p/z)*(gv_i+1)-1:z*$clog2(p/z)*gv_i] = act_addr[gv_i];
		assign act_we_package[z*(gv_i+1)-1:z*gv_i] = act_we[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: data_collections
		 for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1)
		begin: data_one_collection
			assign data_in_mem[(z*gv_i+z/fo*(gv_j+1))*width-1:(z*gv_i+z/fo*gv_j)*width] = data_in;
		end
	end
	endgenerate

	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1) //choose collection out of collection collections
	begin: act_we_collections
		for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1) //choose part out of fo parts in a collection
		begin: act_we_one_collection
			for (gv_k = 0; gv_k<(z/fo); gv_k = gv_k + 1) //choose memory out of z/fo memories in a part
			begin: act_we_one_cycle
				assign act_we[gv_i][gv_j*z/fo+gv_k] = 
					((cycle_index_delay<p/z*fo) && //check that there are clocks left in cycle
					(gv_j==cycle_index_delay[$clog2(p/z*fo/2)-1:0]) && //check that current clock is referencing correct part
					(gv_i==w_pt) && (!reset))? 1: 0; //check that correct collection is selected and reset is off
			end
		end
	end
	endgenerate
	
	// generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	// begin: act_we_collections
	// 	for (gv_j = 0; gv_j<fo; gv_j = gv_j + 1)
	// 	begin: act_we_one_collection
	// 		for (gv_k = 0; gv_k<(p/z*fo); gv_k = gv_k + 1)
	// 		begin: act_we_one_cycle
	// 			assign act_we[gv_i][gv_j*p/z*fo+gv_k] = 
	// 				((cycle_index_delay<p/z*fo) && 
	// 				(gv_j==cycle_index_delay[$clog2(p/z*fo/2)-1:0]) && 
	// 				(gv_i==w_pt) && (!reset))? 1: 0;
	// 		end
	// 	end
	// end
	// endgenerate

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin: write_address_generator
		assign w_address_raw[$clog2(p/z)*(gv_i+1)-1:$clog2(p/z)*gv_i] 
			= cycle_index_delay[$clog2(cpc)-1:$clog2(fo)];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<collection; gv_i = gv_i + 1)
	begin: addr_collection
		assign act_addr[gv_i] = (gv_i == w_pt)? w_address_raw : r_address_raw;
	end
	endgenerate
	

	counter #(.max(2*L-1), 
		.ini(0)) act_r0
		(cycle_clk, reset, rFF_pt);

	counter #(.max(2*L-1), 
		.ini(1)) act_w
		(cycle_clk, reset, w_pt);

	counter #(.max(2*L-1), 
		.ini(2)) act_r1
		(cycle_clk, reset, rUP_pt);

	shift_reg #(
		.width($clog2(cpc)), 
		.depth(2)
	) cycle_index_reg (
		.clk(clk),
		.reset(reset),
		.data_in(cycle_index),
		.data_out(cycle_index_delay)
	);
endmodule


// For the next 2 modules, refer to slide 19 of Sourya_20160629_DRP.pptx
module address_decoder #(
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 16,
	parameter n  = 8,
	parameter z  = 8
)(
	input [$clog2(p)*z-1:0] memory_index_package, //Neuron from where I should get activation = output of interleaver
	output [$clog2(p/z)*z-1:0] address_package, //[Eg: Slide 19 final output addresses to AMp]
	output [$clog2(z)*z-1:0] mux_sel_package, //control signals for AMp MUXes
	output [$clog2(z)*z-1:0] d_mux_sel_package //control signals for DMp MUXes
);

	wire [$clog2(z)-1:0] insert[z-1:0];
	wire [$clog2(p)-1:0]memory_index[z-1:0];

	genvar gv_i;

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin: address_decoder
		comparator_set #(
			.z(z), 
			.p(p), 
			.number(gv_i)
		) comparator (
			.memory_index_package(memory_index_package),
			.insert(insert [gv_i])
		);
		assign memory_index [gv_i] = memory_index_package [$clog2(p)*(gv_i+1)-1:$clog2(p)*gv_i]; //[Eg: Slide 19 'a' values]
		assign address_package[$clog2(p/z)*(gv_i+1)-1:$clog2(p/z)*gv_i] = memory_index[insert[gv_i]][$clog2(p)-1:$clog2(z)]; //[Eg: Slide 9 'a'[9:6]]
		assign mux_sel_package[$clog2(z)*(gv_i+1)-1:$clog2(z)*gv_i] =  memory_index [gv_i][$clog2(z)-1:0]; //[Eg: Slide 9 'a'[5:0]]
		assign d_mux_sel_package[$clog2(z)*(gv_i+1)-1:$clog2(z)*gv_i] = insert[gv_i];
	end
	endgenerate
endmodule


module comparator_set #(
	parameter z  = 8,
	parameter p  = 16,
	parameter number = 0 //[Eg: In Slide 19, this is the number from which dotted arrow comes out]
)(
	input [$clog2(p)*z-1:0] memory_index_package,
	output reg[$clog2(z)-1:0] insert
);

	wire [$clog2(p)-1:0] memory_index [z-1:0];

	// Unpack
	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin :  ts
		assign memory_index[gv_i] = memory_index_package [$clog2(p)*(gv_i+1)-1:$clog2(p)*gv_i];
	end
	endgenerate
	// Done unpack
	
	integer i;
	always @(memory_index_package) begin
		for (i = 0; i < z; i = i +1) begin
			if ( memory_index[i][$clog2(z)-1:0]==number) //[Eg: From Slide 19, this picks out bits 5:0 for comparison with number]
				insert = i; //[Eg: In slide 19, which AND gate is chosen]
		end
	end
endmodule
