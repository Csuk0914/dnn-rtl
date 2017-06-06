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

tb_DNN.v
	
	[General] define: Uncomment used simulator - Modelsim or Vivado. If using Vivado, UNTICK xsim.simulate.log_all_signals in Simulation tab in Simulation Settings in Left Pane
	[NC] define: Comment out entire chunk of defines for dataset, nin, nout, tc, ttc, checklast, and define new ones
	[NC,BW] Change eta and other params inside #(). Define new `ifdef cases for network params as required
	[NC,BW] Add new `ifdef cases for Gaussian file names in data import block
	
DNN.v

	[NC] define: Uncomment MULTIOUT when applicable
	[NC,BW][SYNTH] Change parameters inside #(). NOT REQUIRED for SIM ONLY.
	
layer_block.v

	[Cost Function] define: Uncomment used cost method

processor_set.v

	[Eta] define: If Eta is NOT a power of 2 between 2^0 to 2^(-frac_bits), comment out ETA2POWER

memories.v

	[SIM] define: Uncomment SIM
	[WtBias Initialization] define: initmemsize should match initmemsize in testbench

interleavers (Assume interleaver_array unless otherwise noted)

	[NC] define: Uncomment used dataset
	[NC,BW] If interleaver_drp is used, comment out higher m else if statements inside r_dither and w_dither in case of any issue while running smaller DNNs

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
	
	p = k*z, k >= 2	
	fo >= 2
	z = k*fi (since an integral number of output neurons must be processed in 1 cycle [TODO] MAYBE add FFs for partial add to alleviate this)



Variable naming conventions: (RTL = hardware Verilog, HL = high level Python)
	
	act = activation
	ans (RTL), ideal (HL) = ideal output
	adot = activation derivative
	del = delta
	wt = weight
	bias = bias
	actwt = activation * weight
	FF = feedforward
	BP = backpropagation
	UP = update
	delta = change in value of any quantity. DO NOT confuse with delta values, which are del

	Junction specific:
	p = # neurons in a layer before a junction
	n = # neurons in a layer after a junction
	fo = Fanout
	fi = Fanin
	W = Total weights = p*fo = n*fi

	For RTL only:
	outside to input layer = 0, input-hidden junctio = 1, hidden-output junction = L-1 (=2), output layer to outside = L (=3)
	within a layer = in for incoming, out for outgoing (regardless of direction, e.g. del_in would come from next layer)
	package = 1D data which needs to be split into 2D (or vice-versa). This is because Verilog can't handle 2D I/O :'-(
	calc = Real number value, not Verilog register or wire in bits
	coll = collection level, i.e. many memory banks
	mem = memory bank level (Might have different meaning in testbench). In applicable situation with neither coll or mem, it means at a single memory level
	r = read
	w = write
	addr = address
	pt = pointer
	we = write enable
	A, B = ports in dual-port memory
