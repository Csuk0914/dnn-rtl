// This file contains all processor sets - feedforward, backpropagation, update
// Sourya Dey, Yinan Shao, USC

`timescale 1ns/100ps

//This module computes actn and adotn, i.e. z activations and their derivatives for the succeeding layer
module FF_processor_set #(
	parameter fi  = 4,
	parameter z  = 8,
	parameter width = 12, 
	parameter int_bits = 3, 
	localparam frac_bits = width-int_bits-1,
	localparam width_TA = 2*width + $clog2(fi),
	parameter actfn = 0 //0 for sigmoid, 1 for ReLU
)(
	input clk,
	input signed [width-1:0] act_in [z-1:0], //Process z input activations together, each width bits
	input signed [width-1:0] wt [z-1:0], //Process z input weights together, each width bits
	input signed [width-1:0] bias [z/fi-1:0], // z/fi is the no. of neurons processed in 1 cycle, so that many bias values
	output signed [width-1:0] act_out [z/fi-1:0], //output actn values
	output signed [width-1:0] adot_out [z/fi-1:0] //output sigmoid prime values (to be used for BP)
);

	logic signed [2*width-1:0] actwt [z-1:0]; //act*wt
	logic signed [2*width-1:0] actwt_fi_partitioned [z/fi-1:0] [fi-1:0];
	logic signed [width_TA-1:0] actwt_dot [z/fi-1:0]; //actwt dot product for 1 neuron
	logic signed [width_TA-1:0] bias_scaled [z/fi-1:0]; //bias bit-scaled to 2,(2*int_bits+log(fi)),2*frac_bits
	logic signed [width_TA-1:0] s_scaled [z/fi-1:0]; //actwt_dot+bias for 1 neuron in config 2,(2*int_bits+log(fi)),2*frac_bits
	logic signed [width-1:0] s [z/fi-1:0]; //actwt_dot+bias for 1 neuron scaled back to original width
	genvar gv_i, gv_j;
	
	generate for (gv_i = 0; gv_i<z; gv_i++) begin: actwtFF_mult
		//Non-IP
		assign actwt[gv_i] = act_in[gv_i]*wt[gv_i];
		
		//IP
		/*mult_IP_LUT mult_actwt (
		  .A(act_in[gv_i]),  // input wire [11 : 0] A
		  .B(wt[gv_i]),  // input wire [11 : 0] B
		  .P(actwt[gv_i])  // output wire [23 : 0] P
		);*/
	end
	endgenerate

	generate for (gv_i=0; gv_i<z/fi; gv_i++) begin: FF_single_neuron
		for (gv_j=0; gv_j<fi; gv_j++) begin: partition_actwt
			assign actwt_fi_partitioned[gv_i][gv_j] = actwt[gv_i*fi+gv_j];
		end
		
		// Use tree adder to add actwt and get dot product
		tree_adder #(
			.fi(fi),
			.width(width)
		) ta_singleneuron (
			.actwt(actwt_fi_partitioned[gv_i]), //actwt is 2,6,16
			.actwt_dot(actwt_dot[gv_i]) //Example: fi=4, then actwtdot is 2,8,16
		);
		
		// Bias is 1,3,8, needs to be converted to 2,8,16
		bit_scaler #(
			.from_width(width),
			.from_sign_bits(1),
			.from_int_bits(int_bits),
			.width(width_TA),
			.sign_bits(2),
			.int_bits(2*int_bits+$clog2(fi))
		) bs_bias (
			.in(bias[gv_i]),
			.out(bias_scaled[gv_i])
		);
				
		// Add bias to dot product
		adder #(
			.width(width_TA)
		) bias_adder (
			.a(actwt_dot[gv_i]),
			.b(bias_scaled[gv_i]),
			.s(s_scaled[gv_i])
		);
		
		// Scale number of bits back to original config, like 1,3,8
		bit_scaler #(
			.from_width(width_TA),
			.from_sign_bits(2),
			.from_int_bits(2*int_bits+$clog2(fi)),
			.width(width),
			.sign_bits(1),
			.int_bits(int_bits)
		) bs_FF_final (
			.in(s_scaled[gv_i]),
			.out(s[gv_i])
		);
		
		//Compute activation and its derivative
		if (actfn==0) begin: sigmoid //Read values from LUTs stored in separate file
			sigmoid_all #(
				.width(width),
				.int_bits(int_bits)
			) s_all (
				.clk,
				.val(s[gv_i]),
				.sigmoid_out(act_out[gv_i]),
				.sigmoid_prime_out(adot_out[gv_i])
			);	
		end else if (actfn==1) begin: relu
			relu_all #(
				.width(width),
				.int_bits(int_bits)
			) s_all (
				.clk,
				.val(s[gv_i]),
				.relu_out(act_out[gv_i]),
				.relu_prime_out(adot_out[gv_i])
			);
		end
	end
	endgenerate
endmodule

// Submodule of FF processor set, used to add all actwt values for ONE neuron
module tree_adder #(
	parameter fi  = 4,
	parameter width = 12,
	localparam width_TA = 2*width + $clog2(fi)
)(
	input signed [2*width-1:0] actwt [fi-1:0],
	output signed [width_TA-1:0] actwt_dot
);
	/* Create fi-to-1 tree adder
	This needs fi-1 adders [Eg: 4-to-1 tree adder needs 3 2-input adders]
	partial_s [0:fi-1] holds the fi aw values, [Eg 4 aw values] of the neuron in question
	partial_s needs fi-1 more values to hold adder outputs
	So total size of partial_s is 2*fi-1 [Eg: 7]
	pz[4] = pz[1]+pz[0], pz[5]=pz[3]+pz[2]
	Finally pz[6] = pz[4]+pz[5] */	
	logic signed [width_TA-1:0] partial_s [2*fi-2:0];
	genvar gv_i, gv_j;
	
	generate for (gv_i = 0; gv_i<fi; gv_i++) begin: bit_extend
		// The following line sign extends 'width bit' actwt to 'width_TA bit'
		assign partial_s[gv_i] = { {$clog2(fi){actwt[gv_i][2*width-1]}}, actwt[gv_i] };
	end
	endgenerate

	generate for (gv_i = 1; gv_i < $clog2(fi)+1; gv_i++) begin: adder_tree_outer //This does tree adder computation, i.e. partial_s[fi] to partial_s[2*fi-2]
		for (gv_j = 0; gv_j < (fi/(2**gv_i)); gv_j++) begin: adder_tree_inner
			if (gv_i<=2)
				adder #(
					.width(width_TA)
				) adder_1 (
					.a(partial_s[fi*2 - fi*2**(2-gv_i) + 2*gv_j]),
					.b(partial_s[fi*2 - fi*2**(2-gv_i) + 2*gv_j + 1]),
					.s(partial_s[2**($clog2(fi)+1) - 2**($clog2(fi)+1-gv_i) + gv_j])
				);
			else
				adder #(
					.width(width_TA)
				) adder_2 (
					.a(partial_s[fi*2 - fi/2**(gv_i-2) + 2*gv_j]),
					.b(partial_s[fi*2 - fi/2**(gv_i-2) + 2*gv_j + 1]),
					.s(partial_s[2**($clog2(fi)+1) - 2**($clog2(fi)+1-gv_i) + gv_j])
				);
		end	
	end
	endgenerate
	
	assign actwt_dot = partial_s[2*fi-2];	
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

//This module computes delp, i.e. z activations for the preceding layer
module BP_processor_set #(
	parameter fi  = 4,
	parameter z  = 8,
	parameter width = 12,
	parameter int_bits = 3,
	localparam frac_bits = width-int_bits-1
)(
	input signed [width-1:0] del_in [z/fi-1:0], //input deln values
	input signed [width-1:0] adot_in [z-1:0], //z weights can belong to z different p layer neurons, so we have z adot_in values
	input signed [width-1:0] wt [z-1:0],
	input signed [width-1:0] partial_del_out [z-1:0], //partial del values being constructed
	output signed [width-1:0] del_out [z-1:0] //delp values
);
	logic signed [width-1:0] delin_adot [z-1:0];
	logic signed [width-1:0] delin_adot_wt [z-1:0];

	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<z/fi; gv_i++) begin: each_output_neuron
		for (gv_j = 0; gv_j<fi; gv_j++) begin: within_1_output_neuron
			// adot always has range within 1, so multiplying by it needs no bit expansion
			multiplier #(
				.width(width),
				.int_bits(int_bits)
			) mul_delin_adot (
				.a(del_in[gv_i]),
				.b(adot_in[gv_i*fi+gv_j]),
				.p(delin_adot[gv_i*fi+gv_j])
			);
			// Then multiply by weight
			multiplier #(
				.width(width),
				.int_bits(int_bits)
			) mul_delin_adot_wt (
				.a(delin_adot[gv_i*fi+gv_j]),
				.b(wt[gv_i*fi+gv_j]),
				.p(delin_adot_wt[gv_i*fi+gv_j])
			);
			// Then add above to respective del value
			adder #(
				.width(width)
			) acc (
				.a(delin_adot_wt[gv_i*fi+gv_j]),
				.b(partial_del_out[gv_i*fi+gv_j]),
				.s(del_out[gv_i*fi+gv_j])
			);
		end
	end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

// This module computes updates to z weights and z/fi biases
module UP_processor_set #(
	parameter fi  = 4,
	parameter z  = 4,
	parameter width =12,
	parameter int_bits = 3,
	localparam frac_bits = width-int_bits-1
	//parameter eta = 0.05
)(
	// Note that updates are done for z weights in a junction and n neurons in succeeding layer
	input [$clog2(frac_bits+2)-1:0] etapos,
	input signed [width-1:0] act_in [z-1:0], //actp
	input signed [width-1:0] del_in [z/fi-1:0], //deln
	input signed [width-1:0] wt [z-1:0], //Existing weights whose values will be updated
	input signed [width-1:0] bias [z/fi-1:0], //Existing bias of layer n neurons whose values will be updated
	output signed [width-1:0] wt_UP [z-1:0], //Output weights after update
	output signed [width-1:0] bias_UP [z/fi-1:0] //Output biases after update
);

	//logic [width-1:0] Eta = -eta*2**frac_bits;
	logic signed [width-1:0] del_in_neg [z/fi-1:0]; //-del_in
	logic signed [width-1:0] delta_bias [z/fi-1:0];
	logic signed [width-1:0] delta_bias_temp [z/fi-1:0]; //Temporarily stores values of delta_bias
	logic signed [width-1:0] delta_wt [z-1:0];

	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i<z/fi; gv_i++) begin: all_update
		assign del_in_neg[gv_i] = (del_in[gv_i] == {1'b1,{(width-1){1'b0}}}) ? {1'b0,{(width-1){1'b1}}} : -del_in[gv_i]; //If del_in is neg max, then we need to explicitly specify that its negative is pos max
		assign delta_bias_temp[gv_i] = (etapos==0) ? 0 : //If etapos=0, operation hasn't started
										del_in_neg[gv_i]>>>(etapos-1); //Otherwise usual case: delta_bias_temp = -del_in*eta
		assign delta_bias[gv_i] = (etapos<=1) ? delta_bias_temp[gv_i] : //If etapos=0, delta_bias=delta_bias_temp=0. If etapos=1, delta_bias=delta_bias_temp
									delta_bias_temp[gv_i] + del_in_neg[gv_i][etapos-2]; //Otherwise round, i.e. add 1 if MSB of shifted out portion in del_in_neg = 1
		adder #(
			.width(width)
		) update_bias (
			.a(bias[gv_i]),
			.b(delta_bias[gv_i]),
			.s(bias_UP[gv_i])
		);

		for (gv_j = 0; gv_j<fi; gv_j++) begin: weight_update
			multiplier #(
				.width(width),
				.int_bits(int_bits)
			) mul_act_del (
				.a(delta_bias[gv_i]),
				.b(act_in[gv_i*fi+gv_j]),
				.p(delta_wt[gv_i*fi+gv_j])
			);
			adder #(
				.width(width)
			) update_wt (
				.a(wt[gv_i*fi+gv_j]),
				.b(delta_wt[gv_i*fi+gv_j]),
				.s(wt_UP[gv_i*fi+gv_j])
			);
		end
	end
	endgenerate
endmodule
