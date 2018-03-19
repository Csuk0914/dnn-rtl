// Implementing start vector shuffle + sweep starter shuffle interleaver. For theory, see Asilomar paper
// Sourya Dey, Yinan Shao, USC

`timescale 1ns/100ps

// Input: eff_cycle_index (cycle_inex except MSB, like if cpc = 16+2, then cycle_index is 5b, but eff_cycle_index will be its 4 LSB)
// Output: The z neurons whose activations will be accessed, each indexed by log(p) bits
module interleaver_set #(
	parameter p  = 32,
	parameter fo = 2,
	parameter z  = 8,
	localparam log_pbyz = (p==z) ? 1 : $clog2(p/z)
	
	/* For every sweep from 0 to fo-1, there is a starting vector which is z elements long, where each element can take values from 0 to p/z-1
	* So total size of sweepstart is fo*z chunks of log(p/z) bits each. The whole thing can be psuedo-randomly generated in Python, then passed
  	* Here there are different cases defined for sweepstart - some small, and some very large (for MNIST) */	
	// sweepstart can be passed as a parameter, but this uses heavy logic during synthesis. So leave the following line commented out
	//parameter [log_pbyz*fo*z-1:0] sweepstart = 32'b10000111011100101101100000101101
)(
	input [$clog2(p*fo/z)-1:0] eff_cycle_index,
	// [Eg: Here total no. of cycles to process a junction = 8, so eff_cycle_index is 3b. It goes as 000 -> 001 -> ... -> 111]
	input reset,
	output [$clog2(p)-1:0] memory_index [z-1:0] //This has all actmem addresses [Eg: Here this has z=8 5b values indexing the 8 neurons to be accessed out of 32 lefthand neurons]
);
    
	logic [$clog2(p*fo)-1:0] wt [0:z-1]; //INDEX of output side weight being read, NOT the actual weight
	//z weights are read in each running of this module, and each has log(p*fo)-bit index since there are (p*fo) weights in total
	logic [log_pbyz-1:0] t [0:p-1]; //t is same as earlier capital S, i.e. the complete pattern for all p neurons in 1 sweep

	//NOTE: A better option is to store sweepstart in a 1D array of flops and initialize on reset
	logic [log_pbyz*fo*z-1:0] sweepstart = '0; // Misc, as well as the trivial case where p/z=1, for which sweepstart will only have 0s since each memory has just 1 element
	
	always @(posedge reset) begin
		// SMALLNET: Baby network 64x16x4, fo=2,2, z=32,8
		if ((p/z)==2 && (fo*z)==64) sweepstart <= 64'b1101000010111100010000000000001010100110011010111100010000011111;
		else if ((p/z)==2 && (fo*z)==16) sweepstart <= 16'b0111000110001110;
			  
		// MNIST_originalconfig: 1024x64x16, fo=8,8, z=512,32
	  	else if ((p/z)==2 && (fo*z)==4096) sweepstart <= 4096'hd0bc4002a66bc4751f90eeb78c9be0ca981fec47fd90e8b3fe04987a4c7f85d6a8c230af9b2bf8790c022274174bfbf0594e01ff2af007e00aacfbf99ad76093a54c24481c877e32d5f594bbb5da4b74592a287f7d62d18597be33d1e48e9e436303bdac2f4179549e7b422130a0cac25db4fadcc7f294c4952483db10bd3a5d728f85cb5dcdc8d991f919c9c74a1b8204ca6f99153e55037710af5076f148ad63c9460896e3e7f0b1ecd529796b3d65434207f94023e7454c279ec9e7b9d875f6b310c1cb7836375b3d1228f17627eeda16913b081ccba6647693f50cf9a19a670a4da6822fa607cda8d592900ab83ee9f4de3a60c190da75de196e57f705f0acc5742f58a5b55e3a53b8d5dead3d9bf7adbf08080f3ac4e695ce0609826ec8c71f74909a4a0a8ed599b42a96ed52b3a9458e6278a902b1e57884d9dff42714261b0a8f2eff82a63efc33121d11e224159fe6fe67d80480154e85e8b1b6325e905cceea9d1a875e6863fb89921e33bc01ff1aca31ccf6e20327a3055f5e5cf5b5de038085c5161b9ff66dd3bdd9bc4a664c8e702c927f7525e6a671571e4ed5dde329751d4fe5cf57a50a961baf00869a9a51048282f0f51923ad27780796248ca4d3b9073b1b6aa0393ff7c7558c033458cc2aa8e591a20a47656330e9779c241967812fc1ebaa5ef733080b955f92b504b5a3e96de41f8cb1ffdae4467c47;  
	  	else if ((p/z)==2 && (fo*z)==256) sweepstart <= 256'he53cd0663a8bcab10553bbc6244fe51b90ed33c5b344b91d44dd7a34e8a8f9a1;

		// MNIST_FPGAconfig64_32: 1024x64x64, fo=8,32, z=128,32
		else if ((p/z)==8 && (fo*z)==1024) sweepstart <= 3072'hc489e46e0a46be060c05c3e3c8cc17def49a010aa821483cc6e21a3717e058117308496a004b2b29d165013f477483f768018d0e03f81b23df2f7f8d94ab42e9290607732b9f20994fa0887887a3ba5a17633b1f58016653c89a6c4608554d5ae811381f4649dbeaddc08a9099ec2e934f218257be24f56f3b6f69e8b830a73e14c85cc7398ac0c36df101e86b07cf25d3a8d3747f29a3299329f708ff2fdf0ab8837f15af408f902043b3146107cdee84a5095e8f1a680a3b8bea7193cc26bd6bf2ab897b3fbf4cfaca9564889054ccd30e58127776ef590f9b8649fab267426f413bef2150b27010088ae836650995ef5aa1eccceeb81ea5e5b93856659249781eb1a917c938ce40227e64452b631d150fa81f9dca91176a24148ef613441edb2b8d9b85b5b9fd526d171697955dfdcea1f308db497050d3210c7c42fbe5340d9d6416c3662a7c101b0ba8c0683306a2619b2b8e46cc957ba75ee98ad070a98c0a60ac3c9dea0816d5db29d5070f75579de4c01f0aef63179ac017a2b62df9;
	  	else if ((p/z)==2 && (fo*z)==1024) sweepstart <= 1024'hc4c9a9576da777704f3f892c22db05d57c5f03e955f2019ca0ea50431658e83b771c538fbdcac3edbf349a62d79c491fbb302799f9ae99b1d53be79dd6819322795ecebe0224203a4231075029ff0a5427ec521edeb2d9457ed08ac91d98837f156c8e4c6e4ecac79899fb5bf50a7d8ad1b8ffb7bf967399fa23341a4476df63;			
		
		//MNIST_FPGAconfig64_16: 1024x64x64, fo=8,16, z=128,16
		else if ((p/z)==4 && (fo*z)==256) sweepstart <= 512'hb1149ad3431e906c349ad0f66654ea7e6670b3de871dccab51d716017db7f12a681a801ac48dd8737ea8eb97d94a14bb4ae02194e1c702cefb1531780837d849;
			
		//MNIST_FPGAconfig64_8: 1024x64x64, fo=8,8, z=128,8
		else if ((p/z)==8 && (fo*z)==64) sweepstart <= 192'hcaca2edf89b471e3b5539eab9f4f221fb1e121821447f4cd;
			
		// MNIST_FPGAconfig64_4: 1024x64x64, fo=8,4, z=128,4
		else if ((p/z)==16 && (fo*z)==16) sweepstart <= 64'hea5d44b212720f4e;
			
		/* Extra case: Probably 512x32x16, fo=2,2, z=256,8
		else if ((p/z)==2 && (fo*z)==512) sweepstart <= 512'hd0bc4002a66bc4751f90eeb78c9be0ca981fec47fd90e8b3fe04987a4c7f85d6d0bc4002a66bc4751f90eeb78c9be0ca981fec47fd90e8b3fe04987a4c7f85d6;
		else if ((p/z)==4 && (fo*z)==16) sweepstart <= 32'b10000111011100101101100000101101; */
	end
	
	genvar gv_i, gv_j;
	generate for (gv_i = 0; gv_i < p/z; gv_i++) begin: create_t_outer
		for (gv_j = 0; gv_j<z; gv_j++) begin: create_t_inner
			if (p==z) assign t[gv_j] = 0; //If p=z, then t has p singleton elements, which are all 0
			
			/* For addition, we don't need to put modulo p/z because each chunk of sweepstart is p/z bits, so it automatically does modulo
			Eg: If p/z=4, then each chunk of sweepstart is 0 or 1 or 2 or 3.
			So if we do something like sweepstart[6th chunk]+3 = 3+3 = 6, it automatically stores 6 as 6%4=2 (i.e. 2 is stored in a chunk)] */		
			else begin
			
				//If fo=1, sweepstart just has z chunks of log_pbyz bits each. Just pick the relevant chunk and add offset = gv_i
				if (fo==1) assign t[gv_i*z+gv_j] = sweepstart[gv_j*log_pbyz +: log_pbyz] + gv_i;
				
				/*If fo>1, sweepstart will have fo*z chunks of log_pbyz bits each. In this case, we need to shift the chunk of sweepstart depending on the sweep number
				[Eg: Say p=32, fo=4, z=8 => eff_cycle_index goes from 0000 -> 1111. The 2 MSBs give the sweep number, so we add 2MSBs*z to the chunk index of sweepstart]*/
				// We don't need to worry about the case where p*fo=z, because if so, then p must be = z, which has already been taken care of above
				else assign t[gv_i*z+gv_j] = sweepstart[(gv_j + z*eff_cycle_index[$clog2(p*fo/z)-1 : log_pbyz]) * log_pbyz  +:  log_pbyz] + gv_i;
			end
		end
	end
	endgenerate
	

	generate //actual interleaver
		for (gv_i = 0; gv_i<z; gv_i++) begin
			assign wt[gv_i] = eff_cycle_index*z + gv_i; /*Get weight index
			Now convert weight index to interleaved activation number, i.e. neuron number
			Note that the final expression on copy is a weight interleaver:  pi[i] = (t[i%p]*z + (i%z))*fo + (i/p)
			Here we delete the last 2 terms to get act[i] = t[i%p]*z + (i%z), where i = wt[gv_i] */ 
			if (z>1)
				assign memory_index[gv_i] = t[wt[gv_i][$clog2(p)-1:0]]*z + wt[gv_i][$clog2(z)-1:0];
			else
				assign memory_index[gv_i] = t[wt[gv_i][$clog2(p)-1:0]];
		end
	endgenerate
endmodule
