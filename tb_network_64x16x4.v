`timescale 1ns/100ps

module tb_network #(
	// DNN parameters to be passed
	parameter width = 16,
	parameter int_bits = 5,
	parameter frac_bits = 10,
	parameter L = 3,
	parameter [31:0]fo[0:L-2] = '{2, 2},
	parameter [31:0]fi[0:L-2]  = '{8, 8},
	parameter [31:0]z[0:L-2]  = '{32, 8},
	parameter [31:0]n[0:L-1] = '{64, 16, 4},
	parameter eta = 0.9,
	parameter lamda = 0.5,
	// Testbench parameters:
	parameter training_cases = 32,
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

	// An f anywhere out of 16 bits in a means corresponding y will be 1
	// Eg: a = 64'h000000000000f000, a = 64'h000000000000ff0f, a = 64'h00000000000000ff, etc all lead to y = 4'b0001
	
/* genvar i, j;
	generate
		for (i=0; i<training_cases; i=i+1) begin : training_cases
			assign a_package[n[0]*(i+1)-1:n[0]*i] = 64'h000f00f00f00f000fff0ff0ff0ff0fff;
			assign y_package =  32'b00010010010010001110110110110111; */

	assign a_package[319:256] = 64'hff0f000000000000; assign y_package[19:16] = 4'b1000;
	assign a_package[1279:1216] = 64'h00f0000000000000; assign y_package[79:76] = 4'b1000;
	assign a_package[1535:1472] = 64'hf000000000000000; assign y_package[95:92] = 4'b1000;
	assign a_package[1855:1792] = 64'hffff000000000000; assign y_package[115:112] = 4'b1000;
	assign a_package[639:576] = 64'h0f0f000000000000; assign y_package[39:36] = 4'b1000;
	assign a_package[1151:1088] = 64'hf0f0000000000000; assign y_package[71:68] = 4'b1000;
	assign a_package[1023:960] = 64'hfff0000000000000; assign y_package[63:60] = 4'b1000;
	assign a_package[1471:1408] = 64'h0ff0000000000000; assign y_package[91:88] = 4'b1000;
	
	assign a_package[1599:1536] = 64'h0000ff0f00000000; assign y_package[99:96] = 4'b0100;
	assign a_package[63:0] = 64'h000000f000000000; assign y_package[3:0] = 4'b0100;
	assign a_package[895:832] = 64'h0000f00000000000; assign y_package[55:52] = 4'b0100;
	assign a_package[1727:1664] = 64'h0000ffff00000000; assign y_package[107:104] = 4'b0100;
	assign a_package[1087:1024] = 64'h00000f0f00000000; assign y_package[67:64] = 4'b0100;
	assign a_package[1663:1600] = 64'h0000f0f000000000; assign y_package[103:100] = 4'b0100;
	assign a_package[703:640] = 64'h0000fff000000000; assign y_package[43:40] = 4'b0100;
	assign a_package[383:320] = 64'h00000ff000000000; assign y_package[23:20] = 4'b0100;
	
	assign a_package[1407:1344] = 64'h00000000ff0f0000; assign y_package[87:84] = 4'b0010;
	assign a_package[447:384] = 64'h0000000000f00000; assign y_package[27:24] = 4'b0010;
	assign a_package[1919:1856] = 64'h00000000f0000000; assign y_package[119:116] = 4'b0010;
	assign a_package[2047:1984] = 64'h00000000ffff0000; assign y_package[127:124] = 4'b0010;
	assign a_package[767:704] = 64'h000000000f0f0000; assign y_package[47:44] = 4'b0010;
	assign a_package[831:768] = 64'h00000000f0f00000; assign y_package[51:48] = 4'b0010;
	assign a_package[1215:1152] = 64'h00000000fff00000; assign y_package[75:72] = 4'b0010;
	assign a_package[191:128] = 64'h000000000ff00000; assign y_package[11:8] = 4'b0010;

	assign a_package[1343:1280] = 64'h000000000000ff0f; assign y_package[83:80] = 4'b0001;
	assign a_package[511:448] = 64'h00000000000000f0; assign y_package[31:28] = 4'b0001;
	assign a_package[1983:1920] = 64'h000000000000f000; assign y_package[123:120] = 4'b0001;
	assign a_package[127:64] = 64'h000000000000ffff; assign y_package[7:4] = 4'b0001;
	assign a_package[255:192] = 64'h0000000000000f0f; assign y_package[15:12] = 4'b0001;
	assign a_package[1791:1728] = 64'h000000000000f0f0; assign y_package[111:108] = 4'b0001;
	assign a_package[959:896] = 64'h000000000000fff0; assign y_package[59:56] = 4'b0001;
	assign a_package[575:512] = 64'h0000000000000ff0; assign y_package[35:32] = 4'b0001;

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
		if (num_train==100) $stop; //2nd stop condition
	end

	always @(posedge clk) begin
		if (cycle_index > 1 && a_out != y_out) tc_error = 1; //Since output is obtained starting from cycle 2 up till cycle (cpc-1)	
	end
endmodule
