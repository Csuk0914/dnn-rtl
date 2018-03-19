`timescale 1ns / 100ps

module tb_FF_processor_set #(
	parameter fi  = 32,
	parameter z  = 512,
	parameter width = 12, 
	parameter int_bits = 3, 
	localparam frac_bits = width-int_bits-1,
	localparam width_TA = 2*width + $clog2(fi),
	parameter actfn = 0 //0 for sigmoid, 1 for ReLU
)(
);
	logic clk = 0;
	logic signed [width-1:0] act_in [z-1:0]; //Process z input activations together, each width bits
	logic signed [width-1:0] wt [z-1:0]; //Process z input weights together, each width bits
	logic signed [width-1:0] bias [z/fi-1:0]; // z/fi is the no. of neurons processed in 1 cycle, so that many bias values
	logic signed [width-1:0] act_out [z/fi-1:0]; //output actn values
	logic signed [width-1:0] adot_out [z/fi-1:0]; //output sigmoid prime values (to be used for BP)

	FF_processor_set #(
		.width(width),
		.z(z),
		.fi(fi),
		.int_bits(int_bits),
		.actfn(actfn)
	) FFps (
		.clk,
		.act_in,
		.wt,
		.bias,
		.act_out,
		.adot_out
	);
	
	always #5 clk=~clk;
	
	//Bigger cases
	initial begin
		integer i;
		for (i=0; i<z; i++) begin
			act_in[i] = '0;
			wt[i] = '1;
		end
		for (i=0; i<z/fi; i++)
			bias[i] = '0;
		#20 $stop;
	end
	
	
	// For z=4, fi=4
	/*initial begin
		integer i;
		for (i=0; i<z; i++) begin
			act_in[i] = i<<8; //i in 1,3,8
			wt[i] = (-i)<<8;
		end
		for (i=0; i<z/fi; i++) begin
			bias[i] = 12'h7ff; //8-2^-8
		end
		//expected: sigmoid(-6) = sigmoidprime(-6) = 2.46e-3, relu(-6) = reluprime(-6) = 0
		#20;
		for (i=0; i<z; i++) begin
			act_in[i] = 12'b000010000000; //0.5
			wt[i] = 12'b111110000000; //-0.5
		end
		for (i=0; i<z/fi; i++) begin
			bias[i] = 12'b000110000000; //1.5
		end
		//expected: sigmoid(0.5) = 0.622, sigmoidprime(0.5) = 0.235, relu(0.5) = 0.5, reluprime(0.5) = 1
		#20;
		act_in[0] = 12'b000001000000; //0.25
		act_in[1] = 12'b000001100000; //0.375
		act_in[2] = 12'b000010000000; //0.5
		act_in[3] = 12'b000010100000; //0.625
		wt[0] = 12'b101101010000; //-4.6875
		wt[1] = '0;
		wt[2] = 12'b000000000101; //0.0195
		wt[3] = 12'b001100000000; //3
		//actwtdot = 0.712875
		bias[0] = 12'b111011000000; //-1.25
		//actwtdot+bias = -0.537
		//expected: sigmoid = 0.3689, sp = 0.2328, relu = 0, relup = 0
		#20 $stop;
	end*/

	// For z=4, fi=1
	/*initial begin
		act_in[0] = 12'b000001000000; //0.25
		act_in[1] = 12'b000001100000; //0.375
		act_in[2] = 12'b011110000000; //7.5
		act_in[3] = 12'b001100000001; //3+2^-8
		wt[0] = 12'b101101010000; //-4.6875, pdt=-1.17
		wt[1] = '1; //-2^-8, pdt=-1.46e-3
		wt[2] = act_in[2]; //7.5, pdt=56.25
		wt[3] = 12'b110100000000; //-3, pdt=-9-(3*2e-8)
		bias[0] = 12'b000100000000; //1, s=0.457, sp=0.248, r=rp=0
		bias[1] = '0; //s=0.5, sp=0.25, r=rp=0
		bias[2] = '0; //s=1, sp=0, r=1, rp=0
		bias[3] = 12'b011100000000; //7, s=0.117, sp=0.103, r=rp=0
		#10 act_in[0] = '0;
		#1 wt[0] = '0; //s=0.73, sp=0.196, r=1, rp=0
		#10 $stop;
	end*/

endmodule
