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
	parameter cost_type = 0, //0 for quadcost, 1 for xentcost
	// Testbench parameters:
	parameter training_cases = 10000, //number of cases to consider out of entire MNIST. Should be <= 50000
	parameter total_training_cases = 10*training_cases, //total number of training cases over all epochs
	//parameter test_cases = 8,
	parameter checklast = 1000, //how many previous inputs to compute accuracy from
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
	reg [$clog2(training_cases)-1:0] sel_tc = 0; //MUX select to choose training case each block cycle
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
	// Basic performance evaluation
	////////////////////////////////////////////////////////////////////////////////////
	wire cycle_clk;
	wire [$clog2(cpc)-1:0] cycle_index;
	integer num_train = 0; //Number of the current training case
	integer epoch = 0;
	reg tc_error = 0; //Flags if a particular training case gives error (in any of its neurons)
	integer total_error = 0; //Total number of tc_errors accumulated over training cases
	//real error_rate = 0;
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
		//$display("Error rate = %2.5f", error_rate);
		//$fdisplay(file, "%0d", total_error);
		if (tc_error != 0) total_error = total_error+1;
		
		//Start new training case
		num_train <= num_train + 1;
		sel_tc <= (sel_tc == training_cases-1)? 0 : sel_tc + 1;
		if (sel_tc == 0) begin
			$display("finish training epoch %0d", epoch);
			epoch = epoch + 1;
		end
		tc_error <= 0;
		//error_rate <= 0;
		
		if (num_train==total_training_cases) $stop;
	end

	always @(posedge clk) begin
		if (cycle_index > 1 && a_out != y_out) tc_error = 1; //Since output is obtained starting from cycle 2 up till cycle (cpc-1)
		/*if( cycle_index > 1)
			// Need to divide actL by 2**frac_bits to get result between 0 and 1
			if(y_out) error_rate = error_rate + y_out - DNN.actL/(2**frac_bits); //y_out = 1, so |y_out-actL| = 1-actL
			else error_rate = error_rate + DNN.actL/(2**frac_bits); //y_out = 0, so |y_out-actL| = actL */
	end



	////////////////////////////////////////////////////////////////////////////////////
	// data import block [todo] Modify this portion to have 512 inputs
	// train_input.dat contains 50000 MNIST pattern. Each pattern contain 28*28 pixels which is 8 bit gray scale.
	// 					1 line is one pattern with 784 8bit hex.
	// train_idealout.dat is the data set for 50000 correct result of training data. There are 10 bits one-hot represent 10 digital number.
	//					1 line is one pattern with 10 one-hot binary.
	//data import need to be fixed to the DNN network which is 1024 input and 16 output.
	//For the training data input, the first 784 values are from one trainning pattern and the rest input bits are set to 0.
	//For the idealout input, the first 10 values are from the training result with the same index to training pattern and the rest bits are set to 0.
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
		eta = Eta * (2 ** frac_bits); //convert the Eta to fix point
		eta = ~eta + 1;
		$readmemb("train_idealout.dat", y_mem);
		$readmemh("train_input.dat", a_mem);
	end
	////////////////////////////////////////////////////////////////////////////////////
	
	////////////////////////////////////////////////////////////////////////////////////
	/* This whole block is used for debug. Comment it in normal simulation
		The following line converts any variable x[width-1:0] from its 2'c complement binary representation to signed decimal representation
		x/2.0**frac_bits - x[width-1]*2.0**(1+int_bits)  */
	////////////////////////////////////////////////////////////////////////////////////
	integer  q, //loop variable
				correct, //signals whether current training case is correct or not
				recent = 0; //counts #correct in last 1000 training cases
	integer  crt[checklast:0], //stores last 1000 results - each result is either 1 or 0
				crt_pt=0; //points to where current training case result will enter. Loops around on reaching 1000
	// For the next few variables:
	// cpc = Cycles+2, e.g. cycles=16, cpc=18. So [cpc-3:0] creates 16 values to store outputs of 16 cycles.
	real  net_a_out[cpc-3:0], //Actual 32-bit output of network
			net_y_out[cpc-3:0], //Ideal output y
			//a_minus_y[cpc-3:0],
			delta[cpc-3:0], //a-y
			//spL[cpc-3:0],
			zL[cpc-3:0]; //output layer z, i.e. just before taking final sigmoid
	real  train_n=0, //training case number
			EMS; //Expected mean square error between a_out and y_out of all neurons in output layer
	//The following variables store information of the 0th cycle (when cycle_index = 2 out of 17) as fed to the update processor
	real  wb1[z[L-2]+z[L-2]/fi[L-2]-1:0], //pre-update weights = z[L-2] + biases = z[L-2]/fi[L-2]
			//del_wb1[z[L-2]+z[L-2]/fi[L-2]-1:0], //updated weights and biases
			a1[z[L-2]-1:0]; //activations (which get multiplied by deltas for weight updates) 
	integer file1, file2;

	initial begin
		file1 = $fopen("EMS.dat");
		file2 = $fopen("log.dat"); //Stores a lot of info
		for(q=0;q<=checklast;q=q+1) crt[q]=0; //initialize all 1000 places to 0
	end

	always @(negedge clk) begin
		if (cycle_index==2) begin
			for (q=0;q<z[L-2];q=q+1) begin //Weights and activations
				a1[q] = DNN.hidden_layer_block_1.UP_processor.a[q]/2.0**frac_bits - DNN.hidden_layer_block_1.UP_processor.a[q][width-1]*2.0**(1+int_bits);
				wb1[q] = DNN.hidden_layer_block_1.UP_processor.w[q]/2.0**frac_bits - DNN.hidden_layer_block_1.UP_processor.w[q][width-1]*2.0**(1+int_bits);
				//del_wb1[q] = DNN.hidden_layer_block_1.UP_processor.delta_w[q]/2.0**frac_bits - DNN.hidden_layer_block_1.UP_processor.delta_w[q][width-1]*2.0**(1+int_bits);
			end
			for (q=z[L-2];q<z[L-2]+z[L-2]/fi[L-2];q=q+1) begin //Biases
				wb1[q] =DNN.hidden_layer_block_1.UP_processor.b[q-z[L-2]]/2.0**frac_bits - DNN.hidden_layer_block_1.UP_processor.b[q-z[L-2]][width-1]*2.0**(1+int_bits);
				//del_wb1[q] =DNN.hidden_layer_block_1.UP_processor.delta_b[q-z[L-2]]/2.0**frac_bits - DNN.hidden_layer_block_1.UP_processor.delta_b[q-z[L-2]][width-1]*2.0**(1+int_bits);
			end
		end
		if (cycle_index>1) begin //Actual output, ideal output, delta
			net_a_out[cycle_index-2] = DNN.actL/2.0**frac_bits;
			net_y_out[cycle_index-2] = DNN.y_out; //Division is not required because it is not in 32-bit form
			// a_minus_y[cycle_index-2] = DNN.output_layer_block.a_minus_y/2.0**frac_bits - DNN.output_layer_block.a_minus_y[width-1]*2.0**(1+int_bits);
			// spL[cycle_index-2] = DNN.output_layer_block.spL/2.0**frac_bits - DNN.output_layer_block.spL[width-1]*2.0**(1+int_bits);
			delta[cycle_index-2] = DNN.output_layer_block.delta/2.0**frac_bits - DNN.output_layer_block.delta[width-1]*2.0**(1+int_bits);
		end
		if (cycle_index>0 && cycle_index<=cpc-2) begin //z of output layer
			zL[cycle_index-1] = DNN.hidden_layer_block_1.FF_processor.sigmoid_function_set[0].s_function.s/2.0**frac_bits - DNN.hidden_layer_block_1.FF_processor.sigmoid_function_set[0].s_function.s[width-1]*2.0**(1+int_bits);
		end
	end
	
	always @(posedge cycle_clk) begin
		train_n = train_n + 1;
		recent = recent - crt[crt_pt]; //crt[crt_pt] is the value about to be replaced 
		correct = 1; //temporary placeholder
		for (q=0;q<cpc-2;q=q+1) begin
			if((net_a_out[q]>0.5 && net_y_out[q]<0.5)||(net_a_out[q]<0.5 && net_y_out[q]>0.5)) correct=0; //If any output neuron has wrong threshold value, whole thing becomes wrong
		end
		crt[crt_pt] = correct;
		recent = recent + crt[crt_pt]; //Update recent with value just stored
		crt_pt = (crt_pt==checklast)? 0 : crt_pt+1;
		
		EMS = 0;
		for (q=0;q<cpc-2;q=q+1) EMS = delta[q]*delta[q] + EMS;
		EMS = EMS * 100;

		// Transcript display - case number, actual output, ideal output, delta, stats
		$display ("-----------------------------train: %d", train_n);
		$write ("actual output:");
		for(q=0;q<cpc-2;q=q+1) $write ("\t %1.4f", net_a_out[q]); $write ("\n");
		$write ("ideal output: ");
		for(q=0;q<cpc-2;q=q+1) $write ("\t %1.4f", net_y_out[q]); $write ("\n");
		$write ("delta:        ");
		for(q=0;q<cpc-2;q=q+1) $write ("\t %1.4f", delta[q]); $write ("\n");
		$display("correct = %5d, recent_%4d = %3d, EMS = %5f", correct, checklast, recent, EMS); 

		// Write to log file - Everything
		$fdisplay (file2,"-----------------------------train: %d", train_n);
		$fwrite (file2, "actual output:");
		for(q=0;q<cpc-2;q=q+1) $fwrite (file2, "\t %1.4f", net_a_out[q]); $fwrite (file2, "\n");
		$fwrite (file2, "ideal output: ");
		for(q=0;q<cpc-2;q=q+1) $fwrite (file2, "\t %1.4f", net_y_out[q]); $fwrite (file2, "\n");
		$fwrite (file2, "delta:        ");
		for(q=0;q<cpc-2;q=q+1) $fwrite (file2, "\t %1.4f", delta[q]); $fwrite (file2, "\n");
		$fwrite (file2, "z:            ");
		for(q=0;q<cpc-2;q=q+1) $fwrite (file2, "\t %1.4f", zL[q]); $fwrite (file2, "\n");
		// $fwrite (file2, "a-y:          ");
		// for(q=0;q<cpc-2;q=q+1) $fwrite (file2, "\t %1.4f", a_minus_y[q]); $fwrite (file2, "\n");
		// $fwrite (file2, "spL:          ");
		// for(q=0;q<cpc-2;q=q+1) $fwrite (file2, "\t %1.4f", spL[q]); $fwrite (file2, "\n");
		$fwrite (file2, "a1:     ");
		for(q=0; q<z[L-2]; q=q+1) $fwrite (file2, "\t %1.3f", a1[q]); $fwrite (file2, "\n");
		$fwrite (file2, "w12:     ");
		for(q=0; q<z[L-2]; q=q+1) $fwrite (file2, "\t %1.3f", wb1[q]); $fwrite (file2, "\n");
		$fwrite (file2, "b2:     ");
		for(q=z[L-2]; q<z[L-2]+z[L-2]/fi[L-2]; q=q+1) $fwrite (file2, "\t %1.3f", wb1[q]); $fwrite (file2, "\n");
		//$fwrite (file2, "delta_w12:     ");
		//for(q=0; q<z[L-2]; q=q+1) $fwrite (file2, "\t %1.3f", del_wb1[q]); $fwrite (file2, "\n");
		//$fwrite (file2, "delta_b2:     ");
		//for(q=z[L-2]; q<z[L-2]+z[L-2]/fi[L-2]; q=q+1) $fwrite (file2, "\t %1.3f", del_wb1[q]); $fwrite (file2, "\n");
		$fdisplay(file2, "correct = %5d, recent_%4d = %3d, EMS = %5f", correct, checklast, recent, EMS); 
		$fdisplay(file1, "%5f", EMS); //Write separately to EMS file
	end
	////////////////////////////////////////////////////////////////////////////////////
	// debug block end
	////////////////////////////////////////////////////////////////////////////////////
endmodule
