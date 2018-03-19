`timescale 1ns/100ps

module address_decoder #(
	parameter p  = 16,
	parameter z  = 8,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_z = (z==1) ? 1 : $clog2(z)
	//Assume p>1
)(
	input [$clog2(p)-1:0] memory_index [z-1:0], //Neurons from where I should get activation = output of interleaver
	output [log_pbyz-1:0] addr [z-1:0], //1 address for each AMp and DMp, total of z. Addresses are log(p/z) bits since each AMp and DMp has that many elements
	output [log_z-1:0] muxsel [z-1:0] //control signals for AMp, ADMp, DMp MUXes
);

	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i++) begin: addr_gen
		if (p==z)
			assign addr[gv_i] = 0;
		else
			assign addr[gv_i] = memory_index[gv_i][$clog2(p)-1:$clog2(z)]; //Address within the memory
		
		assign muxsel[gv_i] = gv_i;
	end
	endgenerate
endmodule


//Controller for weight and bias memories
module wb_mem_ctr #(
	parameter p = 16,
	parameter fo = 2,
	parameter z = 8,
	parameter ec = 2,
	parameter cpc = p*fo/z + ec
)(
	input clk,
	input reset,
	input [$clog2(cpc)-1:0] cycle_index,
	output [z-1:0] weA,
	//No weB necause port B is always used for reading
	output [$clog2(cpc-ec)-1:0] r_addr [z-1:0], //p*fo/z cells in each weight memory, and there are z mems
	output [$clog2(cpc-ec)-1:0] w_addr [z-1:0]
);

	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i++) begin: ctr_generate
		assign weA[gv_i] = (cycle_index>0 && cycle_index <= cpc-ec)? ~reset : 0; //If cycle_index has a valid value and reset is OFF, then all weA = 1
		assign r_addr[gv_i] = cycle_index[$clog2(cpc-ec)-1:0]; //All read addresses = effective cycle_index, since we read the same entry from all memories
		DFF #(
			.width($clog2(cpc-ec))
		) dff_memaddr (
			.clk,
			.reset,
			.d(r_addr[gv_i]),
			.q(w_addr[gv_i])
		); //Because whatever entry we read from all the WMs, same entries are updated 1 cycle later
	end
	endgenerate
endmodule


//Controller for act and adot memories in all hidden layers
module hidden_coll_ctr #(
	parameter width = 12,
	parameter p  = 32,
	parameter fo = 2,
	parameter z  = 8,
	parameter L = 3,
	parameter h = 1,
	parameter ec = 2,
	parameter cpc = p*fo/z + ec,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam collection = 2*(L-h)-1
)(
	input clk,
	input reset,
	input cycle_clk,
	input [$clog2(cpc)-1:0] cycle_index,
	input [log_pbyz-1:0] r_addr_decoded [z-1:0], //addr output of address decoder
	
	// Next 2 inputs are from FF processor of previous layer. Total no. of clocks = p*fo/z. Total act and adot to be inputted = p. So no. of values reqd in each clk = p / p*fo/z = z/fo
	// z/fo memories together is defined as a part. So act_in and adot_in hold all the data for 1 cell of all z/fo memories in a part
	input signed [width-1:0] act_in [z/fo-1:0],
	input signed [width-1:0] adot_in [z/fo-1:0],

	// Signals for AMp
	output [log_pbyz-1:0] act_coll_addr [collection-1:0] [z-1:0], //AMp collections, each has z AMs, each AM has p/z entries, so total address bits = collection*z*log(p/z)
	output [z-1:0] act_coll_we [collection-1:0], //Each AM has 1 we
	output signed [width-1:0] act_coll_in [collection-1:0] [z-1:0], // All data to be written into AM and adot mem in 1 clock. 1 clock writes 1 cell in all memories of each collection
	output signed [width-1:0] adot_coll_in [collection-1:0] [z-1:0],
	
	// Signals for DMp
	output [log_pbyz-1:0] del_coll_addrA [1:0] [z-1:0],
	output [z-1:0] del_coll_weA [1:0],
	output [log_pbyz-1:0] del_coll_addrB [1:0] [z-1:0],
	output [z-1:0] del_coll_weB [1:0],
	output signed [width-1:0] del_coll_partial_inB [1:0] [z-1:0], //write always happens at port B
	output [$clog2(cpc)-1:0] cycle_index_delay,	//1 cycle delay of cycle_index, used for read-modify-write in DM
	
	// Pointers for collections (only 1 bit for BP since there are 2 DM collections)
	output [$clog2(collection)-1:0] act_coll_rFF_pt, //AM collection from which FF is computed for next layer
	output [$clog2(collection)-1:0] act_coll_rUP_pt,	//AM collection used for UP. IMPORTANT: Also collection which provides adot values for current layer BP
	output del_coll_rBP_pt	//DM collection from which BP is computed for previous layer
);

	logic [$clog2(cpc)-1:0] cycle_index_delay2; //2 cycle delay of cycle_index, used for writing to AM
	logic [$clog2(collection)-1:0] act_coll_wFF_pt; //AM collection whose FF is being computed in current layer. IMPORTANT: Also ADM collection currently being written into
	logic [log_pbyz-1:0] wFF_addr [z-1:0]; //interleaved addresses for writing FF being computed	
	logic [log_pbyz-1:0] del_r_addr [z-1:0], del_r_addr_delay [z-1:0]; //see below
	logic [log_pbyz-1:0] r_addr_decoded_delay [z-1:0];

	genvar gv_i, gv_j, gv_k;
	
	// set AMp, ADMp collection address
	generate for (gv_i = 0; gv_i<collection; gv_i++) begin: act_addr_coll
		for (gv_j=0; gv_j<z; gv_j++) begin: act_addr_z
			assign act_coll_addr[gv_i][gv_j] = (gv_i == act_coll_wFF_pt)? wFF_addr[gv_j] : r_addr_decoded[gv_j]; //basically if you are not writing to a collection, you can read from it. Read is not destructive
		end
	end
	endgenerate
	
	//z AMPs are divided into (fo) parts, all parts will be written to in sequence (p/z) times
	//writing is done on every cycle except for the 1st 2 garbage cycles, so work with cycle_index_delay2
	generate for (gv_i = 0; gv_i<collection; gv_i++) begin: act_we_collection
		for (gv_j = 0; gv_j<fo; gv_j++) begin: act_we_part //choose part out of fo parts in a collection
			for (gv_k = 0; gv_k<(z/fo); gv_k++) begin: act_we_mem //choose memory out of z/fo memories in a part
				if (fo>1)
					assign act_coll_we[gv_i][gv_j*z/fo+gv_k] = 
						((cycle_index_delay2 < cpc-ec) && //check that we are not in the 1st 2 garbage cycles
						(gv_j==cycle_index_delay2[$clog2(fo)-1:0]) && //check that current clock is referencing correct part
						(gv_i==act_coll_wFF_pt))? ~reset : 0; //check that correct collection is selected and reset is off
				else
					assign act_coll_we[gv_i][gv_j*z/fo+gv_k] = 
						((cycle_index_delay2 < cpc-ec) && 
						//part has to match because fo=1, so there's only 1 part
						(gv_i==act_coll_wFF_pt))? ~reset : 0;
			end
		end
	end
	endgenerate
		
	//inside a collection, set AMp, ADMp write address = DMp read/write address
	//all z memories have same address at a time
	//since mems are divided into fo parts and 1 part is acessed in a cycle, so an address persists for z/fo consecutive cycles
	generate for (gv_i = 0; gv_i<z; gv_i++) begin: raw_addr_generator
		if (p==z) begin
			assign wFF_addr[gv_i] = 0;
			assign del_r_addr[gv_i] = 0;
		end else begin
			assign wFF_addr[gv_i] = cycle_index_delay2[$clog2(cpc-ec)-1:$clog2(fo)]; //Take all MSB of cycle_index_delay2 except for log(fo) LSB. This is the cell address for writing
			/* [Eg: If p*fo = 4096, z = 64, fo=4, then 1 AMp collection has fo=4 parts, each part has 16 memories, each memory has 16 entries (since p/z=16).
			   cpc = 64. So in 1st cycle, write cell 0 of 1st 16 memories, then cell0 of next 16 memories in next cycle and so on.
			   So cell number remains constant for 4 cycles, so we discard 2 LSB]. Same thing for BP */
			assign del_r_addr[gv_i] = cycle_index[$clog2(cpc-ec)-1:$clog2(fo)];
		end
	end
	endgenerate

	// previous FF computed data to be written to AMp, ADMp
	generate for (gv_i = 0; gv_i<collection; gv_i++) begin: act_in_collection
		for (gv_j = 0; gv_j<fo; gv_j++) begin: act_in_fo
			for (gv_k = 0; gv_k<z/fo; gv_k++) begin: act_in_part
				// z/fo elements of act_in are assigned to each part (out of fo parts) comprising z/fo mems in each collection of act_coll_in
				// 1st write to cell 0 of all mems, by which time cycle_index_delay2[MSB:$clog2(fo)] changes (=> wFF_addr changes), then write to cell 1 of all , ...
				assign act_coll_in[gv_i][gv_j*z/fo+gv_k] = act_in[gv_k];
				assign adot_coll_in[gv_i][gv_j*z/fo+gv_k] = adot_in[gv_k];
			end
		end
	end
	endgenerate
		
/*  Delta memory working:
	There are 2 collections, each has ports A and B, each can read and write and so has write enables
	Assume del_coll_rBP_pt = 1, so collection 1 is being read to compute BP for previous layer, while collection 0 is doing read-modify-write for BP of current layer
	Port A of coll 1 will always be read, so its weA = 0
	Port B of coll 1 must be used for writing. We should write 0 here because this will be the R-M-W collection for the next cycle_clk and will accumulate partial_d, so must start from 0
		So weB will be 1 after 1 clock delay
	Port B of coll 0 will always be read for the R in R-M-W. So its weB = 0
		Note that 0 will be attempted to be written to port B of both collections, but will only succeed for coll 1 because weB of coll 0 = 0
	Port A of coll 0 must be used for the W in R-M-W. So its weA will be 1 after a clk delay
*/
	
	generate for (gv_i = 0; gv_i<2; gv_i++) begin: del_partial_coll
		for (gv_j = 0; gv_j<z; gv_j++) begin: del_partial_z
			assign del_coll_partial_inB[gv_i][gv_j] = '0; //Attempt to write 0 to port B of both collections
		end
	end
	endgenerate

	// DM weA
	generate for (gv_i = 0; gv_i<2; gv_i++) begin: del_weA_coll
		for (gv_j = 0; gv_j<z; gv_j++) begin: del_weA_z
			assign del_coll_weA[gv_i][gv_j] = ((gv_i == del_coll_rBP_pt)||(cycle_index == 0)||(cycle_index>cpc-ec)) ? 0 : 1;
			//From the example in comments, weA of rBP_pt collection = 0 and weA of ~rBP_pt collection = 1, unless it's the 0th clk.
			//We cannot write after cycles are exceeded, so weA will also be 0 for this occasion
		end
	end
	endgenerate

	// DM weB
	generate for (gv_i = 0; gv_i<2; gv_i++) begin: del_weB_coll
		for (gv_j = 0; gv_j<fo; gv_j++) begin: del_weB_fo//choose part out of fo parts in a collection
			for (gv_k = 0; gv_k<(z/fo); gv_k++) begin: del_weB_part //choose memory out of z/fo memories in a part
				if (fo>1)
					assign del_coll_weB[gv_i][gv_j*z/fo+gv_k] = 
						((cycle_index_delay < cpc-ec) &&
						((gv_j)==cycle_index_delay[$clog2(fo)-1:0]) && //check for part match
						(gv_i==del_coll_rBP_pt))? 1 : 0;
				else
					assign del_coll_weB[gv_i][gv_j*z/fo+gv_k] = 
						((cycle_index_delay < cpc-ec) &&
						//part has to match since fo=1
						(gv_i==del_coll_rBP_pt))? 1 : 0;
				// From the example in comments, weB of ~rBP_pt will be 0
				// weB of rBP_pt will be 1 only after 1 clock delay, that is why we use cycle_index_delay in the comparison, and not cycle_index
				// (cycle_index can be used of course, but that would lead to the additional condition of it needing to be greater than 0)
				// Writing 0 is done part by part, so we need to check for part match and write for exactly cpc-ec cycles, otherwise no. of parts will overshoot
			end
		end
	end
	endgenerate
	//NOTE: Both write enables will never be 1 together

	// DM collection Addresses
	generate for (gv_i = 0; gv_i<2; gv_i++) begin: del_addr_coll
		for (gv_j=0; gv_j<z; gv_j++) begin: del_addr_z
			assign del_coll_addrA[gv_i][gv_j] = (gv_i == del_coll_rBP_pt)? del_r_addr[gv_j] : r_addr_decoded_delay[gv_j];
			assign del_coll_addrB[gv_i][gv_j] = (gv_i == del_coll_rBP_pt)? del_r_addr_delay[gv_j] : r_addr_decoded[gv_j];
			/*  For rBP_pt coll, port A (read) address is the one sequentially computed from cycle index, i.e. the one that goes part by part.
					This is because we read DM in sequence for previous layer BP
				For the other (i.e. R-M-W) coll, port A (write) address is as generated from the interleaver, delayed by 1
				For rBP_pt coll, port B (write 0) address = Same as its port A (read) address, delayed by 1
				For the other (i.e. R-M-W) coll, port B (read) address is as generated from the interleaver */
		end
	end
	endgenerate

	// Set pointers for AM and DM collections:
	counter #(
		.max(collection), 
		.ini(0)
	) act_rFF (
		.clk(cycle_clk),
		.reset,
		.count(act_coll_rFF_pt)
	); //AM collection read pointer for next layer FF. Starts from 0, cycles through all collections

	counter #(
		.max(collection), 
		.ini(1)
	) act_wFF (
		.clk(cycle_clk),
		.reset,
		.count(act_coll_wFF_pt)
	); //AM collection write pointer for FF being computed from previous layer. Always the coll after rFF

	counter #(
		.max(collection), 
		.ini(2)
	) act_rUP (
		.clk(cycle_clk),
		.reset,
		.count(act_coll_rUP_pt)
	); //AM collection read pointer for UP (also gives adot for current layer BP). Always the coll 2 after FF

	counter #(
		.max(2), 
		.ini(0)
	) del_r (
		.clk(cycle_clk),
		.reset,
		.count(del_coll_rBP_pt)
	); //DM collection read pointer for previous layer BP

	
	//Set cycle_index delays
	DFF #(
		.width($clog2(cpc))
	) DFF_cycle_index_delay (
		.clk,
		.reset,
		.d(cycle_index),
		.q(cycle_index_delay)
	);
	
	DFF #(
		.width($clog2(cpc))
	) DFF_cycle_index_delay2 (
		.clk,
		.reset,
		.d(cycle_index_delay),
		.q(cycle_index_delay2)
	);

	//Set address delays
	generate for (gv_i=0; gv_i<z; gv_i++) begin: raddr_delay
		DFF #(
			.width(log_pbyz)
		) DFF_r_addr_decoded (
			.clk,
			.reset,
			.d(r_addr_decoded[gv_i]),
			.q(r_addr_decoded_delay[gv_i])
		);
	
		DFF #(
			.width(log_pbyz)
		) DFF_r_addr (
			.clk,
			.reset,
			.d(del_r_addr[gv_i]),
			.q(del_r_addr_delay[gv_i])
		);
	end
	endgenerate
endmodule


// Subset of hidden_coll_ctr: Controller of act memories in input layer (since input has no adot mem previous)
module input_coll_ctr #(
	parameter width = 12,
	parameter p  = 16,
	parameter fo = 2,
	parameter z  = 8,
	parameter L = 3,
	parameter ec = 2,
	parameter cpc = p*fo/z + ec,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam collection = 2*L-1
)(
	input clk,
	input reset,
	input cycle_clk,
	input [$clog2(cpc)-1:0] cycle_index,
	input [log_pbyz-1:0] r_addr_decoded [z-1:0], //addr output of address decoder
	input signed [width-1:0] act_in [z/fo-1:0],
	
	output [log_pbyz-1:0] act_coll_addr [collection-1:0] [z-1:0],
	output [z-1:0] act_coll_we [collection-1:0],
	output signed [width-1:0] act_coll_in [collection-1:0] [z-1:0],
	
	output [$clog2(collection)-1:0] act_coll_rFF_pt,
	output [$clog2(collection)-1:0] act_coll_rUP_pt
);

	logic [$clog2(cpc)-1:0] cycle_index_delay2;
	logic [$clog2(collection)-1:0] act_coll_wFF_pt;
	logic [log_pbyz-1:0] wFF_addr [z-1:0];
	genvar gv_i, gv_j, gv_k;
	
	generate for (gv_i = 0; gv_i<collection; gv_i++) begin: act_addr_collection
		for (gv_j=0; gv_j<z; gv_j++) begin: act_addr_z
			assign act_coll_addr[gv_i][gv_j] = (gv_i == act_coll_wFF_pt)? wFF_addr[gv_j] : r_addr_decoded[gv_j]; //basically if you are not writing to a collection, you can read from it. Read is not destructive
		end
	end
	endgenerate
	
	generate for (gv_i = 0; gv_i<collection; gv_i++) begin: act_we_collection
		for (gv_j = 0; gv_j<fo; gv_j++) begin: act_we_part //choose part out of fo parts in a collection
			for (gv_k = 0; gv_k<(z/fo); gv_k++) begin: act_we_mem //choose memory out of z/fo memories in a part
				if (fo>1)
					assign act_coll_we[gv_i][gv_j*z/fo+gv_k] = 
						((cycle_index_delay2 < cpc-ec) && //check that we are not in the 1st 2 garbage cycles
						(gv_j==cycle_index_delay2[$clog2(fo)-1:0]) && //check that current clock is referencing correct part
						(gv_i==act_coll_wFF_pt))? ~reset : 0; //check that correct collection is selected and reset is off
				else
					assign act_coll_we[gv_i][gv_j*z/fo+gv_k] = 
						((cycle_index_delay2 < cpc-ec) && 
						//part has to match because fo=1, so there's only 1 part
						(gv_i==act_coll_wFF_pt))? ~reset : 0;
			end
		end
	end
	endgenerate
	
	generate for (gv_i = 0; gv_i<z; gv_i++) begin: raw_addr_generator
		if (p==z) begin
			assign wFF_addr[gv_i] = 0;
		end else begin
			assign wFF_addr[gv_i] = cycle_index_delay2[$clog2(cpc-ec)-1:$clog2(fo)]; //Take all MSB of cycle_index_delay2 except for log(fo) LSB. This is the cell address for writing
		end
	end
	endgenerate
	
	generate for (gv_i = 0; gv_i<collection; gv_i++) begin: act_in_collection
		for (gv_j = 0; gv_j<fo; gv_j++) begin: act_in_fo
			for (gv_k = 0; gv_k<z/fo; gv_k++) begin: act_in_part
				// z/fo elements of act_in are assigned to each part (out of fo parts) comprising z/fo mems in each collection of act_coll_in
				assign act_coll_in[gv_i][gv_j*z/fo+gv_k] = act_in[gv_k];
			end
		end
	end
	endgenerate

	counter #(
		.max(collection), 
		.ini(0)
	) act_rFF (
		.clk(cycle_clk),
		.reset,
		.count(act_coll_rFF_pt)
	); //AM collection read pointer for next layer FF. Starts from 0, cycles through all collections

	counter #(
		.max(collection), 
		.ini(1)
	) act_wFF (
		.clk(cycle_clk),
		.reset,
		.count(act_coll_wFF_pt)
	); //AM collection write pointer for FF being computed from previous layer. Always the coll after rFF

	counter #(
		.max(collection), 
		.ini(2)
	) act_rUP (
		.clk(cycle_clk),
		.reset,
		.count(act_coll_rUP_pt)
	); //AM collection read pointer for UP (also gives adot for current layer BP). Always the coll 2 after FF
	
	shift_reg #(
		.width($clog2(cpc)), 
		.depth(2)
	) cycle_index_reg (
		.clk,
		.reset,
		.d(cycle_index),
		.q(cycle_index_delay2)
	);
endmodule


// State machine to input data and output all mem data and control signals, i.e. for AMp, AMn, ADMp, ADMn, DMp, DMn
module hidden_layer_state_machine #(
	parameter width = 16,
	parameter p  = 8,
	parameter fo = 2,
	parameter z  = 4,
	parameter L = 3,
	parameter h = 1, //Index. Layer after input has h = 1, then 2 and so on
	parameter ec = 2,
	parameter cpc = p*fo/z + ec,
	localparam collection = 2*(L-h)-1, //No. of AM and APM collections
	// Note that no. of DM collections is always 2
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_z = (z==1) ? 1 : $clog2(z)
)(
	input clk,
	input reset,
	input cycle_clk,
	input [$clog2(cpc)-1:0] cycle_index,
	
	// Next 2 inputs are from FF processor of previous layer. Total no. of clocks = p*fo/z. Total act and adot to be inputted = p. So no. of values reqd in each clk = p / p*fo/z = z/fo
	// z/fo memories together is defined as a part. So act_in and adot_in hold all the data for 1 cell of all z/fo memories in a part
	input signed [width-1:0] act_in [z/fo-1:0],
	input signed [width-1:0] adot_in [z/fo-1:0],

	// Signals for AMp
	output [log_pbyz-1:0] act_coll_addr [collection-1:0] [z-1:0], //AMp collections, each has z AMs, each AM has p/z entries, so total address bits = collection*z*log(p/z)
	output [z-1:0] act_coll_we [collection-1:0], //Each AM has 1 we
	output signed [width-1:0] act_coll_in [collection-1:0] [z-1:0], // All data to be written into AM and adot mem in 1 clock. 1 clock writes 1 cell in all memories of each collection
	output signed [width-1:0] adot_coll_in [collection-1:0] [z-1:0],
	
	// Signals for DMp
	output [log_pbyz-1:0] del_coll_addrA [1:0] [z-1:0],
	output [z-1:0] del_coll_weA [1:0],
	output [log_pbyz-1:0] del_coll_addrB [1:0] [z-1:0],
	output [z-1:0] del_coll_weB [1:0],
	output signed [width-1:0] del_coll_partial_inB [1:0] [z-1:0], //write always happens at port B
	
	// Pointers for collections (only 1 bit for BP since there are 2 DM collections)
	output [$clog2(collection)-1:0] act_coll_rFF_pt_final, //goes to FF
	output [$clog2(collection)-1:0] act_coll_rUP_pt_final, //goes to UP
	output del_coll_rBP_pt, //choose collection from which read is done for preivous BP. Negation of this will be for write.
	output [$clog2(cpc)-1:0] cycle_index_delay,
	
	output [log_z-1:0] muxsel_final [z-1:0] //Goes to AMp, ADMp, DMp. z MUXes, each of size z, i.e. log(z) select bits
);	

	logic [$clog2(p)-1:0] memory_index [z-1:0]; //Output of z interleavers. Points to all z neurons in p layer from which activations are to be taken for FF
	logic [log_pbyz-1:0] r_addr_decoded [z-1:0]; //z read addresses from all AMp for FF and UP
	//Note that same mem adresses are used for FF collection and UP collection, just because they are different collections, they need different del_coll_rBP_pt values
	logic [log_z-1:0] muxsel_initial [z-1:0]; //z MUXes, each z-to-1, i.e. log(z) select bits
	logic [$clog2(collection)-1:0] act_coll_rFF_pt_initial, act_coll_rUP_pt_initial; //AM collections used for FF and UP

	// Set of z interleaver blocks. Takes cycle index as input, computes interleaved output
	interleaver_set #(
		.p(p),
		.fo(fo), 
	 	.z(z)
	) hidden_interleaver (
		.eff_cycle_index(cycle_index[$clog2(cpc-ec)-1:0]), //if cpc = 3, then $clog2(cpc-ec)-1 = -1. For Verilog, a[-1:0] is a syntax error. So cpc must be > 3
		.reset,
		.memory_index
	);

	address_decoder #(
	 	.p(p),
	 	.z(z)
	) hidden_address_decoder (
		.memory_index,
		.addr(r_addr_decoded),
		.muxsel(muxsel_initial)
	);

	hidden_coll_ctr #(
		.width(width),
		.p(p),
		.fo(fo),
		.z(z), 
		.L(L), 
		.h(h),
		.ec(ec),
		.cpc(cpc)
	) hidden_coll_ctr (
		.clk,
		.reset,
		.cycle_clk,
		.cycle_index,
		.r_addr_decoded,
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
		.cycle_index_delay,
		.act_coll_rFF_pt(act_coll_rFF_pt_initial),
		.act_coll_rUP_pt(act_coll_rUP_pt_initial),
		.del_coll_rBP_pt
	);

	//DFFs used to delay control signals one clock, since memory needs 1 cycle to operate
	DFF #(
		.width($clog2(collection))
	) DFF_act_coll_rFF_pt (
		.clk,
		.reset,
		.d(act_coll_rFF_pt_initial),
		.q(act_coll_rFF_pt_final)
	);
		
	DFF #(
		.width($clog2(collection))
	) DFF_act_coll_rUP_pt (
		.clk,
		.reset,
		.d(act_coll_rUP_pt_initial),
		.q(act_coll_rUP_pt_final)
	);
	
	genvar gv_i;
	generate for (gv_i=0; gv_i<z; gv_i++) begin: muxsel_delay
		DFF #(
			.width(log_z)
		) DFF_muxsel (
			.clk,
			.reset,
			.d(muxsel_initial[gv_i]),
			.q(muxsel_final[gv_i])
		);
	end
	endgenerate	
endmodule


// Subset of input_layer_state_machine: Same as before, except no DM, ADM
module input_layer_state_machine #(
	parameter width = 12,
	parameter p  = 16,
	parameter fo = 2,
	parameter z  = 8,
	parameter L = 3,
	parameter ec = 2,
	parameter cpc = p*fo/z + ec,
	localparam collection = 2*L-1,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z),
	localparam log_z = (z==1) ? 1 : $clog2(z)
)(
	input clk,
	input reset,
	input cycle_clk,
	input [$clog2(cpc)-1:0] cycle_index,	
	input signed [width-1:0] act_in [z/fo-1:0],
	
	output [log_pbyz-1:0] act_coll_addr [collection-1:0] [z-1:0],
	output [z-1:0] act_coll_we [collection-1:0],
	output signed [width-1:0] act_coll_in [collection-1:0] [z-1:0],
	output [$clog2(collection)-1:0] act_coll_rFF_pt_final,
	output [$clog2(collection)-1:0] act_coll_rUP_pt_final,
	output [log_z-1:0] muxsel_final [z-1:0]
);

	logic [$clog2(p)-1:0] memory_index [z-1:0];
	logic [log_pbyz-1:0] r_addr_decoded [z-1:0];
	logic [log_z-1:0] muxsel_initial [z-1:0];
	logic [$clog2(collection)-1:0] act_coll_rFF_pt_initial, act_coll_rUP_pt_initial;

	interleaver_set #(
			.p(p),
			.fo(fo), 
		 	.z(z)
		) input_interleaver (
			.eff_cycle_index(cycle_index[$clog2(cpc-ec)-1:0]), //if cpc = 3, then $clog2(cpc-ec)-1 = -1. For Verilog, a[-1:0] is a syntax error. So cpc must be > 3
			.reset,
			.memory_index
		);

	address_decoder #(
	 	.p(p),
	 	.z(z)
	) input_address_decoder (
		.memory_index,
		.addr(r_addr_decoded),
		.muxsel(muxsel_initial)
	); 

	input_coll_ctr #(
		.width(width),
		.p(p),
		.fo(fo),
		.z(z), 
		.L(L),
		.ec(ec),
		.cpc(cpc)
	) input_coll_ctr (
		.clk,
		.reset,
		.cycle_clk,
		.cycle_index,
		.r_addr_decoded,
		.act_in, 
		.act_coll_addr,
		.act_coll_we,
		.act_coll_in, 
		.act_coll_rFF_pt(act_coll_rFF_pt_initial),
		.act_coll_rUP_pt(act_coll_rUP_pt_initial)
	);
	
	DFF #(
		.width($clog2(collection))
	) DFF_act_coll_rFF_pt (
		.clk,
		.reset,
		.d(act_coll_rFF_pt_initial),
		.q(act_coll_rFF_pt_final)
	);
		
	DFF #(
		.width($clog2(collection))
	) DFF_act_coll_rUP_pt (
		.clk,
		.reset,
		.d(act_coll_rUP_pt_initial),
		.q(act_coll_rUP_pt_final)
	);

	genvar gv_i;
	generate for (gv_i=0; gv_i<z; gv_i++) begin: muxsel_delay
		DFF #(
			.width(log_z)
		) DFF_muxsel (
			.clk,
			.reset,
			.d(muxsel_initial[gv_i]),
			.q(muxsel_final[gv_i])
		);
	end
	endgenerate
endmodule


// State machine for data and control signals of output layer (NOT a subset of anything)
module output_layer_state_machine #(
	parameter width = 16,
	parameter p = 4, //Number of neurons in last layer
	parameter zbyfi = 1,
	parameter ec = 2,
	parameter cpc = p/zbyfi + ec
	//There is no param for log_pbyzbyfi because p*fi/z is always > 1 (from constraints)
	//There is no param for collection because delta memory always has 2 collections in output layer. Each collection is a bunch of z memories, each of size p*fo/z
)(
	input clk,
	input reset,
	input cycle_clk,
	input [$clog2(cpc)-1:0] cycle_index, //This is used for reading in cycles 0,...,cpc-3
	input signed [width-1:0] del_in [zbyfi-1:0], //delta, after it finishes computation from cost terms
	
	output [$clog2(p/zbyfi)-1:0] del_coll_addr [1:0] [zbyfi-1:0], //lump all addresses together: collections * mem/collection * addr_bits/mem
	output [zbyfi-1:0] del_coll_we [1:0],
	output signed [width-1:0] del_coll_in [1:0] [zbyfi-1:0],
	output del_coll_rBP_pt //selects 1 collection. 1b because no. of DM collections is always 2
);

	logic del_coll_wBP_pt_final, del_coll_wBP_pt_initial; //1b because no. of DM collections is always 2
	//del_coll_wBP_pt_initial is collection which will be written in this cycle_clk (cost collection). del_coll_wBP_pt_final is same thing, delayed by 1-2 clocks because write does not start until clk 2.
	logic [$clog2(cpc)-1:0] cycle_index_delay2; //Delayed version of cycle_index by 2 clocks. Used for writing in cycles 2,...,cpc-1
	genvar gv_i, gv_j;
	
	generate for (gv_i=0; gv_i<2; gv_i++) begin: del_in_collection
		for (gv_j=0; gv_j<zbyfi; gv_j++) begin: del_in_z
			assign del_coll_in[gv_i][gv_j] = del_in[gv_j]; //assign input data to memories in both collections, later mux will select 1
		end
	end
	endgenerate

	generate for (gv_i=0; gv_i<2; gv_i++) begin: del_we_coll
		for (gv_j = 0; gv_j<zbyfi; gv_j++) begin: del_we_zbyfi
			assign del_coll_we[gv_i][gv_j] = (del_coll_wBP_pt_final==gv_i && cycle_index >= ec) ? ~reset : 0; //1st cycle is only for read. Write starting from 2nd cycle
			assign del_coll_addr[gv_i][gv_j] = (del_coll_wBP_pt_final==gv_i) ? cycle_index_delay2[$clog2(p/zbyfi)-1:0] : cycle_index[$clog2(p/zbyfi)-1:0];
				//If del_coll_wBP_pt_final equals collection ID (0 or 1), then memory is being written. Write in cycles 2,3,...,cpc-1. Otherwise memory is being read. Read in cycles 0,1,...,cpc-3
		end
	end
	endgenerate

	counter #( //Counter for DM collections. After every cpc clocks (i.e. 1 cycle_clk), changes from 0->1 or 1->0
		.max(2),
		.ini(0)
	) del_rBP (
		.clk(cycle_clk),
		.reset,
		.count(del_coll_wBP_pt_initial)
	); // Note that counter output is del_coll_wBP_pt_initial, which initially points to collection to be written into

	shift_reg #(
		.depth(2),
		.width(1)
	) delay_del_wBP (
		.clk,
		.reset,
		.d(del_coll_wBP_pt_initial),
		.q(del_coll_wBP_pt_final)
	); /* Can use 1 DFF is enough because mem remains idle. In that case, there is no depth parameter
	2 is also fine because the actual delay is 2 (confirm that we use cycle_index_delay2). In that case, add parameter .depth(2) */
	
	assign del_coll_rBP_pt = ~del_coll_wBP_pt_initial; //Read pointer points to the other collection, form where I'm reading values and computing BP for prev layer

	shift_reg #(
		.width($clog2(cpc)), 
		.depth(2)
	) cycle_index_reg (
		.clk,
		.reset,
		.d(cycle_index),
		.q(cycle_index_delay2)
	);
endmodule
