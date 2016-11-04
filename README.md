# dnn-RTL
RTL implementaion of USC's DNN system.

Testbench

DNN.v		//whole network

layer_block.v		// Contains processors, memory, state machines and other small logic for each layer

memory_ctr.v 		// State machine for each layer. It will generate all control signal for memory (address, enable), counter and mux
processor_set.v 	// FF, BP and UP processors

components.v		// Contain adders, multipliers, DFFs, counters, MUXes
memories.v			// Contains single/dual port memory (no parallel, parallel, many collections)
interleave.v		// DRP logic. It will generate memory index. some logic will generate memory address and mux signal by memory index
sigmoid_sigmoidprime_table.v		// Look-up table for sigmoid and sigmoid prime function



NOTES:			
Manual override required:
Sigmoid and sigmoid prime files, if bit widths are changed
Interleaver file, if interleaver parameters are changed. Also comment out higher m else if statements inside r_dither and w_dither in case of any issue while running smaller DNNs

Constraints:
p/z >= 2
fo >= 2
z >= fi [todo] add FFs for partial add to alleviate this

