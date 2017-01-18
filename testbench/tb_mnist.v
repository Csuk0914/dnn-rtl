`timescale 1ns/100ps

module MNIST_tb #(
	// DNN parameters to be passed
	parameter width = 32,
	parameter width_in = 8,
	parameter int_bits = 10,
	parameter frac_bits = 21,
	parameter L = 3,
	parameter [31:0]fo[0:L-2] = '{8, 8},
	parameter [31:0]fi[0:L-2]  = '{128, 32},
	parameter [31:0]z[0:L-2]  = '{512, 32},
	parameter [31:0]n[0:L-1] = '{1024, 64, 16},
	parameter Eta = 1,
	parameter lamda = 0.25,
	parameter cost_type = 1, //0 for quadcost, 1 for xentcost
	// Testbench parameters:
	parameter training_cases = 50000,
	//parameter test_cases = 8,
	parameter clock_period = 10,
	parameter cpc =  n[0] * fo[0] / z[0] + 2
);
	////////////////////////////////////////////////////////////////////////////////////
	// define DNN DUT I/O
	// DNN input: clk, reset, eta, a_in, y_in
	// DNN output: y_out, a_out
	////////////////////////////////////////////////////////////////////////////////////
	reg clk = 1;
	reg reset = 1;
	reg [width-1:0] eta;
	wire [width_in*z[0]/fo[0]-1:0] a_in; //No. of input activations coming into input layer per clock, each having width_in bits
	wire [z[L-2]/fi[L-2]-1:0] y_in; //No. of ideal outputs coming into input layer per clock
	wire [z[L-2]/fi[L-2]-1:0] y_out; //ideal output (y_in after going through all layers)
	wire [z[L-2]/fi[L-2]-1:0] a_out; //Actual output [Eg: 4/4=1 output neuron processed per clock]

	////////////////////////////////////////////////////////////////////////////////////
	// Instantiate DNN
	////////////////////////////////////////////////////////////////////////////////////
	DNN #(
		.width(width), 
		.width_in(width_in),
		.int_bits(int_bits),
		.frac_bits(frac_bits),
		.L(L), 
		.fo(fo), 
		.fi(fi), 
		.z(z), 
		.n(n), 
		//.eta(eta), 
		.lamda(lamda),
		.cost_type(cost_type)
	) DNN (
		.a_in(a_in),
		.y_in(y_in), 
		.eta_in(eta), 
		.clk(clk),
		.reset(reset),
		.y_out(y_out),
		.a_out(a_out)
	);



	////////////////////////////////////////////////////////////////////////////////////
	// initial weight memory Pre-Processing
	////////////////////////////////////////////////////////////////////////////////////
	reg [width-1:0] memL1[1999:0], memL2[1999:0];
	initial begin
		$readmemb("./gaussian_list/s136_frc21_int10.dat", memL1);
		$readmemb("./gaussian_list/s40_frc21_int10.dat", memL2);
	end


	////////////////////////////////////////////////////////////////////////////////////
	// Training cases Pre-Processing
	////////////////////////////////////////////////////////////////////////////////////
	wire [n[L-1]-1:0] y; //Complete 1b ideal output for 1 training case, i.e. No. of output neurons x 1 x 1
	wire [width_in*n[0]-1:0] a; //Complete 8b act input for 1 training case, i.e. No. of input neurons x 8 x 1
	reg [$clog2(training_cases)-1:0] sel_tc = 10000; //MUX select
	wire [$clog2(cpc-2)-1:0] sel_network; //MUX select to choose which input/output pair to feed to network within a block cycle

	mux #( //Choose the required no. of ideal outputs for feeding to DNN
		.width(z[L-2]/fi[L-2]), 
		.N(n[L-1]*fi[L-2]/z[L-2]) //This is basically cpc-2 of the last junction
	) mux_idealoutput_feednetwork (
		y, sel_network, y_in);

	mux #( //Choose the required no. of act inputs for feeding to DNN
		.width(width_in*z[0]/fo[0]), 
		.N(n[0]*fo[0]/z[0]) //This is basically cpc-2 of the 1st junction
	) mux_actinput_feednetwork (
		a, sel_network, a_in);

	
	
	////////////////////////////////////////////////////////////////////////////////////
	// Performance evaluation
	////////////////////////////////////////////////////////////////////////////////////
	wire cycle_clk;
	wire [$clog2(cpc)-1:0] cycle_index;
	integer num_train = 0; //Number of the current training case
	integer epoch = 0;
	reg tc_error = 0; //Flags if a particular training case gives error (in any of its neurons)
	integer total_error = 0; //Total number of tc_errors accumulated over training cases
	real error_rate = 0;
	/* Let e = sum over all output neurons |y_out-actL|, where actL is the unthresholded output of the last layer
	* Then e is basically giving the L1 norm over all output neurons of a particular training case
	* error_rate computes average of e over the last 100 training cases, i.e. moving average */
	

	cycle_block_counter #(
		.cpc(cpc)
	) cycle_counter (
		.clk(clk),
		.reset(reset),
		.cycle_clk(cycle_clk),
		.count(cycle_index)
	);
	assign sel_network = cycle_index[$clog2(cpc-2)-1:0]-2;
	/* cycle_index goes from 0-17, so its 4 LSB go from 0-15 then 0-1
	* But nothing happens in the last 2 cycles since pipeline delay is 2
	* So take values of cycle_index from 0-15 and subtract 2 to make its 4 LSB go from 14-15, then 0-13
	* Note that the jumbled order isn't important as long as all inputs from 0-15 are fed */
	
	initial begin
		//file = $fopen("results.dat");
		#91 reset = 0;
		//#10000000 $stop; //1st stop condition
	end

	////////////////////////////////////////////////////////////////////////////////////
	// Set Clock	
	////////////////////////////////////////////////////////////////////////////////////
	always #(clock_period/2) clk = ~clk;


	////////////////////////////////////////////////////////////////////////////////////
	// performance analysis
	// comment the $display if too much information shows on screen 
	////////////////////////////////////////////////////////////////////////////////////
	always @(posedge cycle_clk) begin
		//Evaluate previous training case
		$display("Training case number = %0d", num_train);
		$display("Training Case Error = %0d", tc_error);
		$display("Total Error = %0d", total_error);
		$display("Error rate = %2.5f", error_rate);
		//$fdisplay(file, "%0d", total_error);
		if (tc_error != 0) total_error = total_error+1;
		
		//Start new training case
		num_train <= num_train + 1;
		sel_tc <= (sel_tc == training_cases-1)? 0 : sel_tc + 1;
		if (sel_tc == training_cases-1) begin
			$display("finish training epoch %d", epoch);
			epoch = epoch + 1;
		end
		tc_error <= 0;
		error_rate <= 0;
		
		if (num_train==100000) $stop;
	end

	always @(posedge clk) begin
		if (cycle_index > 1 && a_out != y_out) tc_error = 1; //Since output is obtained starting from cycle 2 up till cycle (cpc-1)
		if( cycle_index > 1)
			// Need to divide actL by 2**frac_bits to get result between 0 and 1
			if(y_out) error_rate = error_rate + y_out - DNN.actL/(2**frac_bits); //y_out = 1, so |y_out-actL| = 1-actL
			else error_rate = error_rate + DNN.actL/(2**frac_bits); //y_out = 0, so |y_out-actL| = actL
	end



	////////////////////////////////////////////////////////////////////////////////////
	// data import block [todo] Modify this portion to have 512 inputs
	// train_input.dat contains 50000 MNIST pattern. Each pattern contain 28*28 pixels which is 8 bit gray scale.
	// 					1 line is one pattern with 784 8bit hex.
	// train_result.dat is the data set for 50000 correct result of training data. There are 10 bits one-hot represent 10 digital number.
	//					1 line is one pattern with 10 one-hot binary.
	//data import need to be fixed to the DNN network which is 1024 input and 16 output.
	//For the trainning data input, the first 784 values are from one trainning pattern and the rest input bits are set to 0.
	//For the result input, the first 10 values are from the training result with the same index to training pattern and the rest bits are set to 0.
	//training_case is the number of pattern that will load to design as a epoch of training data. This testbench only have one epoch now.
	////////////////////////////////////////////////////////////////////////////////////
	reg i, j, k;
	reg y_mem[training_cases-1:0][9:0];
	reg [width_in-1:0] a_mem[training_cases-1:0][783:0];
	wire [n[0]*width_in-1:0] a_array;
	wire [n[L-1]-1:0] y_array;

	genvar gv_i;	
	generate for (gv_i = 0; gv_i<n[0]; gv_i = gv_i + 1)
	begin: pr
		assign a[width_in*(gv_i+1)-1:width_in*gv_i] = (gv_i<784)? a_mem[sel_tc][gv_i]:0;
	end
	endgenerate

	generate for (gv_i = 0; gv_i<n[L-1]; gv_i = gv_i + 1)
	begin: pp
		assign y[gv_i] = (gv_i<10)? y_mem[sel_tc][gv_i]:0;
	end
	endgenerate

	initial begin
		eta = ~(Eta * (2 ** frac_bits)) + 1; //convert the Eta to fix point
		$readmemb("train_result.dat", y_mem);
		$readmemh("train_input.dat", a_mem);
	end
	////////////////////////////////////////////////////////////////////////////////////
	//actual code ends here
	////////////////////////////////////////////////////////////////////////////////////
	
	
	////////////////////////////////////////////////////////////////////////////////////
	//this whole block is used for debug. Comment it in normal simulation
	////////////////////////////////////////////////////////////////////////////////////
	integer p, q, correct, recent = 0;
	integer crt[100:0], crt_pt=0;
	real net_a_out[15:0], net_y_out[15:0], a_minus_y[15:0], delta[15:0], spL[15:0], train_n=0;
	real zL[15:0];
	real EMS;
	real wb1[32:0],U_wb1[32:0], a1[31:0], a_index[31:0];
	integer file1, file2;

	initial begin
		file1 = $fopen("EMS.dat");
		file2 = $fopen("log.dat");
		for(q = 0;q<101; q = q + 1)
			crt[q]=0;

	end

	wire [8:0]a_index_w[31:0];
	genvar gv_p;
	generate for(gv_p=0;gv_p<32;gv_p=gv_p+1) begin
			//assign a_index_w[gv_p]=DNN.hidden_layer_block_1.hidden_layer_state_machine.inter.maid[gv_p].DRP.memory_index;
		end
	endgenerate

	always @(negedge clk) begin
	if (cycle_index==1) begin
		for (q=0;q<32;q=q+1) begin
			a_index[q]=a_index_w[q];
		end
	end

	if (cycle_index==2) begin
		for (q=0;q<32;q=q+1) begin
			a1[q] =DNN.hidden_layer_block_1.UP_processor.a[q]/2.0**frac_bits
									-DNN.hidden_layer_block_1.UP_processor.a[q][width-1]*2.0**(1+int_bits);
			wb1[q] =DNN.hidden_layer_block_1.UP_processor.w[q]/2.0**frac_bits
									-DNN.hidden_layer_block_1.UP_processor.w[q][width-1]*2.0**(1+int_bits);
			U_wb1[q] =DNN.hidden_layer_block_1.UP_processor.w_UP[q]/2.0**frac_bits
									-DNN.hidden_layer_block_1.UP_processor.w_UP[q][width-1]*2.0**(1+int_bits);
		end
		wb1[32] =DNN.hidden_layer_block_1.UP_processor.b[0]/2.0**frac_bits
									-DNN.hidden_layer_block_1.UP_processor.b[0][width-1]*2.0**(1+int_bits);
		U_wb1[32] =DNN.hidden_layer_block_1.UP_processor.b_UP[0]/2.0**frac_bits
									-DNN.hidden_layer_block_1.UP_processor.b_UP[0][width-1]*2.0**(1+int_bits);
		end
	if (cycle_index>1) begin
		net_a_out[cycle_index-2] = DNN.actL/2.0**frac_bits;
		net_y_out[cycle_index-2] = DNN.y_out;
		// a_minus_y[cycle_index-2] = DNN.output_layer_block.a_minus_y/2.0**frac_bits
		// 							-DNN.output_layer_block.a_minus_y[width-1]*2.0**(1+int_bits);
		// spL[cycle_index-2] = DNN.output_layer_block.spL/2.0**frac_bits
		// 							-DNN.output_layer_block.spL[width-1]*2.0**(1+int_bits);
		delta[cycle_index-2] = DNN.output_layer_block.delta/2.0**frac_bits
									-DNN.output_layer_block.delta[width-1]*2.0**(1+int_bits);
	end
	if (cycle_index>0 && cycle_index<17) begin
		zL[cycle_index-1] = DNN.hidden_layer_block_1.FF_processor.sigmoid_function_set[0].s_function.s/2.0**frac_bits
							-DNN.hidden_layer_block_1.FF_processor.sigmoid_function_set[0].s_function.s[width-1]*2.0**(1+int_bits);
	end

	end
	
	always @(posedge cycle_clk)begin
		correct = 1;
		for (q=0;q<16;q=q+1) if((net_a_out[q]>0.5 && net_y_out[q]<0.5)||(net_a_out[q]<0.5 && net_y_out[q]>0.5)) correct=0; 
		crt[crt_pt] = correct;
		if (correct)
			recent = recent + 1;
		crt_pt = (crt_pt ==100)? 0:crt_pt+1;
		if (crt[crt_pt])
			recent = recent - 1;
		train_n = train_n + 1;
		EMS = 0;
		for (q=0;q<16;q=q+1) EMS = delta[q]*delta[q] + EMS;
		EMS = EMS * 100;
		$display ("-----------------------------train: %d", train_n);
		$write ("actual output:");
		for(q=0;q<16;q=q+1) $write ("\t %1.4f", net_a_out[q]); $write ("\n");
		$write ("ideal output: ");
		for(q=0;q<16;q=q+1) $write ("\t %1.4f", net_y_out[q]); $write ("\n");
		// $write ("a-y:          ");
		// for(q=0;q<16;q=q+1) $write ("\t %1.4f", a_minus_y[q]); $write ("\n");
		// $write ("spL:          ");
		// for(q=0;q<16;q=q+1) $write ("\t %1.4f", spL[q]); $write ("\n");
		$write ("delta:        ");
		for(q=0;q<16;q=q+1) $write ("\t %1.4f", delta[q]); $write ("\n");
		$write ("z:            ");
		for(q=0;q<16;q=q+1) $write ("\t %1.4f", zL[q]); $write ("\n");
		for(p=0;p<2;p=p+1) begin
		// $write ("a_index%1d:     ", p);
		// for(q=0;q<8;q=q+1) $write ("\t %3d", a_index[q+8*p]); $write ("\n");
		$write ("a%1d:           ", p);
		for(q=0;q<8;q=q+1) $write ("\t %1.3f", a1[q+8*p]); $write ("\n");
		// $write ("w%1d:           ", p);
		// for(q=0;q<8;q=q+1) $write ("\t %1.3f", wb1[q+8*p]); $write ("\n");
		// $write ("w_UP%1d:      ", p);
		// for(q=0;q<8;q=q+1) $write ("\t %1.3f", U_wb1[q+8*p]); $write ("\n");
		end
		$display("correct = %5d, recent_100 = %3d, EMS = %5f", correct, recent, EMS); 

		$fdisplay (file2,"-----------------------------train: %d", train_n);
		$fwrite (file2, "actual output:");
		for(q=0;q<16;q=q+1) $fwrite (file2, "\t %1.4f", net_a_out[q]); $fwrite (file2, "\n");
		$fwrite (file2, "ideal output: ");
		for(q=0;q<16;q=q+1) $fwrite (file2, "\t %1.4f", net_y_out[q]); $fwrite (file2, "\n");
		// $fwrite (file2, "a-y:          ");
		// for(q=0;q<16;q=q+1) $fwrite (file2, "\t %1.4f", a_minus_y[q]); $fwrite (file2, "\n");
		// $fwrite (file2, "spL:          ");
		// for(q=0;q<16;q=q+1) $fwrite (file2, "\t %1.4f", spL[q]); $fwrite (file2, "\n");
		$fwrite (file2, "delta:        ");
		for(q=0;q<16;q=q+1) $fwrite (file2, "\t %1.4f", delta[q]); $fwrite (file2, "\n");
		$fwrite (file2, "z:            ");
		for(q=0;q<16;q=q+1) $fwrite (file2, "\t %1.4f", zL[q]); $fwrite (file2, "\n");
		for(p=0;p<4;p=p+1) begin
		$fwrite (file2, "a_index%1d:     ", p);
		for(q=0;q<8;q=q+1) $fwrite (file2, "\t %3d", a_index[q+8*p]); $fwrite (file2, "\n");
		$fwrite (file2, "a%1d:           ", p);
		for(q=0;q<8;q=q+1) $fwrite (file2, "\t %1.3f", a1[q+8*p]); $fwrite (file2, "\n");
		$fwrite (file2, "w%1d:           ", p);
		for(q=0;q<8;q=q+1) $fwrite (file2, "\t %1.3f", wb1[q+8*p]); $fwrite (file2, "\n");
		$fwrite (file2, "w_UP%1d:      ", p);
		for(q=0;q<8;q=q+1) $fwrite (file2, "\t %1.3f", U_wb1[q+8*p]); $fwrite (file2, "\n");
		end
		$fdisplay(file2, "correct = %5d, recent_100 = %3d, EMS = %5f", correct, recent, EMS); 
		$fdisplay(file1, "%5f", EMS);
	end

	////////////////////////////////////////////////////////////////////////////////////
	// debug block end
	////////////////////////////////////////////////////////////////////////////////////

endmodule
