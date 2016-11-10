`timescale 1ns/100ps

// This is a SPECIFIC DRP interleaver, it is only parameterized for s and p, NOT for r and w dither vectors
module interleaver_set #( //All z DRP interleavers together
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 16,
	parameter n  = 8,
	parameter z  = 8,
	parameter DRP_s = 3,
	parameter DRP_p = (z==4 && p*fo==16)? 11 : (z==8)? 23 : (z==32)? 15 : 3,
	parameter m = z/fo
)(
	input [$clog2(fo*p/z)-1:0] cycle_index, //log of total number of cycles to process a junction = log(no. of weights / z)
	output [$clog2(p)*z-1:0] memory_index_package //This has all addresses [Eg: Here this has z=8 4b values, indexing the 8 neurons which need to be accessed out of 16 input neurons]
);

	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1) //Create z interleavers
	begin : maid	
		interleaver #(
			.i(gv_i),
			.fo(fo),
			.fi(fi),
			.p(p),
			.n(n),
			.z(z),
			.DRP_s(DRP_s),
			.DRP_p(DRP_p),
			.m(m)
		) DRP (
			.cycle_index(cycle_index),
			.memory_index(memory_index_package[$clog2(p)*(gv_i+1)-1:$clog2(p)*gv_i])
		);
	end
	endgenerate
	/* wire [$clog2(p)-1:0] memory_index [z-1:0];
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin :  ts
		assign memory_index[gv_i] = memory_index_package [$clog2(p)*(gv_i+1)-1:$clog2(p)*gv_i];
	end
	endgenerate */
endmodule

module interleaver #( //This is 1 DRP interleaver, i.e. SISO
	parameter i   = 0,
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 16,
	parameter n  = 8,
	parameter z  = 8,
	parameter DRP_s  = 3,
	parameter DRP_p  = 23,
	parameter m = z/fo
)(
	input [$clog2(fo*p/z)-1:0] cycle_index, //[Eg: Here total no. of cycles to process a junction = 4, so cycle_index is 2b. It goes as 00 -> 01 -> 10 -> 11]
	output [$clog2(p)-1:0] memory_index //This is the address identifying 1 out of the p neurons [Eg: Here it's 4b]
);
	
	// All intermediate interleavers are [Eg: 5b] long, since there are [Eg: fo*p=32] weights
	wire [$clog2(fo*p)-1:0]r_i;
	wire [$clog2(fo*p)-1:0]RP_i;

// STAGE 1: READ DITHER : Takes cycle index as input and produces r_i as output
	//assign r_i = {cycle_index, r[i]};
	r_dither  #(
		.fo(fo),
		.p(p),
		.z(z),
		.i(i),
		.m(m)
	) r_d (
		.cycle_index(cycle_index),
		.r_i(r_i)
	);
	
// STAGE 2: RP INTERLEAVER : Takes r_i as input and produces RP_i as output
	assign RP_i = (DRP_s + r_i * DRP_p) % (fo * p);
	 /* RP 	#(
		.fo(fo),
	 	.p(p),
	 	.z(z)) RP(r_i, RP_i); */
		 
// STAGE 3: WRITE DITHER : Takes RP_i as input and produces memory_index as output. This is the final output
	w_dither  #(
		.fo(fo),
		.p(p),
		.z(z),
		.m(m)
	) w_d (
		.RP_i(RP_i),
		.memory_index(memory_index)
	);
	//assign memory_index = {RP_i[$clog2(fo*p)-1:$clog2(fo*p/z)], w[RP_i[$clog2(fo*p/z)-1:0]]}/fo;
endmodule

module r_dither #( //Take single number cycle index input and calculates its read interleaved value, i.e. from 2b cycle index to 5b interleaved value
	parameter fo = 2,
	parameter p  = 16,
	parameter z  = 8,
	parameter i   = 0,
	parameter m = z/fo //Based on our original hypothesis that z = fo*m
)(
	input [$clog2(fo*p/z)-1:0]cycle_index,
	output reg[$clog2(fo*p)-1:0]r_i //read interleaved value
);

	wire [$clog2(z)-1:0] i_net;
	wire [$clog2(p*fo)-1:0] cycle_index_i;

	assign i_net = i;
	assign cycle_index_i = {cycle_index, i_net};

	always @(cycle_index) begin
		if (m == 2)
		case (cycle_index_i[$clog2(m)-1:0]) //Read dither = {1,0}
			0: r_i = {cycle_index_i[$clog2(fo*p)-1:1], 1'b1};
			1: r_i = {cycle_index_i[$clog2(fo*p)-1:1], 1'b0};
		endcase

		else if (m == 4)
		case (cycle_index_i[$clog2(m)-1:0]) //Read dither = {1,2,3,0}
			0: r_i = {cycle_index_i[$clog2(fo*p)-1:2], 2'd1};
			1: r_i = {cycle_index_i[$clog2(fo*p)-1:2], 2'd2};
			2: r_i = {cycle_index_i[$clog2(fo*p)-1:2], 2'd3};
			3: r_i = {cycle_index_i[$clog2(fo*p)-1:2], 2'd0};
		endcase
		
		else if (m == 8)
		case (cycle_index_i[$clog2(m)-1:0])
			0: r_i = {cycle_index_i[$clog2(fo*p)-1:3], 3'd3};
			1: r_i = {cycle_index_i[$clog2(fo*p)-1:3], 3'd5};
			2: r_i = {cycle_index_i[$clog2(fo*p)-1:3], 3'd2};
			3: r_i = {cycle_index_i[$clog2(fo*p)-1:3], 3'd7};
			4: r_i = {cycle_index_i[$clog2(fo*p)-1:3], 3'd0};
			5: r_i = {cycle_index_i[$clog2(fo*p)-1:3], 3'd6};
			6: r_i = {cycle_index_i[$clog2(fo*p)-1:3], 3'd1};
			7: r_i = {cycle_index_i[$clog2(fo*p)-1:3], 3'd4};
		endcase
		
		// IMPORTANT: Sometimes, when running a smaller DNN, the part selection here can be small to big, i.e. something like cycle_index_i[3:4]
		// This might give errors in Vivado, so this will need to be commented out
		/*else if (m == 16)
		case (cycle_index_i[$clog2(m)-1:0])
			0: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd1};
			1: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd6};
			2: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd8};
			3: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd9};
			4: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd13};
			5: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd4};
			6: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd2};
			7: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd14};
			8: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd10};
			9: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd7};
			10: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd15};
			11: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd11};
			12: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd3};
			13: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd0};
			14: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd5};
			15: r_i = {cycle_index_i[$clog2(fo*p)-1:4], 4'd12};
		endcase*/
	end
endmodule


module w_dither #( //Take RP output and calculate final DRP output
	parameter fo = 2,
	parameter p  = 16,
	parameter z = 8,
	parameter m = z/fo //Based on our original hypothesis that z = fo*m
)(
	input [$clog2(fo*p)-1:0]RP_i,
	output [$clog2(p)-1:0]memory_index  //final drp output
);
	reg [$clog2(p*fo)-1:0] w_i;

	assign memory_index = w_i[$clog2(p*fo)-1:$clog2(fo)];
	always @(RP_i) begin
		if (m == 2)
		case (RP_i[$clog2(m)-1:0])
			0: w_i = {RP_i[$clog2(fo*p)-1:1], 1'b1};
			1: w_i = {RP_i[$clog2(fo*p)-1:1], 1'b0};
		endcase

		else if (m == 4)
		case (RP_i[$clog2(m)-1:0])
			0: w_i = {RP_i[$clog2(fo*p)-1:2], 2'd1};
			1: w_i = {RP_i[$clog2(fo*p)-1:2], 2'd2};
			2: w_i = {RP_i[$clog2(fo*p)-1:2], 2'd3};
			3: w_i = {RP_i[$clog2(fo*p)-1:2], 2'd0};
		endcase
		
		else if (m == 8)
		case (RP_i[$clog2(m)-1:0])
			0: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd3};
			1: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd5};
			2: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd2};
			3: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd7};
			4: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd0};
			5: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd6};
			6: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd1};
			7: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd4};
		endcase
		
		// IMPORTANT: Sometimes, when running a smaller DNN, the part selection here can be small to big, i.e. something like cycle_index_i[3:4]
		// This might give errors in Vivado, so this will need to be commented out
		/*else if (m == 16)
		case (RP_i[$clog2(m)-1:0])
			0: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd5};
			1: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd8};
			2: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd4};
			3: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd9};
			4: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd0};
			5: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd13};
			6: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd10};
			7: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd14};
			8: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd11};
			9: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd7};
			10: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd1};
			11: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd12};
			12: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd2};
			13: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd15};
			14: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd3};
			15: w_i = {RP_i[$clog2(fo*p)-1:4], 4'd6};
		endcase*/
	end
endmodule
