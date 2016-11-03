// THIS MODULE DEFINES VARIOUS BASIC COMPONENTS TO BE USED IN THE DESIGN
`timescale 1ns/100ps

// Custom made signed multiplier where input and outputs all have same bit width
//[todo] a and d have to be between 0-1 to preserve int_bits, frac_bits. Can this be changed?
module multiplier #(
	parameter width = 16,
	parameter int_bits = 5 //No. of bits in integer portion
)(
	input [width-1:0] a, //1,5,10
	input [width-1:0] b, //1,5,10
	output [width-1:0] z //1,5,10
);
	
	wire [2*width-2:0] z_raw; //1,10,20. Overall 1 bit less because sign bit doesn't get replicated
	assign z_raw = (a[width-2:0] - a[width-1] * 2**(width-1)) * (b[width-2:0] - b[width-1] * 2**(width-1)); //Subtraction converts signed representation to actual number
	assign z = {z_raw[2*width-2],z_raw[2*width-2-int_bits-1:width-int_bits-1]};
	/* To understand this, use the fact that MSB of z_raw = 2*width-2 and int_bits from MSB are discarded because multiplier is only used for w*a and w*d.
	   Both a and d are <1, so we only need int_bits LSB [Eg: bits 24-20] of the integer part, since int_bits MSB [Eg: bits 29-24] of integer part are always 00000 (pos) or 11111 (neg)
	   We also take MSB = sign and frac_bits MSB of frac part [Eg: Bits 19-10]. We discard frac_bits LSB [Eg: Bits 9-0]. Note that frac_bits = width-int_bits-1 */
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

	wire [width-1:0] a[z-1:0], b[z-1:0], out[z-1:0];

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


module adder #(
	parameter width = 16
)(
	input [width-1:0] a,
	input [width-1:0] b,
	output [width-1:0] z
);
	assign z = a+b; //(a[14:0] - a[15] * 2 ** 15) + (b[14:0] - b[15] * 2 ** 15);
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

	wire [width-1:0] a[z-1:0], y[z-1:0], costterm[z-1:0];

	genvar gv_i;

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data
		assign a[gv_i] = a_set[width*(gv_i+1)-1:width*gv_i];
		assign y[gv_i] =  (~{{int_bits{1'b0}},y_set[gv_i],{frac_bits{1'b0}}})+1;
		/*[Eg: Say width = 16, int_bits = 5 => frac_bits = 10]
		Then, if y_set[gv_i]=0, y[gv_i] = 00000 0 0000000000. If y_set[gv_i]=1, y[gv_i] = 11111 1 0000000000
		After this, a[gv_i]+y[gv_i] actually gives the 16-bit appropriate representation of a-y */
		assign c_set[width*(gv_i+1)-1:width*gv_i] = costterm[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : cost_adder_set
		adder cost_adder(a[gv_i], y[gv_i], costterm[gv_i]);
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
			count <= cpc-1; //count stays at highest value during reset, so that it becomes 0 on next clk
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


// This is a parallel register, i.e. width 1-bit DFFs
module DFF #(
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
endmodule


// This is a serial bank of parallel registers, i.e. depth banks, each bank has width 1-bit DFFs
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
