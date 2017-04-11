// THIS MODULE DEFINES VARIOUS BASIC COMPONENTS TO BE USED IN THE DESIGN
`timescale 1ns/100ps

//`define SYNCFF //Uncomment this if synchronous reset DFFs are [also] used

// Custom made signed multiplier where input and outputs all have same bit width
// This is achieved by restricting one of the inputs to [0-1]
//[todo] Extend to [-1,1]
//[todo] a and d have to be between 0-1 to preserve int_bits, frac_bits. Can this be changed?
module multiplier #(
	parameter width = 16,
	parameter int_bits = 5 //No. of bits in integer portion
)(
	input signed [width-1:0] a, //1,5,10
	input signed [width-1:0] b, //1,5,10
	output signed [width-1:0] z //1,5,10
);
	
	wire signed [2*width-1:0] z_raw; //1,10,21
	//assign z_raw = (a[width-2:0] - a[width-1] * 2**(width-1)) * (b[width-2:0] - b[width-1] * 2**(width-1)); //Subtraction converts signed representation to actual number
	assign z_raw = a*b;
	assign z = (z_raw[2*width-1]==0 && z_raw[2*width-2:2*width-int_bits-2]!=0) ? {1'b0, {(width-1) {1'b1}}} : //positive overflow => set to max pos value
		(z_raw[2*width-1]==1 && z_raw[2*width-2:2*width-int_bits-2]!={(int_bits+1) {1'b1}})? {1'b1, {(width-1){1'b0}}} : //negative overflow => set to max neg value
		{z_raw[2*width-1],z_raw[2*width-3-int_bits:width-int_bits-1]} + z_raw[width-int_bits-2]; //normal case. The + is used for rounding
	/* To understand this, use the fact that MSB of z_raw = 2*width-1 and int_bits+1 from MSB are discarded because multiplier is only used for w*a and w*d.
	   Both a and d are <1, so we only need int_bits LSB [Eg: bits 24-20] of the integer part, since int_bits+1 MSB [Eg: bits 30-25] of integer part are always 000000 (pos) or 111111 (neg)
	   We also take MSB = sign and frac_bits MSB of frac part [Eg: Bits 19-10]. We discard frac_bits LSB [Eg: Bits 9-0] after using bit[9] to round */
endmodule


// Custom made signed multiplier set where input and outputs all have same bit width
module multiplier_set #(
	parameter z = 4, //No. of multipliers
	parameter width = 16,
	parameter int_bits = 5
)(
	input [width*z-1:0] a_set,
	input [width*z-1:0] b_set,
	output [width*z-1:0] z_set
);

	wire signed [width-1:0] a[z-1:0], b[z-1:0], out[z-1:0];

	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data
		assign a[gv_i] = a_set[width*(gv_i+1)-1:width*gv_i];
		assign b[gv_i] = b_set[width*(gv_i+1)-1:width*gv_i];
		assign z_set[width*(gv_i+1)-1:width*gv_i] = out[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : multiplier_set
		multiplier #(.width(width),.int_bits(int_bits)) mul (a[gv_i], b[gv_i], out[gv_i]);
	end
	endgenerate
endmodule


// Saturating adder
module adder #(
	parameter width = 16
)(
	input signed [width-1:0] a,
	input signed [width-1:0] b,
	output signed [width-1:0] z
);
	wire signed [width-1:0] z_raw;
	assign z_raw = a+b;
	assign z = (a[width-1]==b[width-1] && z_raw[width-1]!=b[width-1]) ? //check for overflow
					(z_raw[width-1]==1'b0) ? //if overflow yes, then check which side
					{1'b1,{(width-1){1'b0}}} : {1'b0,{(width-1){1'b1}}} //most negative or most positive value, depending on z_raw MSB
					: z_raw; //if no overflow, then z = z_raw 

	/*always @(a, b) begin
		if (a[width-1]==b[width-1] && z_raw[width-1]!=b[width-1]) $display("Adder overflow in %m"); //display hierarchy
	end*/
endmodule


// Computes cost term, i.e. vector a-y for output layer of neurons
// Note that (a-y) is used in both quadcost (along with sp) and xentcost (by itself)
module costterm_set #(
	parameter z = 4, //No. of output neurons
	parameter width = 16,
	parameter int_bits = 5,
	parameter frac_bits = 10
)(
	input [width*z-1:0] a_set, //computed output from network
	input [z-1:0] y_set, //ideal output (0 or 1 for each neuron)
	output [width*z-1:0] c_set //packed cost terms
);

	wire signed [width-1:0] a[z-1:0], y[z-1:0], costterm[z-1:0];

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


// count starts at ini upon resetting, increments by 1 every clock, goes from max-1 to 0
module counter #(
	parameter ini = 0,
	parameter max = 2
)(
	input clk,
	input reset,
	output reg[$clog2(max)-1:0] count = ini
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


// Both these functions start on lowering reset - a) Generate cycle_clk for every cpc clks, b) Count no. of clks till cpc, then loop
module cycle_block_counter #(
	parameter cpc = 6 //expected cpc
)(
	input clk,
	input reset,
	output reg cycle_clk = 0, //this is the block cycle clock
	output reg [$clog2(cpc)-1:0] count = cpc-1 //counts no. of cycles and resets when a block cycle is reached
);

	always @(posedge clk) begin
		if (reset) begin
			count <= 0;
			cycle_clk = 0;
		end else begin //reset is off
			if(count == cpc-1) begin
				count <= 0;
				cycle_clk = 1;
			end else begin
				count <= count + 1;
				cycle_clk = 0;
			end
		end
	end
endmodule


module mux #(
	parameter width = 16,
	parameter N = 4 //No. of inputs. Has to be greater than 0 and ideally shouldn't be 1
)(
	input [width*N-1:0] in_package,
	input [$clog2(N)-(N!=1):0] sel, //The 2nd condition is to prevent [-1:0] sel when N = 1
	output [width-1:0] out
);

	wire [width-1:0] in [N-1:0];

	genvar gv_i;

	generate for (gv_i = 0; gv_i<N; gv_i = gv_i + 1)
	begin : package_input
		assign in[gv_i] = in_package[width*(gv_i+1)-1:width*gv_i];
	end
	endgenerate

	assign out = in [sel];
endmodule


// M N-to-1 MUXes, all with common N inputs (different sel combinations)
module mux_set #(
	parameter width = 16,
	parameter N = 4, //No. of inputs. Has to be greater than 0 and ideally shouldn't be 1
	parameter M = N //No. of MUXes. For our application, generally this will be = N
)(
	input [width*N-1:0] in_package,
	input [$clog2(N)*M-(N!=1):0] sel_package,
	output [width*M-1:0] out_package
);

	wire [width-1:0] out [M-1:0];
	wire [$clog2(N)-(N!=1):0] sel [M-1:0];

	genvar gv_i;

	generate for (gv_i = 0; gv_i<M; gv_i = gv_i + 1)
	begin : package_selout
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

// Given N width-bit values (packed as a N*width-bit 1D array), find the max width-bit value out of the N
// Also find its position, e.g. is pos=0110, then the 6th value out of a possible 16 is the max
module max_finder_set #(
	parameter width = 16,
	parameter N = 16,
	parameter poswidth = (N==1) ? 1 : $clog2(N)
)(
	input [width*N-1:0] in,
	output signed [width-1:0] out,
	output [poswidth-1:0] pos
);
	wire [width*(N-1)-1:0] intermeds; //intermediate max2to1 outputs
	wire [$clog2(N)*(N-1)-1:0] interpos; //intermediate max pos
	wire [N/2-2:0] singlepos; //intermediate pos output of 2to1 max_finder
	genvar gv_i, gv_j;
	generate
		if (N==1) begin //trivial case
			assign out = in;
			assign pos = 1'b0;
		end
		else if (N==2) begin //base case
			max_finder #(.width(width)) mf2to1 (.a(in[width-1:0]),.b(in[2*width-1:width]),.out(out),.pos(pos));
		end
		else begin //N>2
			for (gv_i=$clog2(N)-1; gv_i>=0; gv_i=gv_i-1) begin: max_finder_levels
				for (gv_j=0; gv_j<2**gv_i; gv_j=gv_j+1) begin
					if (gv_i==$clog2(N)-1) begin //1st level of 2to1 maxfinders which operate directly on inputs
						assign interpos[(gv_i+1)*gv_j+gv_i:(gv_i+1)*gv_j+1] = gv_j;
						max_finder #(
							.width(width)
						) maxf_level1 (
							.a(in[(2*gv_j+1)*width-1:2*gv_j*width]),
							.b(in[2*(gv_j+1)*width-1:(2*gv_j+1)*width]),
							.out(intermeds[(gv_j+1)*width-1:gv_j*width]),
							.pos(interpos[(gv_i+1)*gv_j])
						);
					end
					else begin //2nd level onwards, which operate with intermeds as both inputs and outputs
						max_finder #(
							.width(width)
						) maxf_biglevels (
							.a(intermeds[(N-2**(gv_i+2)+2*gv_j+1)*width-1:(N-2**(gv_i+2)+2*gv_j)*width]),
							.b(intermeds[(N-2**(gv_i+2)+2*gv_j+2)*width-1:(N-2**(gv_i+2)+2*gv_j+1)*width]),
							.out(intermeds[(N+gv_j+1-2**(gv_i+1))*width-1:(N+gv_j-2**(gv_i+1))*width]),
							.pos(singlepos[N/2-2**(gv_i+1)+gv_j])
						);
						assign interpos[(N+gv_j-2**(gv_i+1))*$clog2(N)+$clog2(N)-1:(N+gv_j-2**(gv_i+1))*$clog2(N)] =
							(singlepos[N/2-2**(gv_i+1)+gv_j]==0) ?
							interpos[(N-2**(gv_i+2)+2*gv_j)*$clog2(N)+$clog2(N)-1:(N-2**(gv_i+2)+2*gv_j)*$clog2(N)] :
							interpos[(N-2**(gv_i+2)+2*gv_j+1)*$clog2(N)+$clog2(N)-1:(N-2**(gv_i+2)+2*gv_j+1)*$clog2(N)];
					end
				end
			end
			assign out = intermeds[width*(N-1)-1:width*(N-2)];
			assign pos = interpos[$clog2(N)*(N-1)-1:$clog2(N)*(N-2)];
		end
	endgenerate
endmodule


// This is a parallel register with asynchronous reset, i.e. width 1-bit DFFs
// Changing to synchronous reset by deleting @posedge reset does NOT work [TODO] WHY??
module DFF #(
	parameter width = 16 //No. of DFFs in parallel
)(
	input clk,
	input reset,
	input [width-1:0] d,
	output reg [width-1:0] q
);
	always @(posedge clk, posedge reset) begin
		if (reset)
			q <= {width{1'b0}};
		else
			q <= d;
	end
endmodule

// This is a parallel register with synchronous reset, i.e. width 1-bit DFFs
// [TODO] Use this for all DFFs not triggered by cycle_clk, i.e. use for all clk triggered DFFs
/*module DFF_syncreset #(
	parameter width = 16 //No. of DFFs in parallel
)(
	input clk,
	input reset,
	input [width-1:0] d,
	output reg [width-1:0] q
);
	always @(posedge clk) begin
		if (reset)
			q <= {width{1'b0}};
		else
			q <= d;
	end
endmodule*/


// This is a serial bank of parallel registers, i.e. depth banks, each bank has width 1-bit async DFFs
module shift_reg #(
	parameter width = 16, //No. of DFFs in parallel
	parameter depth = 8 //No. of serial banks. Must be >= 2
)(
	input clk,
	input reset,
	input [width-1:0] data_in,
	output [width-1:0] data_out
);

	wire [width-1:0] mem [depth-1:0];
	assign data_out = mem[depth-1];
	
	genvar i;

	DFF #( //1st DFF
		.width(width)
	) shift_reg_0 (
		.clk(clk),
		.reset(reset),
		.d(data_in),
		.q(mem[0])
	);
	generate for (i=1; i<depth; i=i+1)
	begin: shift_reg
		DFF #( //another depth-1 DFFs
			.width(width)
		) shift_reg_dff (
			.clk(clk),
			.reset(reset),
			.d(mem[i-1]),
			.q(mem[i])
		);
	end
	endgenerate
endmodule
