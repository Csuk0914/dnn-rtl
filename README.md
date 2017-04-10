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



RUNNING: (Key: [NC] - Network configuration changed only, [BW] - Bit widths changed only, [SIM] - Behavioral Simulation in either Modelsim or Vivado, [SYNTH] - Synthesis in Vivado)

Testbench [SIM]
	
	[General] Make sure correct simulator (Modelsim or Vivado) portion is uncommented in Data import block. If using Vivado, please UNTICK xsim.simulate.log_all_signals in Simulation tab in Simulation Settings in Left Pane
	[NC] Create new testbench (use tb_mnist as ref)
	[NC,BW] Change parameters at top
	[NC] In the Modelsim and Vivado portions in data import, change 784,783,10,9 to nin,nin-1,nout,nout-1 (numbers of input and output neurons)
	[NC,BW] Change Gaussian file names
	
DNN.v

	[NC] Delete this following line wherever it comes, when applicable: /****************** DELETE THIS LINE if z[L-2]/fi[L-2]>1 ************************
	[NC,BW][SYNTH] Change parameters at top
	
memories.v

	[NC][SIM] Search for tb_ (match case) in memories.v and change it to the testbench module name being used, like tb_mnist
	[SYNTH] Comment out initial blocks and the integer declarations preceding them
	
interleavers (Assume interleaver_array unless otherwise noted)

	[NC] Define all sweepstart cases for different p/z and fo*z
	[NC,BW] If interleaver_drp is used, comment out higher m else if statements inside r_dither and w_dither in case of any issue while running smaller DNNs
	[SYNTH] Comment out the sweepstart cases not used
	
sigmoid_sigmoidprime_table.v

	[BW] Refer to comments at top of /src/sigmoid_sigmoidprime_table.v and /scripts/actlut_generator.py

Gaussian lists

	[NC,BW] Regenerate using /src/glorotnormal_init_generator.py
	Put new files in local Verilog folder on Windows
	
New datasets [NC]

	Use scripts/create_data to get training input and output files in Vivado format.
	The file is not completely parameterized - refer to comments on top
	(Additional processing needs to be added for Modelsim format)
	Put new files in local Verilog folder on Windows

Location of Files:

	[SIM] Modelsim [Sourya's Machine]: Windows -> Verilog/DNN
	[SIM] Vivado: Windows -> <Vivado folder>/<projectname>/<projectname>.sim/sim_1/behav
	[SYNTH] Basic report: <Vivado folder>/<projectname>/<projectname>.runs/synth_1/<topmodulename>_utilization_synth.rpt
	[SYNTH] Detailed report: <Vivado folder>/<projectname>/<projectname>.runs/synth_1/<topmodulename>.vds
	[General] Periodically delete Windows -> <Vivado folder>/<projectname>/<projectname>.cache to save space


CONSTRAINTS:
	
	p/z >= 2	
	fo >= 2	
	z >= fi [todo] MAYBE add FFs for partial add to alleviate this
