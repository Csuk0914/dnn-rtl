// This file contains a number of different types of memories
`timescale 1ns/100ps

/* Single port memory
Using mode read-first and latency = 1
Old data is first read from memory on a posedge
Then new data is written on the same posedge
If any data or address changes between edges, it will be written into or read from memory on next posedge (latency = 1)
*/
module memory #(
	parameter depth = 2, //No. of cells
	parameter width = 12, //No. of bits in each cell
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input [addrsize-1:0] address,
	input we, //write enable
	input signed [width-1:0] data_in,
	output signed [width-1:0] data_out
);

	// xpm_memory_spram: Single Port RAM
	// Xilinx Parameterized Macro, Version 2017.4
	xpm_memory_spram # (
	  
	  // Common module parameters
	  .MEMORY_SIZE             (width*depth),     //positive integer
	  .MEMORY_PRIMITIVE        ("auto"),          //string; "auto", "distributed", "block" or "ultra";
	  .MEMORY_INIT_FILE        ("none"),          //string; "none" or "<filename>.mem" 
	  .MEMORY_INIT_PARAM       (""    ),          //string;
	  .USE_MEM_INIT            (1),               //integer; 0,1
	  .WAKEUP_TIME             ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin" 
	  .MESSAGE_CONTROL         (0),               //integer; 0,1
	  .MEMORY_OPTIMIZATION     ("true"),          //string; "true", "false" 
	
	  // Port A module parameters
	  .WRITE_DATA_WIDTH_A      (width),              //positive integer
	  .READ_DATA_WIDTH_A       (width),              //positive integer
	  .BYTE_WRITE_WIDTH_A      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
	  .ADDR_WIDTH_A            (addrsize),               //positive integer
	  .READ_RESET_VALUE_A      ("0"),             //string
	  .ECC_MODE                ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode" 
	  .AUTO_SLEEP_TIME         (0),               //Do not Change
	  .READ_LATENCY_A          (1),               //non-negative integer
	  .WRITE_MODE_A            ("read_first")     //string; "write_first", "read_first", "no_change" 
	
	) singleportmem (
	
	  // Common module ports
	  .sleep                   (1'b0),
	
	  // Port A module ports
	  .clka                    (clk),
	  .rsta                    (reset),
	  .ena                     (1'b1),
	  .regcea                  (1'b1),
	  .wea                     (we),
	  .addra                   (address),
	  .dina                    (data_in),
	  .injectsbiterra          (1'b0),
	  .injectdbiterra          (1'b0),
	  .douta                   (data_out),
	  .sbiterra                (),
	  .dbiterra                ()
	);
endmodule


//set of identical memory modules, each clocked by same clk. 1 whole set like this is a single collection
module parallel_mem #(
	parameter z = 8, //no. of mems, each having depth cells, each cell has width bits
	parameter depth = 2, //No. of cells
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(	
	input clk,
	input reset,
	input [addrsize-1:0] address [z-1:0],
	input [z-1:0] we,
	input signed [width-1:0] data_in [z-1:0],
	output signed [width-1:0] data_out [z-1:0]
);

	genvar gv_i;
	generate for (gv_i=0; gv_i<z; gv_i++) begin: parallel_mem
		memory #(
			.depth(depth),
			.width(width)
		) mem (
			.clk,
			.reset,
			.address(address[gv_i]),
			.we(we[gv_i]),
			.data_in(data_in[gv_i]),
			.data_out(data_out[gv_i])
		);
	end
	endgenerate
endmodule


//set of collections. Each collection is a parallel_mem, i.e. a set of memories of identical size and clocked by same clock
module mem_collection #(
	parameter collection = 5, //no. of collections
	parameter z = 8, //no. of mems in each collection
	parameter depth = 2, //no. of cells in each mem
	parameter width = 16, //no. of bits in each cell
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input [addrsize-1:0] address [collection-1:0] [z-1:0],
	input [z-1:0] we [collection-1:0],
	input signed [width-1:0] data_in [collection-1:0] [z-1:0],
	output signed [width-1:0] data_out [collection-1:0] [z-1:0]
);
	
	genvar gv_i;
	generate for (gv_i = 0; gv_i<collection; gv_i++) begin: mem_collection
		parallel_mem #(
			.z(z), 
			.width(width), 
			.depth(depth)
		) parmem (
			.clk,
			.reset,
			.address(address[gv_i]),
			.we(we[gv_i]),
			.data_in(data_in[gv_i]),
			.data_out(data_out[gv_i])
		);
	end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

/* Simple dual port memory => Write only to port A, read only from port B
Using mode read-first and latency = 1
If ports A and B point to same address and A tries to write, then B will first read the old value on the upcoming posedge
It will read the new value written by A on the next posedge
FOR EVERY CHANGED CONFIG, THE INIT VALUES FOR WBMEMS NEED TO BE REGENERATED
*/
module simple_dual_port_memory #(
	parameter purpose = 1, //1 for jn1 wbmem (input layer), 2 for jn2 wbmem (hidden layer), ...
	//Memories for different purposes differ only in their init files
	parameter depth = 16,
	parameter width = 12,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input weA,
	input [addrsize-1:0] addressA,
	input [addrsize-1:0] addressB,
	input signed [width-1:0] data_inA,
	output signed [width-1:0] data_outB
);

	generate if (purpose==1) begin: input_wbmem_gen
	
		// xpm_memory_sdpram: Simple Dual Port RAM
		// Xilinx Parameterized Macro, Version 2017.4
		xpm_memory_sdpram # (
		
		  // Common module parameters
		  .MEMORY_SIZE             (depth*width),            //positive integer
		  .MEMORY_PRIMITIVE        ("auto"),          //string; "auto", "distributed", "block" or "ultra";
		  .CLOCKING_MODE           ("common_clock"),  //string; "common_clock", "independent_clock" 
		  .MEMORY_INIT_FILE        ("none"),          //string; "none" or "<filename>.mem" 
		  .MEMORY_INIT_PARAM       ("00F,015,003,FCC,01E,032,030,00F,044,FE5,FD3,FC9,015,FBB,FEF,FFE"),          //string;
		  .USE_MEM_INIT            (1),               //integer; 0,1
		  .WAKEUP_TIME             ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin" 
		  .MESSAGE_CONTROL         (0),               //integer; 0,1
		  .ECC_MODE                ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode" 
		  .AUTO_SLEEP_TIME         (0),               //Do not Change
		  .USE_EMBEDDED_CONSTRAINT (0),               //integer: 0,1
		  .MEMORY_OPTIMIZATION     ("true"),          //string; "true", "false" 
		
		  // Port A module parameters
		  .WRITE_DATA_WIDTH_A      (width),              //positive integer
		  .BYTE_WRITE_WIDTH_A      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
		  .ADDR_WIDTH_A            (addrsize),               //positive integer
		
		  // Port B module parameters
		  .READ_DATA_WIDTH_B       (width),              //positive integer
		  .ADDR_WIDTH_B            (addrsize),               //positive integer
		  .READ_RESET_VALUE_B      ("0"),             //string
		  .READ_LATENCY_B          (1),               //non-negative integer
		  .WRITE_MODE_B            ("read_first")      //string; "write_first", "read_first", "no_change" 
		
		) simpledualport_input_wbmem (
		
		  // Common module ports
		  .sleep                   (1'b0),
		
		  // Port A module ports
		  .clka                    (clk),
		  .ena                     (1'b1),
		  .wea                     (weA),
		  .addra                   (addressA),
		  .dina                    (data_inA),
		  .injectsbiterra          (1'b0),
		  .injectdbiterra          (1'b0),
		
		  // Port B module ports
		  .clkb                    (1'b0),
		  .rstb                    (reset),
		  .enb                     (1'b1),
		  .regceb                  (1'b1),
		  .addrb                   (addressB),
		  .doutb                   (data_outB),
		  .sbiterrb                (),
		  .dbiterrb                ()
		
		);
		
	end else if (purpose==2) begin: hidden_wbmem_gen
			
		// xpm_memory_sdpram: Simple Dual Port RAM
		// Xilinx Parameterized Macro, Version 2017.4
		xpm_memory_sdpram # (
		
		  // Common module parameters
		  .MEMORY_SIZE             (depth*width),            //positive integer
		  .MEMORY_PRIMITIVE        ("auto"),          //string; "auto", "distributed", "block" or "ultra";
		  .CLOCKING_MODE           ("common_clock"),  //string; "common_clock", "independent_clock" 
		  .MEMORY_INIT_FILE        ("none"),          //string; "none" or "<filename>.mem" 
		  .MEMORY_INIT_PARAM       ("028,02D,FD8,FF6,FF4,036,08D,027,FFF,F9B,F96,003,048,075,03A,03E"),          //string;
		  .USE_MEM_INIT            (1),               //integer; 0,1
		  .WAKEUP_TIME             ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin" 
		  .MESSAGE_CONTROL         (0),               //integer; 0,1
		  .ECC_MODE                ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode" 
		  .AUTO_SLEEP_TIME         (0),               //Do not Change
		  .USE_EMBEDDED_CONSTRAINT (0),               //integer: 0,1
		  .MEMORY_OPTIMIZATION     ("true"),          //string; "true", "false" 
		
		  // Port A module parameters
		  .WRITE_DATA_WIDTH_A      (width),              //positive integer
		  .BYTE_WRITE_WIDTH_A      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
		  .ADDR_WIDTH_A            (addrsize),               //positive integer
		
		  // Port B module parameters
		  .READ_DATA_WIDTH_B       (width),              //positive integer
		  .ADDR_WIDTH_B            (addrsize),               //positive integer
		  .READ_RESET_VALUE_B      ("0"),             //string
		  .READ_LATENCY_B          (1),               //non-negative integer
		  .WRITE_MODE_B            ("read_first")      //string; "write_first", "read_first", "no_change" 
		
		) simpledualport_hidden_wbmem (
		
		  // Common module ports
		  .sleep                   (1'b0),
		
		  // Port A module ports
		  .clka                    (clk),
		  .ena                     (1'b1),
		  .wea                     (weA),
		  .addra                   (addressA),
		  .dina                    (data_inA),
		  .injectsbiterra          (1'b0),
		  .injectdbiterra          (1'b0),
		
		  // Port B module ports
		  .clkb                    (1'b0),
		  .rstb                    (reset),
		  .enb                     (1'b1),
		  .regceb                  (1'b1),
		  .addrb                   (addressB),
		  .doutb                   (data_outB),
		  .sbiterrb                (),
		  .dbiterrb                ()
		
		);
		
	end
	endgenerate
endmodule


// Set of z simple dual port mems
module parallel_simple_dual_port_mem #(
	parameter purpose = 1,
	parameter z = 8,
	parameter depth = 16,
	parameter width = 12, 
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(	
	input clk,
	input reset,
	input [z-1:0] weA,
	input [addrsize-1:0] addressA [z-1:0],
	input [addrsize-1:0] addressB [z-1:0],
	input signed [width-1:0] data_inA [z-1:0],
	output signed [width-1:0] data_outB [z-1:0]
);

	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i++) begin: parallel_sdp_mem
		simple_dual_port_memory #(
			.purpose(purpose),
			.depth(depth),
			.width(width)
		) sdpmem (
			.clk,
			.reset,
			.addressA(addressA[gv_i]),
			.weA(weA[gv_i]),
			.data_inA(data_inA[gv_i]),
			.addressB(addressB[gv_i]),
			.data_outB(data_outB[gv_i])
		);
	end
	endgenerate
endmodule

// __________________________________________________________________________________________________________ //
// __________________________________________________________________________________________________________ //

/* True dual port memory => Both ports can read and write, but can't write together
Using mode read-first and latency = 1
Say port A is writing, then it will read from its address and then write to it. Meanwhile B will read from its own address
Vice-versa for when B is writing
Say both addresses are same and A is writing. Then both ports will have same output (old data), and then A will write new data to it
*/
module true_dual_port_memory #(
	parameter depth = 2,
	parameter width = 12,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input weA,
	input weB,
	input [addrsize-1:0] addressA,
	input [addrsize-1:0] addressB,
	input signed [width-1:0] data_inA,
	input signed [width-1:0] data_inB,
	output signed [width-1:0] data_outA,
	output signed [width-1:0] data_outB
);

	// xpm_memory_tdpram: True Dual Port RAM
	// Xilinx Parameterized Macro, Version 2017.4
	xpm_memory_tdpram # (
	
	  // Common module parameters
	  .MEMORY_SIZE             (depth*width),            //positive integer
	  .MEMORY_PRIMITIVE        ("auto"),          //string; "auto", "distributed", "block" or "ultra";
	  .CLOCKING_MODE           ("common_clock"),  //string; "common_clock", "independent_clock" 
	  .MEMORY_INIT_FILE        ("none"),          //string; "none" or "<filename>.mem" 
	  .MEMORY_INIT_PARAM       (""    ),          //string;
	  .USE_MEM_INIT            (1),               //integer; 0,1
	  .WAKEUP_TIME             ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin" 
	  .MESSAGE_CONTROL         (0),               //integer; 0,1
	  .ECC_MODE                ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode" 
	  .AUTO_SLEEP_TIME         (0),               //Do not Change
	  .USE_EMBEDDED_CONSTRAINT (0),               //integer: 0,1
	  .MEMORY_OPTIMIZATION     ("true"),          //string; "true", "false" 
	
	  // Port A module parameters
	  .WRITE_DATA_WIDTH_A      (width),              //positive integer
	  .READ_DATA_WIDTH_A       (width),              //positive integer
	  .BYTE_WRITE_WIDTH_A      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
	  .ADDR_WIDTH_A            (addrsize),               //positive integer
	  .READ_RESET_VALUE_A      ("0"),             //string
	  .READ_LATENCY_A          (1),               //non-negative integer
	  .WRITE_MODE_A            ("read_first"),     //string; "write_first", "read_first", "no_change" 
	
	  // Port B module parameters
	  .WRITE_DATA_WIDTH_B      (width),              //positive integer
	  .READ_DATA_WIDTH_B       (width),              //positive integer
	  .BYTE_WRITE_WIDTH_B      (width),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
	  .ADDR_WIDTH_B            (addrsize),               //positive integer
	  .READ_RESET_VALUE_B      ("0"),             //vector of READ_DATA_WIDTH_B bits
	  .READ_LATENCY_B          (1),               //non-negative integer
	  .WRITE_MODE_B            ("read_first")      //string; "write_first", "read_first", "no_change" 
	
	) truedualportmem_hidden_DMp (
	
	  // Common module ports
	  .sleep                   (1'b0),
	
	  // Port A module ports
	  .clka                    (clk),
	  .rsta                    (reset),
	  .ena                     (1'b1),
	  .regcea                  (1'b1),
	  .wea                     (weA),
	  .addra                   (addressA),
	  .dina                    (data_inA),
	  .injectsbiterra          (1'b0),
	  .injectdbiterra          (1'b0),
	  .douta                   (data_outA),
	  .sbiterra                (),
	  .dbiterra                (),
	
	  // Port B module ports
	  .clkb                    (1'b0),
	  .rstb                    (reset),
	  .enb                     (1'b1),
	  .regceb                  (1'b1),
	  .web                     (weB),
	  .addrb                   (addressB),
	  .dinb                    (data_inB),
	  .injectsbiterrb          (1'b0),
	  .injectdbiterrb          (1'b0),
	  .doutb                   (data_outB),
	  .sbiterrb                (),
	  .dbiterrb                ()
	
	);
endmodule


//set of identical dual port memory modules, each clocked by same clk. 1 whole set like this is a single collection
module parallel_true_dual_port_mem #(
	parameter z = 8,
	parameter depth = 16,
	parameter width = 12, 
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(	
	input clk,
	input reset,
	input [z-1:0] weA,
	input [z-1:0] weB,
	input [addrsize-1:0] addressA [z-1:0],
	input [addrsize-1:0] addressB [z-1:0],
	input signed [width-1:0] data_inA [z-1:0],
	input signed [width-1:0] data_inB [z-1:0],
	output signed [width-1:0] data_outA [z-1:0],
	output signed [width-1:0] data_outB [z-1:0]
);

	genvar gv_i;
	generate for (gv_i = 0; gv_i<z; gv_i++) begin: parallel_tdpmem
		true_dual_port_memory #(
			.depth(depth),
			.width(width)
		) tdpmem (
			.clk,
			.reset,
			.addressA(addressA[gv_i]),
			.weA(weA[gv_i]),
			.data_inA(data_inA[gv_i]),
			.data_outA(data_outA[gv_i]),
			.addressB(addressB[gv_i]),
			.weB(weB[gv_i]),
			.data_inB(data_inB[gv_i]),
			.data_outB(data_outB[gv_i])
		);
	end
	endgenerate
endmodule


//set of collections. Each collection is a dual port parallel_mem, i.e. a set of memories of identical size and clocked by same clock
module true_dual_port_mem_collection #(
	parameter collection = 5,
	parameter z = 8,
	parameter depth = 2,
	parameter width = 16,
	localparam addrsize = (depth==1) ? 1 : $clog2(depth)
)(
	input clk,
	input reset,
	input [z-1:0] weA [collection-1:0],
	input [z-1:0] weB [collection-1:0],
	input [addrsize-1:0] addressA [collection-1:0] [z-1:0],
	input [addrsize-1:0] addressB [collection-1:0] [z-1:0],
	input signed [width-1:0] data_inA [collection-1:0] [z-1:0],
	input signed [width-1:0] data_inB [collection-1:0] [z-1:0],
	output signed [width-1:0] data_outA [collection-1:0] [z-1:0],
	output signed [width-1:0] data_outB [collection-1:0] [z-1:0]
);

	genvar gv_i;	
	generate for (gv_i = 0; gv_i<collection; gv_i++) begin: tdpmem_collection
		parallel_true_dual_port_mem #(
			.z(z), 
			.width(width), 
			.depth(depth)
		) ptdp_mem (
			.clk,
			.reset,
			.addressA(addressA[gv_i]),
			.weA(weA[gv_i]),
			.data_inA(data_inA[gv_i]),
			.data_outA(data_outA[gv_i]),
			.addressB(addressB[gv_i]),
			.weB(weB[gv_i]),
			.data_inB(data_inB[gv_i]),
			.data_outB(data_outB[gv_i])
		);
	end
	endgenerate
endmodule
