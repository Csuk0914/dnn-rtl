# dnn-RTL
RTL and FPGA implementaion of USC's DNN system - Sourya, Yinan, Chiye, Mahdi

testbench - Main file is tb_mnist.v. Other files are for baby networks or submodules.

src - All source code Verilog files. Hierarchy:

	DNN.v	-	whole network
	layer_block.v	-	Contains processors, memory, state machines and other small logic for each layer
	memory_ctr.v	-	State machine for each layer. Generates control signals for memory (address, enable), counter and mux
	processor_set.v	-	FF, BP and UP processors
	components.v	-	Contain adders, multipliers, DFFs, counters, MUXes
	memories.v	-	Contains single/dual port memory (no parallel, parallel, many collections)
	interleaver_array.v	-	// Array interleaver to generate memory index, address and mux signals for index
	interleaver_drp.v	-	DRP interleaver
	sigmoid_sigmoidprime_table.v	-	Look-up table for sigmoid and sigmoid prime function

data - Datasets

gaussian_list - Weight intialization

scripts - Python codes to generate LUTs, gaussian lists, calculate FPGA usage etc

misc_stuff - Some images

FPGA - All FPGA specific files like UART, board files, xdc, etc

bin - Top level binary files (Mahdi)



WHENEVER SIMULATING:

If simulator is changed:

	testbench - Make sure correct simulator (Modelsim or Vivado) portion is uncommented in Data import block.
	If using Vivado, please UNTICK xsim.simulate.log_all_signals in Simulation tab in Simulation Settings in Left Pane

If bit widths are changed:
	
	Sigmoid and sigmoid prime files - Refer to comments at top of /src/sigmoid_sigmoidprime_table.v and /scripts/actlut_generator.py
	Gaussian lists - Regenerate using /src/glorotnormal_init_generator.py and put new files in local Verilog folder on Windows
	tb_mnist - Change parameters at top. Change gaussian file names there.

If network parameters are changed:
	
	New datasets may need to be generated:
		Use scripts/create_data to get training input and output files in Vivado format.
		The file is not completely parameterized - refer to comments on top
		(Additional processing needs to be added for Modelsim format)
	Gaussian lists have to be regenerated for new fi, fo (see above sec for details)
	Add new datasets and Gaussian lists to Verilog folder on Windows desktop
	DNN.v - Delete this following line wherever it comes, when applicable: /****************** DELETE THIS LINE if z[L-2]/fi[L-2]>1 ************************
	memories.v - Search for tb_ (match case) in memories.v and change it to the testbench module name being used, like tb_mnist
	interleaver_array.v - Define all sweepstart cases for different p/z and fo*z
	If interleaver_drp is used, comment out higher m else if statements inside r_dither and w_dither in case of any issue while running smaller DNNs
	Testbench: (Use tb_mnist as reference)
		Best is to create a new testbench for each dataset
		Change parameters at top
		In the Modelsim and Vivado portions in data import, change 784,783,10,9 to nin,nin-1,nout,nout-1 (numbers of input and output neurons)
		Change Gaussian file names
	If bit widths and simulator are also changed, see above sections


SIMULATION FILES: (Sourya's machine only)

	Modelsim: VBox Windows Desktop -> Verilog/DNN
	Vivado: VBox Windows Desktop -> Vivado/projectname/projectname/projectname.sim/sim_1/behav
	Periodically delete VBox Windows Desktop -> Vivado/projectname/projectname.cache to save space


CONSTRAINTS:
	
	p/z >= 2	
	fo >= 2	
	z >= fi [todo] MAYBE add FFs for partial add to alleviate this
