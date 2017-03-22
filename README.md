# dnn-RTL
RTL and FPGA implementaion of USC's DNN system - Sourya, Yinan, Chiye, Mahdi


bin - Top level binary files (Mahdi)


data - Datasets


testbench - Main file is tb_mnist.v. Other files are for baby networks or submodules.


src - All source code Verilog files. Hierarchy:

	DNN.v	-	whole network

	layer_block.v	-	Contains processors, memory, state machines and other small logic for each layer

	memory_ctr.v	-	State machine for each layer. It will generate all control signal for memory (address, enable), counter and mux

	processor_set.v	-	FF, BP and UP processors

	components.v	-	Contain adders, multipliers, DFFs, counters, MUXes

	memories.v	-	Contains single/dual port memory (no parallel, parallel, many collections)

	interleaver_array.v	-	// Array interleaver to generate memory index, address and mux signals for index

	interleaver_drp.v	-	DRP interleaver

	sigmoid_sigmoidprime_table.v	-	Look-up table for sigmoid and sigmoid prime function


gaussian_list - Weight intialization


scripts - Python codes to generate LUTs, gaussian lists, calculate FPGA usage etc


misc_stuff - Some images


FPGA - All FPGA specific files like UART, board files, xdc, etc



NOTES:			

Manual override required when bit widths are changed:
	
	Sigmoid and sigmoid prime files - Refer to comments at top of /src/sigmoid_sigmoidprime_table.v and /scripts/actlut_generator.py_
	
	Gaussian lists - Regenerate using /src/glorotnormal_init_generator.py and put new files in local Verilog folder on Windows
	tb_mnist - Change parameters at top. Make sure correct simulator (Modelsim or Vivado) portion is uncommented in Data import block. Change gaussian file names there.
	
Manual overrides required when network parameters are changed:
	
	DNN.v - Delete these 2 lines when applicable:
	/****************** DELETE THIS LINE if z[L-2]/fi[L-2]>1 ************************
	
	Interleaver file, if interleaver parameters are changed. Also comment out higher m else if statements inside r_dither and w_dither in case of any issue while running smaller DNNs


Constraints:
	
	p/z >= 2
	
	fo >= 2
	
	z >= fi [todo] MAYBE add FFs for partial add to alleviate this

