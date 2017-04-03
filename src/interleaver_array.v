// Implementing rs_chng + rsweep_chng interleaver
`timescale 1ns/100ps

module interleaver_set #(
	parameter fo = 2,
	parameter fi  = 4,
	parameter p  = 32,
	parameter n  = 8,
	parameter z  = 8
	
	/* For every sweep from 0 to fo-1, there is a starting vector which is z elements long, where each element can take values from 0 to p/z-1
	* So total size of sweepstart is fo*z chunks of log(p/z) bits each. The whole thing can be psuedo-randomly generated in Python, then passed
  	* Here there are different cases defined for sweepstart - some small, and some very large (for MNIST) */
	
	// sweepstart can be passed as a parameter, but this uses heavy logic during synthesis. So leave the following line commented out
	//parameter [$clog2(p/z)*fo*z-1:0] sweepstart = 32'b10000111011100101101100000101101
)(
	input [$clog2(fo*p/z)-1:0] cycle_index, //log of total number of cycles to process a junction = log(no. of weights / z)
	// [Eg: Here total no. of cycles to process a junction = 8, so cycle_index is 3b. It goes as 000 -> 001 -> ... -> 111]
	input reset,
	output [$clog2(p)*z-1:0] memory_index_package //This has all actmem addresses [Eg: Here this has z=8 5b values indexing the 8 neurons to be accessed out of 32 lefthand neurons]
);
    
	wire [$clog2(p*fo)-1:0] wt [0:z-1]; //Index of output side weight being read
	//z weights are read in each running of this module, and each has log(p*fo)-bit index since there are (p*fo) weights in total
	wire [$clog2(p/z)-1:0] t [0:p-1]; //t is same as earlier capital S, i.e. the complete pattern for all p neurons in 1 sweep
	wire [$clog2(p)-1:0] memory_index [0:z-1];

	// A better option is to store sweepstart in a 1D array of flops and initialize on reset
	reg [$clog2(p/z)*fo*z-1:0] sweepstart;
	always @(posedge reset) begin
		// Baby network 64x16x4
		if ((p/z)==2 && (fo*z)==64)
	  	  	sweepstart = 64'b1101000010111100010000000000001010100110011010111100010000011111;
		else if ((p/z)==2 && (fo*z)==16)
		  	  sweepstart = 16'b0111000110001110;
			  
		// MNIST 1024x64x16
	  	else if ((p/z)==2 && (fo*z)==4096)
			sweepstart = 4096'hd0bc4002a66bc4751f90eeb78c9be0ca981fec47fd90e8b3fe04987a4c7f85d6a8c230af9b2bf8790c022274174bfbf0594e01ff2af007e00aacfbf99ad76093a54c24481c877e32d5f594bbb5da4b74592a287f7d62d18597be33d1e48e9e436303bdac2f4179549e7b422130a0cac25db4fadcc7f294c4952483db10bd3a5d728f85cb5dcdc8d991f919c9c74a1b8204ca6f99153e55037710af5076f148ad63c9460896e3e7f0b1ecd529796b3d65434207f94023e7454c279ec9e7b9d875f6b310c1cb7836375b3d1228f17627eeda16913b081ccba6647693f50cf9a19a670a4da6822fa607cda8d592900ab83ee9f4de3a60c190da75de196e57f705f0acc5742f58a5b55e3a53b8d5dead3d9bf7adbf08080f3ac4e695ce0609826ec8c71f74909a4a0a8ed599b42a96ed52b3a9458e6278a902b1e57884d9dff42714261b0a8f2eff82a63efc33121d11e224159fe6fe67d80480154e85e8b1b6325e905cceea9d1a875e6863fb89921e33bc01ff1aca31ccf6e20327a3055f5e5cf5b5de038085c5161b9ff66dd3bdd9bc4a664c8e702c927f7525e6a671571e4ed5dde329751d4fe5cf57a50a961baf00869a9a51048282f0f51923ad27780796248ca4d3b9073b1b6aa0393ff7c7558c033458cc2aa8e591a20a47656330e9779c241967812fc1ebaa5ef733080b955f92b504b5a3e96de41f8cb1ffdae4467c47;  
	  	else if((p/z)==2 && (fo*z)==256)
			sweepstart = 256'he53cd0663a8bcab10553bbc6244fe51b90ed33c5b344b91d44dd7a34e8a8f9a1;
			
		// Extra cases
		/*else if ((p/z)==4 && (fo*z)==16)
			sweepstart = 32'b10000111011100101101100000101101;
		else if ((p/z)==2 && (fo*z)==512)
			  		sweepstart = 512'hd0bc4002a66bc4751f90eeb78c9be0ca981fec47fd90e8b3fe04987a4c7f85d6d0bc4002a66bc4751f90eeb78c9be0ca981fec47fd90e8b3fe04987a4c7f85d6;*/
		
		// Dummy case
		else   
	  		sweepstart = 1'b0;
	end

	// OLD WAY OF DOING 2D SWEEPSTART - CHECK interleaver_array_old.v if any issue occurs with 1D sweepstart
	//reg [$clog2(p/z)-1:0] sweepstart [0:fo*z-1];
	// This was followed by huge declarations of the form '{1'd0, 1'd1 ...
	
	genvar gv_i, gv_j;
	generate //create t
		for (gv_i = 0; gv_i < p/z; gv_i = gv_i+1) begin
			for (gv_j = 0; gv_j<z; gv_j = gv_j+1) begin
				/* For addition, we don't need to put modulo p/z because each chunk of sweepstart is p/z bits, so it automatically does modulo
				Eg: If p/z=4, then each chunk of sweepstart is 0 or 1 or 2 or 3.
				So if we do something like sweepstart[6th chunk]+3 = 3+3 = 6, it automatically stores 6 as 6%4=2 (i.e. 2 is stored in a chunk)] */
				
				//If fo=1, sweepstart just has z chunks. Just pick the relevant chunk and add offset
				if (fo==1) assign t[gv_i*z+gv_j] = sweepstart[(gv_j+1)*$clog2(p/z)-1:gv_j*$clog2(p/z)]+gv_i; //1D
				//if (fo==1) assign t[gv_i*z+gv_j] = sweepstart[gv_j]+gv_i; //2D
				
				/*If fo>1, sweepstart will have fo*z chunks. In this case, we need to shift the chunk of sweepstart depending on the sweep number
				[Eg: Say p=32, fo=4, z=8 => cycle_index goes from 0000 -> 1111. The 2 MSBs give the sweep number, so we add 2MSBs*z to the chunk index of sweepstart]*/
				else assign t[gv_i*z+gv_j] = sweepstart[(gv_j+z*cycle_index[$clog2(fo*p/z)-1:$clog2(p/z)])*$clog2(p/z) +: $clog2(p/z)] + gv_i; //1D
				//else assign t[gv_i*z+gv_j] = sweepstart[gv_j+cycle_index[$clog2(fo*p/z)-1:$clog2(p/z)]*z]+gv_i; //2D
			end
		end
	endgenerate
	

	generate //actual interleaver
		for (gv_i = 0; gv_i<z; gv_i = gv_i + 1) begin
			assign wt[gv_i] = cycle_index*z + gv_i; //Get weight number
			assign memory_index[gv_i] = t[wt[gv_i][$clog2(p)-1:0]]*z + wt[gv_i][$clog2(z)-1:0]; /*Convert weight number to interleaved ACTIVATION number, i.e. neuron number
			Note that the final expression on copy is a weight interleaver:  pi[i] = (t[i%p]*z + (i%z))*fo + (i/p)
			Here we delete the last 2 terms to get act[i] = t[i%p]*z + (i%z), where i = wt[gv_i] */ 
		end
	endgenerate

	generate //pack memory_index into package in opposite order
	// i.e. M0 goes to 1st p bits, then M1 and finally Mz-1. This ordering doesn't really matter
		for (gv_i = 0; gv_i<z; gv_i = gv_i + 1) begin
			assign memory_index_package[$clog2(p)*(gv_i+1)-1:$clog2(p)*gv_i] = memory_index[gv_i];
		end
	endgenerate
endmodule


/* Old code for creating s from r:
		if (z >= p/z) begin
			for (gv_i = 0; gv_i < z*z/p; gv_i = gv_i+1) begin
				for (gv_j = 0; gv_j < p/z; gv_j = gv_j+1) begin
					assign s[gv_i*p/z+gv_j] = r[gv_j];
				end
			end
		end else begin // Here z < p/z
			for (gv_i = 0; gv_i<z; gv_i = gv_i + 1) begin
				assign s[gv_i] = r[gv_i];
			end
		end
*/
