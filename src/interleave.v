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

	always @(cycle_index_i) begin
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

		else if (m == 64)
		case (cycle_index_i[$clog2(m)-1:0])
			0: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd43};
			1: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd29};
			2: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd26};
			3: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd39};
			4: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd37};
			5: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd62};
			6: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd60};
			7: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd11};
			8: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd8};
			9: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd52};
			10: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd59};
			11: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd19};
			12: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd63};
			13: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd22};
			14: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd49};
			15: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd47};
			16: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd45};
			17: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd17};
			18: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd18};
			19: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd48};
			20: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd50};
			21: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd46};
			22: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd9};
			23: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd42};
			24: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd27};
			25: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd2};
			26: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd7};
			27: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd13};
			28: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd23};
			29: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd41};
			30: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd24};
			31: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd20};
			32: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd15};
			33: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd1};
			34: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd58};
			35: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd53};
			36: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd57};
			37: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd0};
			38: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd40};
			39: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd35};
			40: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd61};
			41: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd38};
			42: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd21};
			43: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd44};
			44: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd56};
			45: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd31};
			46: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd6};
			47: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd55};
			48: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd28};
			49: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd16};
			50: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd3};
			51: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd33};
			52: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd12};
			53: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd32};
			54: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd30};
			55: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd34};
			56: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd36};
			57: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd54};
			58: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd51};
			59: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd25};
			60: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd10};
			61: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd5};
			62: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd4};
			63: r_i = {cycle_index_i[$clog2(fo*p)-1:6], 6'd14};
		endcase

		else if (m == 128)
		case (cycle_index_i[$clog2(m)-1:0])
			0: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd25};
			1: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd93};
			2: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd75};
			3: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd20};
			4: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd54};
			5: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd117};
			6: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd32};
			7: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd18};
			8: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd31};
			9: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd104};
			10: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd118};
			11: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd90};
			12: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd127};
			13: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd76};
			14: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd43};
			15: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd85};
			16: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd119};
			17: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd64};
			18: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd1};
			19: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd105};
			20: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd87};
			21: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd96};
			22: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd108};
			23: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd52};
			24: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd92};
			25: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd102};
			26: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd69};
			27: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd112};
			28: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd47};
			29: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd109};
			30: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd86};
			31: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd55};
			32: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd11};
			33: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd33};
			34: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd46};
			35: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd8};
			36: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd0};
			37: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd79};
			38: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd16};
			39: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd125};
			40: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd5};
			41: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd88};
			42: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd80};
			43: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd116};
			44: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd3};
			45: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd41};
			46: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd83};
			47: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd98};
			48: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd42};
			49: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd38};
			50: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd122};
			51: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd6};
			52: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd73};
			53: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd100};
			54: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd37};
			55: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd60};
			56: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd21};
			57: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd57};
			58: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd115};
			59: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd67};
			60: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd35};
			61: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd107};
			62: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd49};
			63: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd95};
			64: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd44};
			65: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd53};
			66: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd36};
			67: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd17};
			68: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd27};
			69: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd61};
			70: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd13};
			71: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd51};
			72: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd2};
			73: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd40};
			74: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd78};
			75: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd15};
			76: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd65};
			77: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd59};
			78: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd84};
			79: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd106};
			80: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd50};
			81: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd101};
			82: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd34};
			83: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd12};
			84: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd62};
			85: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd45};
			86: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd111};
			87: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd91};
			88: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd58};
			89: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd7};
			90: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd66};
			91: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd103};
			92: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd72};
			93: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd120};
			94: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd19};
			95: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd63};
			96: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd28};
			97: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd26};
			98: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd82};
			99: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd110};
			100: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd39};
			101: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd24};
			102: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd94};
			103: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd4};
			104: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd74};
			105: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd71};
			106: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd81};
			107: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd14};
			108: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd114};
			109: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd48};
			110: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd68};
			111: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd56};
			112: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd29};
			113: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd10};
			114: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd121};
			115: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd99};
			116: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd126};
			117: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd89};
			118: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd97};
			119: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd124};
			120: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd22};
			121: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd70};
			122: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd123};
			123: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd23};
			124: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd9};
			125: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd30};
			126: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd113};
			127: r_i = {cycle_index_i[$clog2(fo*p)-1:7], 7'd77};
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

	assign memory_index = w_i[$clog2(p)-1:0];
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
			0: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd5};
			1: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd7};
			2: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd2};
			3: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd0};
			4: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd3};
			5: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd1};
			6: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd6};
			7: w_i = {RP_i[$clog2(fo*p)-1:3], 3'd4};
		endcase
		
		else if (m == 64)
		case (RP_i[$clog2(m)-1:0])
			0: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd61};
			1: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd36};
			2: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd9};
			3: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd0};
			4: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd6};
			5: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd46};
			6: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd40};
			7: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd12};
			8: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd27};
			9: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd17};
			10: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd21};
			11: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd4};
			12: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd7};
			13: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd10};
			14: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd31};
			15: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd13};
			16: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd38};
			17: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd41};
			18: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd5};
			19: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd60};
			20: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd51};
			21: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd2};
			22: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd43};
			23: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd42};
			24: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd57};
			25: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd49};
			26: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd59};
			27: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd22};
			28: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd14};
			29: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd30};
			30: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd58};
			31: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd32};
			32: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd63};
			33: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd18};
			34: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd19};
			35: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd34};
			36: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd25};
			37: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd33};
			38: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd24};
			39: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd52};
			40: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd47};
			41: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd37};
			42: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd55};
			43: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd45};
			44: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd29};
			45: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd3};
			46: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd39};
			47: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd48};
			48: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd23};
			49: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd62};
			50: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd56};
			51: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd28};
			52: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd8};
			53: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd20};
			54: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd44};
			55: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd50};
			56: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd26};
			57: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd15};
			58: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd16};
			59: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd1};
			60: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd54};
			61: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd35};
			62: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd53};
			63: w_i = {RP_i[$clog2(fo*p)-1:6], 6'd1};
		endcase

		else if (m == 128)
		case (RP_i[$clog2(m)-1:0])
			0: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd19};
			1: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd59};
			2: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd22};
			3: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd86};
			4: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd49};
			5: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd50};
			6: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd33};
			7: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd85};
			8: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd5};
			9: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd24};
			10: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd113};
			11: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd70};
			12: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd111};
			13: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd77};
			14: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd44};
			15: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd80};
			16: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd78};
			17: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd29};
			18: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd31};
			19: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd4};
			20: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd110};
			21: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd81};
			22: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd30};
			23: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd99};
			24: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd127};
			25: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd3};
			26: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd6};
			27: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd73};
			28: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd76};
			29: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd14};
			30: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd64};
			31: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd123};
			32: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd115};
			33: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd87};
			34: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd47};
			35: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd104};
			36: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd84};
			37: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd117};
			38: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd9};
			39: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd82};
			40: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd108};
			41: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd88};
			42: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd39};
			43: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd97};
			44: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd62};
			45: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd79};
			46: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd57};
			47: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd34};
			48: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd83};
			49: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd65};
			50: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd72};
			51: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd89};
			52: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd48};
			53: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd17};
			54: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd32};
			55: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd68};
			56: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd13};
			57: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd15};
			58: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd25};
			59: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd20};
			60: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd119};
			61: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd43};
			62: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd21};
			63: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd28};
			64: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd11};
			65: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd60};
			66: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd124};
			67: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd63};
			68: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd95};
			69: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd52};
			70: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd61};
			71: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd74};
			72: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd38};
			73: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd2};
			74: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd18};
			75: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd54};
			76: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd112};
			77: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd42};
			78: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd8};
			79: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd46};
			80: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd103};
			81: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd1};
			82: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd118};
			83: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd40};
			84: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd37};
			85: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd75};
			86: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd92};
			87: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd12};
			88: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd26};
			89: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd16};
			90: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd116};
			91: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd126};
			92: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd90};
			93: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd102};
			94: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd101};
			95: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd23};
			96: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd105};
			97: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd10};
			98: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd36};
			99: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd91};
			100: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd114};
			101: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd96};
			102: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd45};
			103: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd41};
			104: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd51};
			105: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd58};
			106: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd106};
			107: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd56};
			108: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd71};
			109: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd93};
			110: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd121};
			111: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd66};
			112: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd27};
			113: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd125};
			114: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd120};
			115: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd67};
			116: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd7};
			117: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd53};
			118: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd94};
			119: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd109};
			120: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd100};
			121: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd122};
			122: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd0};
			123: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd98};
			124: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd107};
			125: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd69};
			126: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd55};
			127: w_i = {RP_i[$clog2(fo*p)-1:7], 7'd35};
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
