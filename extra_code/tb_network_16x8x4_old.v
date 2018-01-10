// Original testbench, difficult to make sense of now, but gives reasonable 16x8x4 training results stored in results_tb_network_old
`timescale 1ns/100ps

module tb_network #(
	// DNN parameters to be passed
	parameter width = 16,
	parameter int_bits = 5,
	parameter frac_bits = 10,
	parameter L = 3,
	parameter [31:0]fo[0:L-2] = '{2, 2},
	parameter [31:0]fi[0:L-2]  = '{4, 4},
	parameter [31:0]z[0:L-2]  = '{8, 4},
	parameter [31:0]n[0:L-1] = '{16, 8, 4},
	parameter eta = 0.5,
	parameter lamda = 0.995,
	// Testbench parameters:
	parameter training_cases = 8,
	parameter test_cases = 8,
	parameter cpc =  n[0] * fo[0] / z[0] + 2
); 
	
	// Input Pre-Processing
	wire [n[L-1]*training_cases-1:0] y_package; //Complete 1b ideal output for all training cases, i.e. No. of output neurons x 1 x No. of training cases
	wire [n[0]*training_cases-1:0] a_package; //Complete 1b act input for all training cases, i.e. No. of input neurons x 1 x No. of training cases
	wire [n[L-1]-1:0] y; //Complete 1b ideal output for 1 training case, i.e. No. of output neurons x 1 x 1
	wire [n[0]-1:0] a; //Complete 1b act input for 1 training case, i.e. No. of input neurons x 1 x 1
	reg [$clog2(training_cases)-1:0] sel_tc = 0; //MUX select
	reg [$clog2(cpc-2)-1:0] sel_network = 0; //MUX select

	// Performance evaluation signals
	reg [n[L-1]-1:0] training_y [training_cases-1:0];
	reg [n[0]-1:0] training_a [training_cases-1:0];
	reg [2:0] o = 7;
	integer d;
	reg[15:0] error = 0;
	integer file;
	integer i;

	// DNN DUT I/O
	reg clk = 1;
	reg reset=1;
	wire [z[0]/fo[0]-1:0] act_in; //No. of input activations coming into input layer per clock
	wire [z[L-2]/fi[L-2]-1:0] y_in; //No. of ideal outputs coming into input layer per clock
	wire [width*n[L-1]-1:0] output_package; //Computed outputs from all output layer neurons
	wire [z[L-2]/fi[L-2]-1:0] y_out; //ideal output (y_in after going through all layers)
	wire [z[L-2]/fi[L-2]-1:0] a_out; //Actual output [Eg: 4/4=1 output neuron processed per clock]

	DNN #(
		.width(width),
		.int_bits(int_bits),
		.frac_bits(frac_bits),
		.L(L), 
		.fo(fo), 
		.fi(fi), 
		.z(z), 
		.n(n), 
		.eta(eta), 
		.lamda(lamda)
	) DNN_16x8x4 (
		.act_in(act_in),
		.y_in(y_in),
		.clk(clk),
		.reset(reset),
		.output_package(output_package),
		.y_out(y_out),
		.a_out(a_out)
	);

	mux #( //Choose 1 training case out of all for ideal outputs
		.width(n[L-1]), 
		.N(training_cases)
	) mux_idealoutput_trainingcases (
		y_package, sel_tc, y);

	mux #( //Choose 1 training case out of all for act inputs
		.width(n[0]), 
		.N(training_cases)
	) mux_actinput_trainingcases (
		a_package, sel_tc, a);

	mux #( //Choose the required no. of ideal outputs for feeding to DNN
		.width(z[L-2]/fi[L-2]), 
		.N(n[L-1]*fi[L-2]/z[L-2]) //This is basically cpc-2 of the last junction
	) mux_idealoutput_feednetwork (
		y, sel_network, y_in);

	mux #( //Choose the required no. of act inputs for feeding to DNN
		.width(z[0]/fo[0]), 
		.N(n[0]*fo[0]/z[0]) //This is basically cpc-2 of the 1st junction
	) mux_actinput_feednetwork (
		a, sel_network, act_in);

	// Clock period = 10ns	
	always #5 clk = ~clk; 
	
	initial begin
		file = $fopen("results.dat");
		if (o>7.1)
			d = 1;
		else
			d = 0;
		{training_a[0], training_y[0]} = {16'h000f, 4'b0001};
		{training_a[1], training_y[1]} = {16'h00f0, 4'b0010}; 
		{training_a[2], training_y[2]} = {16'h0f00, 4'b0100}; 
		{training_a[3], training_y[3]} = {16'hf000, 4'b1000}; 
		{training_a[4], training_y[4]} = {16'hfff0, 4'b1110}; 
		{training_a[5], training_y[5]} = {16'hff0f, 4'b1101}; 
		{training_a[6], training_y[6]} = {16'hf0ff, 4'b1011}; 
		{training_a[7], training_y[7]} = {16'h0fff, 4'b0111};
		#55;
		reset = 0;
		#30;
		while (1) begin
			sel_tc = $random()%training_cases;
			error = 0;
			for (i = 0; i < cpc; i = i + 1) begin
				if (i < n[0] * fo[0] / z[0])  begin
					error = DNN_16x8x4.dL[15]? error - DNN_16x8x4.dL : error + DNN_16x8x4.dL;
					sel_network = i-2;
				#10;
				end
			end
			$display("%d", error);
			$fdisplay(file, "%d", error);
		end
	end

	genvar gv_i;
	generate for (gv_i = 0; gv_i<training_cases; gv_i = gv_i + 1)
	begin : package_input
		assign y_package[n[L-1]*(gv_i+1)-1:n[L-1]*gv_i] = training_y[gv_i];
		assign a_package[n[0]*(gv_i+1)-1:n[0]*gv_i] = training_a[gv_i];
	end
	endgenerate
endmodule
