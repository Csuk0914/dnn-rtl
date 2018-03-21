// THIS MODULE DEFINES VARIOUS BASIC COMPONENTS TO BE USED IN THE DESIGN
// Sourya Dey, Yinan Shao, USC

`timescale 1ns/100ps


// Converts {from_sign_bits,from_int_bits,from_frac_bits} input to {sign_bits,int_bits,frac_bits} output
// Can support from_frac_bits = 0 or frac_bits = 0 or both
// Cannot support from_sign_bits=0, sign_bits = 0, from_int_bits = 0, int_bits = 0
//Supports rounding up output based on fractional part, e.g. 7.5 in 1,3,1 becomes 8 in 1,4,0
// Assumes all from_sign bits are the same. If different (exception), the desired output is the max positive value possible
// Eg: Converting from {2,6,16} to {1,3,8}. If the input is 2^6 = 24'b010000... (can be the output of a multiplier), then the sign bits are not the same. In this case, output is 2^3 - 2^-8 = 12'b01111...
module bit_scaler #(
	// If actual frac_bits or from_frac_bits is 0, give it a dummy high value to avoid part select problems 
	
	//Input bit widths
	parameter from_width = 26,
	parameter from_sign_bits = 2,
	parameter from_int_bits = 8,
	localparam from_frac_bits_actual = from_width-from_sign_bits-from_int_bits,
	localparam from_frac_bits = (from_frac_bits_actual == 0) ? from_width : from_frac_bits_actual,
	
	// Output bit widths
	parameter width = 12,
	parameter sign_bits = 1,
	parameter int_bits = 3,
	localparam frac_bits_actual = width-sign_bits-int_bits,
	localparam frac_bits = (frac_bits_actual == 0) ? width : frac_bits_actual	
)(
	input signed [from_width-1:0] in,
	output logic signed [width-1:0] out
);
	//input breakup
	logic signed [from_sign_bits-1:0] in_sign;
	logic signed [from_int_bits-1:0] in_int;
	logic signed [from_int_bits:0] in_intex;
	logic signed [from_frac_bits-1:0] in_frac;
	logic in_leftout_frac = 0; //If from_frac_bits > frac_bits (i.e. truncation), this stores the MSB of left out frac part in input
	
	//output breakup
	logic signed [sign_bits-1:0] out_sign;
	logic signed [int_bits-1:0] out_int;
	logic signed [frac_bits-1:0] out_frac;
	logic signed [width-1:0] out_temp;
	
	//input assignments
	assign in_sign = in[from_width-1 -: from_sign_bits];
	assign in_int = in[from_width-from_sign_bits-1 -: from_int_bits];
	assign in_frac = (from_width-from_sign_bits-from_int_bits == 0) ? '0 : in[from_frac_bits-1:0];
	assign in_intex = {in_sign[0],in_int};
	
	always_comb begin
		out_sign = {sign_bits{in[from_width-1]}};
		if (in[from_width-1] != in[from_width-from_sign_bits]) begin //If sign bits are not the same, result is max positive
			out_int = '1;
			out_frac = '1;
		end else begin
			if (from_int_bits<=int_bits) begin
				out_int = { {(int_bits-from_int_bits){in[from_width-1]}}, in_int }; // small to big : need sign extension
				//BELOW: in case from_frac_bits_actual=0, then out_frac should be all 0s. That will happen in both cases
				if (from_frac_bits<=frac_bits) begin
					out_frac = {in_frac, {(frac_bits-from_frac_bits){1'b0}}}; //small to big : need to add 0s
					if (frac_bits_actual==0)
						in_leftout_frac = in_frac[from_frac_bits-1]; //rounding should happen based on MSB of input frac part
					else //if frac_bits_actual is more than from_frac_bits
						in_leftout_frac = 0; //trivial, since nothing is left out
			 	end else begin //in case from_frac_bits_actual=0, then out_frac should be all 0s, which will happen here
					out_frac = in_frac[from_frac_bits-1 -: frac_bits]; //big to small : need truncation
					if (frac_bits_actual==0)
						in_leftout_frac = in_frac[from_frac_bits-1];
					else //if frac_bits_actual is less than from_frac_bits
						in_leftout_frac = in_frac[from_frac_bits-frac_bits-1]; //take MSB of left out part for rounding
				end
			end else begin
				if (in_intex > 2**int_bits-1) begin //big to small positive overflow, set output to max positive
					out_int = '1;
					out_frac = '1;
				end else if (in_intex < -(2**int_bits)) begin //big to small negative overflow, set output to max negative
					out_int = '0;
					out_frac = '0;
				end else begin
					out_int = in_int[int_bits-1:0]; //big to small normal case, output int bits are LSB int bits of input
					//BELOW: in case from_frac_bits_actual=0, then out_frac should be all 0s. That will happen in both cases
					if (from_frac_bits<=frac_bits) begin
						out_frac = {in_frac, {(frac_bits-from_frac_bits){1'b0}}}; //small to big : need to add 0s
						if (frac_bits_actual==0)
							in_leftout_frac = in_frac[from_frac_bits-1]; //rounding should happen based on MSB of input frac part
						else //if frac_bits_actual is more than from_frac_bits
							in_leftout_frac = 0; //trivial, since nothing is left out
					end else begin //in case from_frac_bits_actual=0, then out_frac should be all 0s, which will happen here
						out_frac = in_frac[from_frac_bits-1 -: frac_bits]; //big to small : need truncation
						if (frac_bits_actual==0)
							in_leftout_frac = in_frac[from_frac_bits-1];
						else //if frac_bits_actual is less than from_frac_bits
							in_leftout_frac = in_frac[from_frac_bits-frac_bits-1]; //take MSB of left out part for rounding
					end
				end
			end
		end	
		if ((width-sign_bits-int_bits)==0) //frac_bits is supposed to be 0
			out_temp = {out_sign, out_int};
		else
			out_temp = {out_sign, out_int, out_frac};
	end
	
	//Round up out if applicable
	assign out = ( in_leftout_frac == 0 || out_temp == {{sign_bits{1'b0}},{(width-sign_bits){1'b1}}} ) ?
					//Rounding up shouldn't be done if out_temp is max positive value
					out_temp : out_temp+1;
endmodule


// Custom made signed multiplier where output is modified to have same fixed point width setup as inputs
// Can use normal logic (parametrizable), or IP (needs to be re-generated for every parameter change)
module multiplier #(
	parameter width = 12,
	parameter int_bits = 3, //No. of bits in integer portion
	localparam frac_bits = width-int_bits-1
)(
	input signed [width-1:0] a, 
	input signed [width-1:0] b, 
	output signed [width-1:0] p 
);
	logic signed [2*width-1:0] p_raw; //Holds full output
	
	assign p_raw = a*b;
	// Can also do the above line with IP
		
	// Elegant, perhaps slow implementation
	/*bit_scaler #(
		.from_width(2*width),
		.from_sign_bits(2),
		.from_int_bits(2*int_bits),
		.width(width),
		.sign_bits(1),
		.int_bits(int_bits)
	) bs_mult (
		.in(p_raw),
		.out(p)
	);*/
	
	//Messy, perhaps fast implementation
	logic signed [width-1:0] p_temp; //1,5,10. Holds truncated output before rounding
	assign p_temp = (p_raw[2*width-1]==0 && p_raw[2*width-2:2*width-int_bits-2]!=0) ? {1'b0, {(width-1){1'b1}}} : //positive overflow => set to max pos value
			(p_raw[2*width-1]==1 && p_raw[2*width-2:2*width-int_bits-2]!={(int_bits+1){1'b1}}) ? {1'b1,{(width-1){1'b0}}} : //negative overflow => set to max neg value
			{p_raw[2*width-1],p_raw[2*width-3-int_bits:width-int_bits-1]}; //no overflow truncated case
		
		/* To understand this, use the fact that MSB of p_raw = 2*width-1 and int_bits+1 from MSB are discarded because multiplier is only used for w*a and w*d.
		Both a and d are <1, so we only need int_bits LSB [Eg: bits 24-20] of the integer part, since int_bits+1 MSB [Eg: bits 30-25] of integer part are always 000000 (pos) or 111111 (neg)
		We also take MSB = sign and frac_bits MSB of frac part [Eg: Bits 19-10]. We discard frac_bits LSB [Eg: Bits 9-0] after using bit[9] to round */
		
		assign p = (p_raw[width-int_bits-2]==0 || p_temp=={1'b0,{(width-1){1'b1}}}) ? //check MSB of left-out frac part in p_raw
			p_temp : // If that is 0, p=p_temp. If that is 1, but p_temp is max positive value, then also p=p_temp (because we don't want overflow)
			p_temp+1; //otherwise round up p to p_temp+1, like 0.5 becomes 1

endmodule


// Saturating adder
module adder #(
	parameter width = 12
)(
	input signed [width-1:0] a,
	input signed [width-1:0] b,
	output signed [width-1:0] s
);
	// Implementation 1: Using same size and overflow checks - *** USES LESS LUTS ***
	logic signed [width-1:0] s_raw;
	assign s_raw = a+b;
	assign s = (a[width-1]==b[width-1] && s_raw[width-1]!=b[width-1]) ? //check for overflow
					(s_raw[width-1]==1'b0) ? //if overflow yes, then check which side
					{1'b1,{(width-1){1'b0}}} : {1'b0,{(width-1){1'b1}}} //most negative or most positive value, depending on s_raw MSB
					: s_raw; //if no overflow, then s = s_raw
					
	/* Track overflow (Simulation only)
	always @(a, b) begin
		if (a[width-1]==b[width-1] && s_raw[width-1]!=b[width-1]) $display("Adder overflow in %m"); //display hierarchy
	end*/
	
					
	//Implementation 2: Using bigger size and limit comparisons - *** USES MORE LUTS ***
	/*logic signed [width:0] s_raw;
	assign s_raw = a+b;
	assign s = (s_raw > 2**(width-1)-1) ? {1'b0,{(width-1){1'b1}}} : (s_raw < -(2**(width-1))) ? {1'b1,{(width-1){1'b0}}} : s_raw;*/

	
	//Implementation 3: Using IP where output is same size as input - *** GIVES WRONG RESULTS WHEN OVERFLOW ***
	/*adder_IP adder_IP_10b (
	  .A(a),  // input wire [9 : 0] A
	  .B(b),  // input wire [9 : 0] B
	  .S(s)  // output wire [9 : 0] S
	);*/
endmodule


// Computes cost term, i.e. vector a-y for output layer of neurons
// Note that (a-y) is used in both quadcost (along with adot) and xentcost (by itself)
module costterm_set #(
	parameter z = 4, //No. of output neurons
	parameter width = 12,
	parameter int_bits = 3,
	localparam frac_bits = width-int_bits-1
)(
	input [width*z-1:0] a_set, //computed output from network
	input [z-1:0] y_set, //ideal output (0 or 1 for each neuron)
	output [width*z-1:0] c_set //packed cost terms
);

	logic signed [width-1:0] a[z-1:0], y[z-1:0], costterm[z-1:0];
	genvar gv_i;

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data
		assign a[gv_i] = a_set[width*(gv_i+1)-1:width*gv_i];
		assign y[gv_i] =  (~{{int_bits{1'b0}},y_set[gv_i],{frac_bits{1'b0}}})+1;
		/*[Eg: Say width = 16, int_bits = 5 => frac_bits = 10]
		Then, if y_set[gv_i]=0, y[gv_i] = 0 00000 0000000000. If y_set[gv_i]=1, y[gv_i] = 1 11111 0000000000
		After this, a[gv_i]+y[gv_i] actually gives the 16-bit appropriate representation of a-y */
		assign c_set[width*(gv_i+1)-1:width*gv_i] = costterm[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : cost_adder_set
		adder #(.width(width))cost_adder(a[gv_i], y[gv_i], costterm[gv_i]);
	end
	endgenerate
endmodule


// count starts at ini upon resetting, increments by 1 every clock, goes from ini to max-1, then back to 0
// max must be >=2
module counter #(
	parameter ini = 0,
	parameter max = 2
)(
	input clk,
	input reset,
	output logic[$clog2(max)-1:0] count = ini
);

	always @(posedge clk) begin
		if (reset)
			count <= ini;
		else if ((count + 1) == max)
			count <= 0;
		else 
			count <= count + 1;
	end
endmodule


// Both these functions start on disabling reset - a) Generate cycle_clk for every cpc clks, b) Count no. of clks till cpc, then loop
// Can be done using IP, however non-IP code should instantiate fine
module cycle_block_counter #(
	parameter cpc = 5
)(
	input clk,
	input reset,
	output logic cycle_clk = 0, //this is the block cycle clock
	output logic [$clog2(cpc)-1:0] count = cpc-1 //counts no. of cycles and resets when a block cycle is reached
);
	always @(posedge clk) begin
		count <= ((reset==1) || (count==cpc-1)) ? 0 : count+1;
		cycle_clk <= ((reset==1) || (count!=cpc-1)) ? 0: 1;
	end
endmodule


module mux #(
	parameter width = 16,
	parameter N = 4 //No. of inputs
)(
	input [width*N-1:0] in_package,
	input [$clog2(N)-(N!=1):0] sel, //The 2nd condition is to prevent [-1:0] sel when N = 1
	output [width-1:0] out
);

	logic [width-1:0] in [N-1:0];
	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<N; gv_i = gv_i + 1)
	begin : package_input
		assign in[gv_i] = in_package[width*(gv_i+1)-1:width*gv_i];
	end
	endgenerate

	assign out = (N==1) ? in[0] : in[sel];
endmodule


// M N-to-1 MUXes, all with common N inputs (different sel combinations)
module mux_set #(
	parameter width = 16,
	parameter N = 4, //No. of inputs
	parameter M = N //No. of MUXes. For our application, generally this will be = N
)(
	input [width*N-1:0] in_package,
	input [$clog2(N)*M-(N!=1):0] sel_package,
	output [width*M-1:0] out_package
);

	logic [width-1:0] out [M-1:0];
	logic [$clog2(N)-(N!=1):0] sel [M-1:0];
	genvar gv_i;

	generate for (gv_i = 0; gv_i<M; gv_i = gv_i + 1)
	begin : package_selout
		if (N==1)
			assign sel[gv_i] = 0;
		else
			assign sel[gv_i] = sel_package[$clog2(N)*(gv_i+1)-1:$clog2(N)*gv_i];
		assign out_package[width*(gv_i+1)-1:width*gv_i] = out[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<M; gv_i = gv_i + 1)
	begin : M_muxes
		mux #(
			.width(width), 
			.N(N)
		) single_mux (
			.in_package(in_package),
			.sel(sel[gv_i]),
			.out(out[gv_i])
		);
	end
	endgenerate
endmodule


// Compare 2 width-bit values and output the greater, as well as its position (see pos)
module max_finder #(
	parameter width = 16
)(
	input signed [width-1:0] a,
	input signed [width-1:0] b,
	output signed [width-1:0] out,
	output pos //0 if a>=b, otherwise 1
);
	assign out = (a>=b)? a : b;
	assign pos = (a>=b)? 1'b0 : 1'b1;
endmodule


// Given N width-bit values, find the max width-bit value out of the N
// Also find its position, e.g. if pos=0110, then the 6th value is the max
module max_finder_set #(
	parameter width = 10,
	parameter N = 13,
	localparam M = 2**$clog2(N),
	localparam poswidth = (M==1) ? 1 : $clog2(M) //this can also be defined as a localparam. param is better since we may want a different width for this settable from outside
)(
	input [width*N-1:0] in,
	output signed [width-1:0] out,
	output [poswidth-1:0] pos
);
	genvar gv_i, gv_j;
	generate
		if (N==1) begin //trivial case
			assign out = in;
			assign pos = 1'b0;
		end
		
		else if (N==2) begin //base case
			max_finder #(
				.width(width)
			) mf2to1 (
				.a(in[width-1:0]),
				.b(in[2*width-1:width]),
				.out(out),
				.pos(pos)
			);
		end
		
		else begin // N>2 => M>=4
			//Idea: Build a binary tree of max finders. There will be M-1 intermdiate max values and positions
			
			logic signed [width-1:0] ein [M-1:0]; //extended in to have 2power values
			for (gv_i=0; gv_i<M; gv_i++) begin: extended_in
				if (gv_i<N)
					assign ein[gv_i] = in[width*(gv_i+1)-1:width*gv_i];
				else
					assign ein[gv_i] = 1<<(width-1); //1 followed by all 0s is the minimum (most negative) number possible
			end
			
			logic [width-1:0] intermeds [M-1:1]; //intermediate max2to1 outputs
			logic [poswidth-1:0] interpos [M-1:1]; //intermediate max pos
			for (gv_j=1; gv_j<=M/2; gv_j++) begin: level1_maxfinder //operate on original inputs and store results in intermeds and interpos
				assign interpos[gv_j][poswidth-1:1] = gv_j-1; //Eg: interpos[0] is comparing between 0 and 1 out of 16, so it has 3 MSB 000, its LSB will be later determined to be either 0 or 1
				max_finder #(
					.width(width)
				) maxf_level1 (
					.a(ein[2*(gv_j-1)]),
					.b(ein[2*gv_j-1]),
					.out(intermeds[gv_j]),
					.pos(interpos[gv_j][0]) //Determine LSB of interpos based on max
				);
			end
			
			//higher levels operate on intermeds. Eg: For M=16, intermeds[0] and [1] are compared and their max stored in interpos[8], [2] and [3] stored in [9], etc
			logic [M/2-1:1] singlepos; //intermediate pos output of higher levels' 2to1 max_finder
			for (gv_i=poswidth-2; gv_i>=0; gv_i--) begin: level2_onwards_maxfinder
				for (gv_j=1; gv_j<=2**gv_i; gv_j++) begin: inside_each_level
					max_finder #(
						.width(width)
					) maxf_level2_onwards (
						.a(intermeds[M - 2**(gv_i+2) + 2*gv_j - 1]),
						.b(intermeds[M - 2**(gv_i+2) + 2*gv_j]),
						.out(intermeds[M + gv_j - 2**(gv_i+1)]),
						.pos(singlepos[M/2 - 2**(gv_i+1) + gv_j])
					);
					assign interpos[M + gv_j - 2**(gv_i+1)] = (singlepos[M/2 - 2**(gv_i+1) + gv_j] == 0) ?
						interpos[M - 2**(gv_i+2) + 2*gv_j - 1] : interpos[M - 2**(gv_i+2) + 2*gv_j]; //interpos [8] gets its value as either interpos[0] or [1] based on singlepos, then [9] gets either [2] or [3], etc
				end
			end
			
			assign out = intermeds[M-1];
			assign pos = interpos[M-1];
		end
	endgenerate
endmodule


// This is a parallel register with synchronous reset, i.e. width 1-bit DFFs
// [MAYBE] Use this for all DFFs not triggered by cycle_clk, i.e. use for all clk triggered DFFs
/******** COMMENT THIS OUT IF NOT USED ********/
module DFF_syncreset #(
	parameter width = 16 //No. of DFFs in parallel
)(
	input clk,
	input reset,
	input [width-1:0] d,
	output logic [width-1:0] q = 0
);
	always @(posedge clk) begin
		if (reset)
			q <= 0;
		else
			q <= d;
	end
endmodule


// This is a parallel register with asynchronous reset, i.e. width 1-bit DFFs
module DFF #(
	parameter width = 16 //No. of DFFs in parallel
)(
	input clk,
	input reset,
	input [width-1:0] d,
	output logic [width-1:0] q = 0
);
	always @(posedge clk, posedge reset) begin
		if (reset)
			q <= 0;
		else
			q <= d;
	end
endmodule

module DFF_no_reset #(
	parameter width = 16 //No. of DFFs in parallel
)(
	input clk,
	input [width-1:0] d,
	output logic [width-1:0] q = 0
);
	always @(posedge clk) q <= d;
endmodule

// This is a serial bank of ASYNC parallel registers, i.e. depth banks, each bank has width 1-bit ASYNC DFFs
module shift_reg #(
	parameter width = 16, //No. of DFFs in parallel
	parameter depth = 8 //No. of serial banks. Must be >= 2
)(
	input clk,
	input reset,
	input [width-1:0] data_in,
	output [width-1:0] data_out // Do NOT set any initial value for this since it's being driven as a wire by the last DFF
);

	logic [width-1:0] mem [0:depth-2];
	
	DFF #( //1st DFF
		.width(width)
	) sr_dff_first (
		.clk,
		.reset,
		.d(data_in),
		.q(mem[0])
	);

	// Maybe other DFFs don't need reset since they get their outputs from the first, which is getting reset ???
	genvar gv_i;
	generate for (gv_i=1; gv_i<depth-1; gv_i++) begin: shift_reg_DFFs
		DFF #( //other DFFs
			.width(width)
		) sr_dffs_mid (
			.clk,
			.reset,
			.d(mem[gv_i-1]),
			.q(mem[gv_i])
		);
	end
	endgenerate

	DFF #( //last DFF
		.width(width)
	) sr_dff_last (
		.clk,
		.reset,
		.d(mem[depth-2]),
		.q(data_out)
	);

	/* Alternate code using register logic
	logic [width-1:0] mem [0:depth-2];
	integer i;
	always @(posedge clk, posedge reset) begin
		if (reset)
			data_out <= {width{1'b0}};
		else begin
			mem[0] <= data_in;
			for (i=1; i<depth-1; i=i+1)
				mem[i] <= mem[i-1];
			data_out <= mem[depth-2];
		end
	end */
endmodule
