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
	//parameter test_cases = 8,
	parameter clock_period = 10,
	parameter cpc =  n[0] * fo[0] / z[0] + 2
);

	// DNN DUT I/O
	reg clk = 1;
	reg reset = 1;
	wire [z[0]/fo[0]-1:0] a_in; //No. of input activations coming into input layer per clock
	wire [z[L-2]/fi[L-2]-1:0] y_in; //No. of ideal outputs coming into input layer per clock
	wire [z[L-2]/fi[L-2]-1:0] y_out; //ideal output (y_in after going through all layers)
	wire [z[L-2]/fi[L-2]-1:0] a_out; //Actual output [Eg: 4/4=1 output neuron processed per clock]

	// Instantiate DNN
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
	) DNN (
		.a_in(a_in),
		.y_in(y_in),
		.clk(clk),
		.reset(reset),
		.y_out(y_out),
		.a_out(a_out)
	);

	// Training cases Pre-Processing
	wire [n[L-1]*training_cases-1:0] y_package; //Complete 1b ideal output for all training cases, i.e. No. of output neurons x 1 x No. of training cases
	wire [n[0]*training_cases-1:0] a_package; //Complete 1b act input for all training cases, i.e. No. of input neurons x 1 x No. of training cases
	wire [n[L-1]-1:0] y; //Complete 1b ideal output for 1 training case, i.e. No. of output neurons x 1 x 1
	wire [n[0]-1:0] a; //Complete 1b act input for 1 training case, i.e. No. of input neurons x 1 x 1
	reg [$clog2(training_cases)-1:0] sel_tc = 0; //MUX select
	wire [$clog2(cpc-2)-1:0] sel_network; //MUX select

	assign a_package = 128'h000f00f00f00f000fff0ff0ff0ff0fff;
	assign y_package =  32'b00010010010010001110110110110111;

	// Instantiate MUXes for feeding data
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
		a, sel_network, a_in);


	// Performance evaluation
	wire cycle_clk;
	wire [$clog2(cpc)-1:0] cycle_index;
	integer file;
	integer num_train = 0;
	integer total_error = 0;
	reg tc_error = 0; //Flags if a particular training case gives error

	cycle_block_counter #(
		.cpc(cpc)
	) cycle_counter (
		.clk(clk),
		.reset(reset),
		.cycle_clk(cycle_clk),
		.count(cycle_index)
	);
	assign sel_network = cpc-3 - cycle_index[$clog2(cpc-2)-1:0];
	
	initial begin
		//file = $fopen("results.dat");
		#91 reset = 0;
		#10000000 $stop; //1st stop condition
	end

	// Set Clock	
	always #(clock_period/2) clk = ~clk;

	always @(posedge cycle_clk) begin
		 //Evaluate previous training case
		$display("Training case number = %0d", num_train);
		$display("Training Case Error = %0d", tc_error);
		$display("Total Error = %0d", total_error);
		//$fdisplay(file, "%0d", total_error);
		if (tc_error != 0) total_error = total_error+1;
		//Start new training case
		num_train <= num_train + 1;
		sel_tc <= sel_tc + 1;
		tc_error <= 0;
		if (num_train==1000) $stop; //2nd stop condition
	end

	always @(posedge clk) begin
		if (cycle_index > 1 && a_out != y_out) tc_error = 1; //Since output is obtained starting from cycle 2 up till cycle (cpc-1)	
	end
endmodule
