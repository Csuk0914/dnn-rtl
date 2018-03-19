`timescale 1ns / 100ps

module tb_BP_processor_set #(
	parameter fi  = 2,
	parameter z  = 4,
	parameter width = 12, 
	parameter int_bits = 3, 
	localparam frac_bits = width-int_bits-1
)(
);

	logic signed [width-1:0] del_in [z/fi-1:0]; //input deln values
	logic signed [width-1:0] adot_in [z-1:0]; //z weights can belong to z different p layer neurons, so we have z adot_out values
	logic signed [width-1:0] wt [z-1:0];
	logic signed [width-1:0] partial_del_out [z-1:0]; //partial del values being constructed
	logic signed [width-1:0] del_out [z-1:0]; //delp values
	
	BP_processor_set #(
		.width(width),
		.z(z),
		.fi(fi),
		.int_bits(int_bits)
	) BPps (
		.del_in,
		.adot_in,
		.wt,
		.partial_del_out,
		.del_out
	);
	
	initial begin
		integer i;
		del_in[0] = 12'b001010000000; //2.5
		del_in[1] = 12'b111100000000; //-1
		for (i=0; i<z; i++) begin
			adot_in[i] = i<<(frac_bits-2); //0,0.25,0.5,0.75
			wt[i] = -i<<frac_bits; //0,-1,-2,-3
		end
		// awd[0] = 0, awd[1] = -0.625, awd[2] = 1, awd[3] = 2.25
		partial_del_out[0] = 12'h0ff; //out=0ff
		partial_del_out[1] = 12'b000010100000; //out=0
		partial_del_out[2] = 12'h7ff; //out=7ff
		partial_del_out[3] = 12'b101001000000; //-5.75, out=12'hc80 = -3.5
		#10;
		for (i=0; i<z; i++) begin
			partial_del_out[i] = del_out[i];
		end
		// out[0,1,2,3] = 12'h0ff,12'hf60,12'h7ff,12'hec0
		#5 $stop;
	end

endmodule
