`timescale 1ns / 100ps

module tb_UP_processor_set #(
	parameter fi  = 2,
	parameter z  = 4,
	parameter width = 12, 
	parameter int_bits = 3, 
	localparam frac_bits = width-int_bits-1
)(
);

	logic [$clog2(frac_bits+2)-1:0] etapos;
	logic signed [width-1:0] act_in [z-1:0]; //actp
	logic signed [width-1:0] del_in [z/fi-1:0]; //input deln values
	logic signed [width-1:0] wt [z-1:0]; //Existing weights whose values will be updated
	logic signed [width-1:0] bias [z/fi-1:0]; //Existing bias of layer n neurons whose values will be updated
	logic signed [width-1:0] wt_UP [z-1:0]; //Output weights after update
	logic signed [width-1:0] bias_UP [z/fi-1:0]; //Output biases after update
	
	UP_processor_set #(
		.width(width),
		.z(z),
		.fi(fi),
		.int_bits(int_bits)
	) UPps (
		.etapos,
		.act_in,
		.del_in,
		.wt,
		.bias,
		.wt_UP,
		.bias_UP
	);
	
	initial begin
		integer i;
		etapos = 4'b0101; //actual eta=2^-4
		del_in[0] = 12'b010000000000; //4
		del_in[1] = 12'b111111111000; //-(2^-5)
		bias[0] = 12'b000001000000; //0.25
		bias[1] = 12'h800;
		// delta_bias = -0.25, 2^-9 rounded to 2^-8,  bias_UP = 0, 12'h801
		for (i=0; i<z; i++) begin
			act_in[i] = i<<(frac_bits-1); //0,0.5,1,1.5
			wt[i] = -i<<frac_bits; //0,-1,-2,-3
			// delta_wt = 0, 12'hfe0,12'h001,002,   wt_UP = 0,ee0,e01,d02
		end
		#10;
		etapos=0;
		for (i=0; i<z/fi; i++) begin
			bias[i] = bias_UP[i];
		end
		//bias_UP = 0,801,  wt_UP = 0,f00,e00,d00
		#10 etapos = 4'b0001;
		del_in[0] = 12'h800;
		del_in[1] = 0;
		for (i=0; i<z; i++) begin
			act_in[i] = 12'b000100000000; //1
		end
		//bias_UP = 7ff,801,  wt_UP = 7ff,6ff,e00,d00
		#5 $stop;
	end

endmodule
