// This file contains all processor sets - feedforward, backpropagation, update
`timescale 1ns/100ps

//This module computes actn, i.e. z activations for the succeeding layer
//Multiplication aw = act*wt happens here, the remaining additions and looking up activation function is done in the submodule sigmoid_function
module FF_processor_set #(
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 16,
	parameter n  = 8,
	parameter z  = 8,
	parameter width = 16, 
	parameter int_bits = 5, 
	parameter frac_bits = 10
)(
	input clk,
	input [width*z -1:0] a_package, //Process z input activations together, each width bits
	input [width*z -1:0] w_package, //Process z input weights together, each width bits
	input [width*z/fi -1:0] b_package, // z/fi is the no. of neurons processed in 1 cycle, so that many bias values
	output [width*z/fi -1:0] sigmoid_package, //output actn values
	output [width*z/fi -1:0] sp_package //output sigmoid prime values (to be used for BP)
);

	// unpack
	wire [width-1:0] a[z-1:0]; //assume always positive (true for sigmoid and relu)
	wire signed [width-1:0] w[z-1:0];
	wire signed [width-1:0] b[z/fi-1:0];
	wire [width-1:0] sigmoid[z/fi-1:0];
	wire [width-1:0] sp[z/fi-1:0];
	
	wire signed [width-1:0] aw[z-1:0]; //a*w
	wire [width*fi-1:0] aw_package[z/fi-1:0]; //1 aw_package value for each output neuron (total z/fi). Each has a width-bit value for each fi, so total width*fi
	
	genvar gv_i, gv_j;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign a[gv_i] = a_package[width*(gv_i+1)-1:width*gv_i];
		assign w[gv_i] = w_package[width*(gv_i+1)-1:width*gv_i];
	end
	endgenerate
	
	generate for (gv_i = 0; gv_i<(z/fi); gv_i = gv_i + 1)
	begin : package_n
		assign sigmoid_package[width*(gv_i+1)-1:width*gv_i] = sigmoid[gv_i];
		assign sp_package[width*(gv_i+1)-1:width*gv_i] = sp[gv_i];
		assign b[gv_i] = b_package[width*(gv_i+1)-1:width*gv_i];
		for (gv_j = 0; gv_j < fi; gv_j = gv_j + 1)
			assign aw_package[gv_i][width*(gv_j+1)-1:width*gv_j]=aw[gv_i*fi+gv_j];
	end
	endgenerate
	// Finished unpacking

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : multiplier
		multiplier #(.width(width), .int_bits(int_bits)) mul ( a[gv_i], w[gv_i], aw[gv_i] );
	end
	endgenerate

	generate for (gv_i = 0; gv_i<(z/fi); gv_i = gv_i + 1)
	begin : sigmoid_function_set
		sigmoid_function #(
			.fo(fo), .fi(fi), .p(p), .n(n), .z(z), .width(width), .frac_bits(frac_bits), .int_bits(int_bits)
		) s_function (
			.clk(clk),
			.aw_package(aw_package[gv_i]),
			.b(b[gv_i]),
			.sigmoid(sigmoid[gv_i]),
			.sp(sp[gv_i])
		);	
	end
	endgenerate
endmodule

// Submodule of FF processor set
// [TODO] generalize this for other activations
module sigmoid_function #( //Computes sigma and sigma prime for ONE NEURON
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 16,
	parameter n  = 8,
	parameter z  = 8,
	parameter width =16,
	parameter width_TA = width + $clog2(fi), //width of tree adder is not compromised
	parameter int_bits = 5, 
	parameter frac_bits = 10
)(
	input clk,
	// All the following parameters are for 1 neuron
	input [width*fi-1:0] aw_package,
	input signed [width-1:0] b,
	output [width-1:0] sigmoid, //actn value
	output [width-1:0] sp //actn' value to be used in BP
);

	/* Create fi-to-1 tree adder
	This needs fi-1 adders [Eg: 4-to-1 tree adder needs 3 2-input adders]
	partial_s [0:fi-1] holds the fi aw values, [Eg 4 aw values] of the neuron in question
	partial_s needs fi-1 more values to hold adder outputs
	So total size of partial_s is 2*fi-1 [Eg: 7]
	pz[4] = pz[1]+pz[0], pz[5]=pz[3]+pz[2]
	Finally pz[6] = pz[4]+pz[5] */
	
	wire signed [width_TA-1:0] partial_s [fi*2-2:0];
	wire signed [width_TA-1:0] s_raw;
	wire signed [width-1:0] s;
	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<fi; gv_i = gv_i + 1)
	begin : unpackage
		// The following line sign extends 'width bit' aw to 'width_TA bit'
		assign partial_s[gv_i] = {{$clog2(fi) {aw_package[width*(gv_i+1)-1]}}, aw_package[width*(gv_i+1)-1:width*gv_i]};
	end
	endgenerate
	// [Eg Now partial_s[3,2,1,0] (each 16b) = aw_package[63:48,47:32,31:16,15:0]]

	generate for (gv_i = 1; gv_i < $clog2(fi)+1; gv_i = gv_i + 1) //This does tree adder computation, i.e. partial_s[f1] to partial_s[2*fi-2]
	begin : tree_adder
		for (gv_j = 0; gv_j < (fi/(2**gv_i)); gv_j = gv_j + 1)
		begin : parallel_adder
			if (gv_i<=2) adder #(.width(width_TA)) adder ( partial_s[fi*2 - fi*2**(2-gv_i) + 2*gv_j],
								partial_s[fi*2 - fi*2**(2-gv_i) + 2*gv_j + 1],
								partial_s[2**($clog2(fi)+1) - 2**($clog2(fi)+1-gv_i) + gv_j] );
			else adder #(.width(width_TA)) adder ( partial_s[fi*2 - fi/2**(gv_i-2) + 2*gv_j],
					partial_s[fi*2 - fi/2**(gv_i-2) + 2*gv_j + 1],
					partial_s[2**($clog2(fi)+1) - 2**($clog2(fi)+1-gv_i) + gv_j] );
		end	
	end
	endgenerate

	adder #(.width(width_TA)) bias_adder (partial_s[fi*2-2], {{$clog2(fi) {b[width-1]}}, b}, s_raw); // The 2nd input is a sign extension of 'width bit' bias to 'width_TA bit'
	// s_raw now has an extra portion consisting of width_TA-width bits and the regular width-bit portion	
	assign s = (s_raw[width_TA-1]==0 && s_raw[width_TA-2:width-1]!=0) ? //check that s_raw is positive and greater than max positive width-bit value
					{1'b0, {(width-1){1'b1}}} : //If yes, assign s to the max positive width-bit value
					(s_raw[width_TA-1]==1 && s_raw[width_TA-2:width-1]!={(width_TA-width){1'b1}}) ? //If no, now check that s_raw is negative and less than max negative width-bit value
					{1'b1, {(width-1){1'b0}}} : //If yes, assign s to the max negative width-bit value
					s_raw[width-1:0]; //If still no, then s_raw is between the limits allowed by width bits. So just assign s to the LSB width bits of s_raw
	sigmoid_table #(.width(width), .frac_bits(frac_bits), .int_bits(int_bits)) s_table (clk, s, sigmoid);
	sigmoid_prime_table #(.width(width), .frac_bits(frac_bits), .int_bits(int_bits)) sp_table (clk, s, sp);
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

//This module computes delp, i.e. z activations for the preceding layer
module BP_processor_set #(
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 16,
	parameter n  = 8,
	parameter z  = 8,
	parameter width = 16,
	parameter frac_bits = 10,
	parameter int_bits = 5
)(
	input [width*z/fi-1:0] deltan_package, //input deln values
	input [width*z -1:0] sp_package, //z weights can belong to z different p layer neurons, so we have z sp values
	input [width*z -1:0] w_package,
	input [width*z -1:0] partial_d_package, //partial delp values being constructed
	output [width*z -1:0] deltap_package //delp values
);

	// Unpack
	wire signed [width-1:0] deltan [z/fi-1:0];
	wire [width-1:0] sp [z-1:0];
	wire signed [width-1:0] partial_d [z-1:0];
	wire signed [width-1:0] w [z-1:0];
	wire signed [width-1:0] deltap [z-1:0];
	wire signed [width-1:0] delta_a [z-1:0];
	wire signed [width-1:0] delta_w [z-1:0];

	reg mem[2:0][3:0];
	genvar gv_i, gv_j;

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign sp[gv_i] = sp_package[width*(gv_i+1)-1:width*gv_i];
		assign w[gv_i] = w_package[width*(gv_i+1)-1:width*gv_i];
		assign partial_d[gv_i] = partial_d_package[width*(gv_i+1)-1:width*gv_i];
		assign deltap_package[width*(gv_i+1)-1:width*gv_i] = deltap[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : package_n
		assign deltan[gv_i] = deltan_package[width*(gv_i+1)-1:width*gv_i];
	end
	endgenerate
	// Finished unpacking

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : delta_accumulation_set
		for (gv_j = 0; gv_j<fi; gv_j = gv_j + 1)
		begin :delta_accumulation
		// [Eg for ppt example: Note that (w.d).f'(z) can be written as w0*d0*f'(z0) + w1*d0*f'(z0) + ... and then later ... w36*d2*f'(z2) ... and so on]
			multiplier #(.width(width),.int_bits(int_bits)) a_d (deltan[gv_i], sp[gv_i*fi+gv_j], delta_a[gv_i*fi+gv_j]); //delta_a = d*f'
			multiplier #(.width(width),.int_bits(int_bits)) w_d (delta_a[gv_i*fi+gv_j], w[gv_i*fi+gv_j], delta_w[gv_i*fi+gv_j]); //delta_w = w*d*f'
			adder #(.width(width)) acc (delta_w[gv_i*fi+gv_j], partial_d[gv_i*fi+gv_j], deltap[gv_i*fi+gv_j]); //Add above to respective delp value
		end
	end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

// This module computes updates to z weights and z/fi biases
module UP_processor_set #(
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 8,
	parameter n  = 4,
	parameter z  = 4,
	parameter width =16,
	parameter int_bits = 5,
	parameter frac_bits = 10, //No. of bits in fractional part
	parameter eta = 4
	//parameter lamda = 1
)(
	// Note that updates are done for z weights in a junction and n neurons in succeeding layer
	//input signed [width-1:0] eta,
	input eta_en,
	inout [width*z/fi-1:0] delta_package, //deln
	input [width*z-1:0] w_package, //Existing weights whose values will be updated
	input [width*z/fi-1:0] b_package, //Existing bias of n neurons whose values will be updated
	input [width*z-1:0] a_package, //actp
	output [width*z-1:0] w_UP_package, //Output weights after update
	output [width*z/fi-1:0] b_UP_package //Output biases after update
);

	//reg [width-1:0] Eta = -eta*2**frac_bits;
	//reg [width-1:0] Lamda = lamda*2**frac_bits;
	
	// Unpack
	wire [width-1:0] a [z-1:0];
	wire signed [width-1:0] w [z-1:0];
	wire signed [width-1:0] b [z/fi-1:0];
	wire signed [width-1:0] delta [z/fi-1:0];
	
	wire signed [width-1:0] delta_w [z-1:0];
	wire signed [width-1:0] w_new [z-1:0];
	wire signed [width-1:0] w_UP [z-1:0];
	
	//wire signed [width-1:0] delta_2c [z/fi-1:0];
	wire signed [width-1:0] delta_b [z/fi-1:0];
	wire signed [width-1:0] b_new [z/fi-1:0];
	wire signed [width-1:0] b_UP [z/fi-1:0];

	genvar gv_i, gv_j;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign w[gv_i] = w_package[width*(gv_i+1)-1:width*gv_i];
		assign a[gv_i] = a_package[width*(gv_i+1)-1:width*gv_i];
		assign w_UP_package[width*(gv_i+1)-1:width*gv_i] = w_UP[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : package_n
		assign delta[gv_i] = delta_package[width*(gv_i+1)-1:width*gv_i];
		assign b[gv_i] = b_package[width*(gv_i+1)-1:width*gv_i];
		assign b_UP_package[width*(gv_i+1)-1:width*gv_i] = b_UP[gv_i];
	end
	endgenerate
	// Finished unpacking

	// generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	// begin : mul_eta
	// 	multiplier mul_eta(delta[gv_i], eta, delta_b[gv_i]);
	// end
	// endgenerate

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin : all_update_set
		assign delta_2c[gv_i] = -delta[gv_i];
		assign delta_b[gv_i] = (eta_en==0) ? {width{1'b0}} :
		(delta_2c[gv_i][width-1]==0) ? {{eta{1'b0}},delta_2c[gv_i][width-1:eta]} :
		{{eta{1'b1}},delta_2c[gv_i][width-1:eta]};
		//assign delta_b[gv_i] = (eta_en==0 || delta[gv_i]=={width{1'b0}}) ? {width{1'b0}} : ($signed(-delta[gv_i]))>>>eta;
		//multiplier #(.width(width),.int_bits(int_bits)) mul_eta(delta[gv_i], eta, delta_b[gv_i]);
		adder #(.width(width)) update_b (b[gv_i], delta_b[gv_i], b_new[gv_i]);
	
		/* lamda factor controlled update of bias (here lamda is NOT used for regularization)
			factor controlled means that if new bias is > lamda*2**int_bits OR < -lamda*2**int_bits, then do NOT update
			Why not set lamda = 1??
				Eg: Say int_bits = 5, old bias = 28 and delta bias = 6
				Then new bias = 29+6 = 35 = -30 (due to wrap-around), which is wrong
				So we include something like lamda = 0.9, so that if new bias is >28.8 or <-28.8, then do not update */
		/*assign b_UP[gv_i] = (b_new[gv_i]<(2**(width-1)-1)*lamda||
					b_new[gv_i]>(2**(width-1)-1)*(2-lamda))? 
					b_new [gv_i] : b[gv_i]; */
		
		assign b_UP[gv_i] = ( b_new[gv_i][width-1]==b[gv_i][width-1] //check if old and new values have same sign. If not, overflow may have occurred
									|| b[gv_i][width-1]!=delta_b[gv_i][width-1] ) ? //OR check if old value and change in value have different signs. If same, overflow may have occurred
									// This takes care of both cases: [old=28, new=-30 (wrap-around is BAD)] and [old=1, new=-1 (this is FINE)]
									b_new[gv_i] : b[gv_i]; //update to new value if all is good, otherwise stick to old value

		for (gv_j = 0; gv_j<fi; gv_j = gv_j + 1)
		begin :weight_update
			multiplier #(.width(width),.int_bits(int_bits)) mul_a_d(delta_b[gv_i], a[gv_i*fi+gv_j], delta_w[gv_i*fi+gv_j]);
			adder #(.width(width)) update_w(w[gv_i*fi+gv_j], delta_w[gv_i*fi+gv_j], w_new[gv_i*fi+gv_j]);
			
			// lamda factor controlled update of weight (here lamda is NOT used for regularization)
			/*assign w_UP[gv_i*fi+gv_j] = (w_new[gv_i*fi+gv_j]<(2**(width-1)-1)*lamda ||
							w_new[gv_i*fi+gv_j]>(2**(width-1)-1)*(2-lamda))? 
							w_new [gv_i*fi+gv_j] : w [gv_i*fi+gv_j];*/

			assign w_UP[gv_i*fi+gv_j] = ( w_new[gv_i*fi+gv_j][width-1]==w[gv_i*fi+gv_j][width-1] //check if old and new values have same sign. If not, overflow may have occurred
									|| w[gv_i*fi+gv_j][width-1]!=delta_w[gv_i*fi+gv_j][width-1] ) ? //OR check if old value and change in value have different signs. If same, overflow may have occurred
									// This takes care of both cases: [old=28, new=-30 (wrap-around is BAD)] and [old=1, new=-1 (this is FINE)]
									w_new[gv_i*fi+gv_j] : w[gv_i*fi+gv_j]; //update to new value if all is good, otherwise stick to old value

			//Regularization: (NOT DONE, so python L2 parameter = 0)
			//multiplier #(.width(width),.int_bits(int_bits)) mul_a_d1(Lamda, w_new [gv_i*fi+gv_j], w_UP[gv_i*fi+gv_j]);
			//assign w_UP[gv_i*fi+gv_j] = w_new [gv_i*fi+gv_j];
		end
	end
	endgenerate
endmodule
