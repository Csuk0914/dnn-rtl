// Diandian Chen, April 2018
//
// This is top level module of board design. Names corresponding to physical pins on board should be declared here as
// I/O ports of this top module. What happens in this module is: "IOExpansion" module (UART) receives bytes sent from PC
// via uart_txd_in serial transmission pin and give them to "grouper" module. Based on how many bits are needed as input
// to DNN (256 bits for current configuration), "grouper" groups bytes from "IOExpansoin" into 256 bits and enables gated
// clock into DNN. DNN keeps running under this gated clock and its outputs are stored in specific registers. Contents
// in these registers are routed to LED output pins and DNN's function is verified by observing its outputs on LEDs.

`timescale 1ps/100fs

module board_top_noDDR (			// Pin name should be consistent to whatever declared in .xdc physical constraint file
	input clk_i,					// System clock from clock pin on board
	input rstn_i,					// Reset_negative pin
	input btnl_i,					// Button L (left), not used in the design
	input btnc_i,					// Button C (central), not used in the design
	input btnr_i,					// Button R (right), not used in the design
	input btnd_i,					// Button D (down), not used in the design
	input btnu_i,					// Button U (up), not used in the design
	input [15:0] sw_i,				// 16 switches below LEDs
	output reg [15:0] led_o,		// 16 LED outputs. high to glow
	input uart_txd_in,				// UART input pin, input from PC
	output uart_rxd_out				// UART output pin, output to PC, not really used
	);

	parameter CLKFREQ = 100_000_000;	// Clock frequency parameter for UART rx and tx. Needed for oversampling
	parameter BAUDRATE = 115_200;		// Baud rate of UART. Needs to be the same as set in PC UART transmission app

	// -----------------------  Configuration parameters for DNN  -----------------------------------------------
	parameter width_in = 8;
	parameter width = 10;
	parameter int_bits = 2;
	parameter L = 3;
	parameter [31:0] actfn [0:L-2] = '{0,0}; //Activation function for all junctions. 0 = sigmoid, 1 = relu
	parameter costfn = 1; //Cost function for output layer. 0 = quadcost, 1 = xentcost
	//parameter Eta = 2.0**(-4), //Should be a power of 2. Value between 2^(-frac_bits) and 1. DO NOT WRITE THIS AS 2**x, it doesn't work without 2.0
	localparam frac_bits = width-int_bits-1;

	parameter [31:0] n [0:L-1] = '{1024, 64, 32}; //No. of neurons in every layer
	parameter [31:0] fo [0:L-2] = '{4, 16}; //Fanout of all layers except for output
	parameter [31:0] fi [0:L-2] = '{64, 32}; //Fanin of all layers except for input
	parameter [31:0] z [0:L-2] = '{128, 32}; //Degree of parallelism of all junctions. No. of junctions = L-1
	// ----------------------------------------------------------------------------------------------------------

	wire clk_i_buf, clk_15MHz_nobuf, clk_15MHz_buf, clk_15MHz_gated, clk_100MHz_buf;	// All clock signals
	// Signals with "_buf" and "_gated" suffix are signals coming out of a clock buffer. We have 3 versions for 15MHz clock because we need one gated
	// version as input clock to DNN, and we need another free running version clk_15MHz_buf for some logic outside DNN. They are both derived from
	// the nobuf version so they have same relative delay to clk_15MHz_nobuf. Here 15MHz domain is for DNN related logic and 100MHz domain is for other
	// board logic including UART and grouper.

	wire rst, reset, resetn;							// rst is inverted version of reset_negative pin. The other two are controled by "locked" signal of Clock Wizard
	wire locked;										// Valid when generated clocks from Clock Wizard are steady and usable
	wire [7:0] dwOut;									// Collected byte offered by UART rx module
	reg [7:0] dwIn = 0;									// Input for UART tx, not really used
	wire rx_data_rdy;									// Indicates collected byte from UART rx is available
	wire group_ready;									// Indicates collected 256 bits from grouper is available
	reg group_ready_reg0_10, group_ready_reg1_10;		// Used for double synchronization for CDC from grouper domain (100MHz) to DNN domain (15MHz)
	wire group_ready_pulse;								// group_ready signal after CDC (100MHz domain to 15MHz). Enables the gated clock
	wire [255:0] group_data_out;						// Collected 256 bits from grouper

	reg [15:0] output_count;				// Counts output cycles of DNN
	reg [9:0] output_store [0:255];			// Stores outputs from DNN (e.g. stores the last 200 outputs)
	reg [7:0] store_count;					// Index for output_store
	reg [9:0] output_reg_last;				// Record of the last outputs of DNN
	reg [7:0] index_count;					// Was used to debug as index into registers below
	reg [6:0] cycle_index_reg [0:199];		// Was used to debug by observing cycle index when output changes
	reg [9:0] changed_output [0:199];		// Was used to debug by capturing changed outputs

	wire [255:0] dnn_input;					// 256-bit data input to DNN
	wire cycle_clk;							// cycle_clk from DNN, can be used to monitor outputs of DNN
	wire [6:0] cycle_index;					// cycle_index from DNN, indicating current progress of inputing one image into DNN
	wire cycle_zero;						// High to indicate that input into DNN now should be filled as 0
	wire ansL;								// ansL from DNN
	wire [31:0] actL_alln;					// actL_alln from DNN

	wire clk_15MHz_gate_en;					// Enable signal for 15MHz clock gating

	reg [2:0] dnn_rst_count;				// DNN is implemented as synchronous reset. Used to feed DNN the reset input while several gated clocks are also enabled
	wire dnn_rst;							// Reset signal into DNN
	integer i;								// Used for looping reset for arrays

	assign rst = ~rstn_i;					// Inverted version of input reset_negative pin
	assign reset = ~locked || rst;			// reset_positive signal controlled by "locked" as well
	assign resetn = locked && ~rst;			// reset_negative signal controlled by "locked" as well

	assign cycle_zero = (cycle_index<2) || (cycle_index>26);							// DNN is designed in this way that because there're so many neurons in input
																						// layer, our images are only big enough to feed part of these neurons (784 
																						// pixels * 8 bit/pixel), and other neurons are simply fed with 0. For current
																						// configuration, the first two cycles are always fed with 0, and cycles after
																						// 26 are corresponding to excessive input neurons thus fed with 0 as well

	assign dnn_rst = dnn_rst_count[2];													// After reset cycles are applied, reset counter will count to 0 and dnn_rst goes invalid
	assign clk_15MHz_gate_en = dnn_rst_count[2] || cycle_zero || group_ready_pulse;		// Whenever reset cycles OR feeding with 0 for sure OR 256-bit data is ready, enable DNN clock
	assign dnn_input = cycle_zero? 0 : group_data_out;									// Only when needed neurons are being fed, provide DNN with received data
	assign group_ready_pulse = group_ready_reg0_10 && ~group_ready_reg1_10;				// Pulse signal derived from double-synchronization to enable gated clock into DNN



	// ----------------------------------------------------- LED display control --------------------------------------------------------------
	// Use switches to control what is shown by LEDs. Only switch 15 and 11 are mainly used for swtiching display mode in final implementation.
	// All switches OFF: display the last outputs from DNN
	// Switch 15: how many outputs have been generated
	// Switch 14: what is the index count (debug purpose which, not used any more)
	// Switch 13: what is the cycle index when output changes (debug purpose which, not used any more)
	// Switch 12: what are the stored changed outputs after reset (debug purpose which, not used any more)
	// Switch 11: check stored last 200 outputs using switches 7 to 0 as index
	// Switch 10: how many outputs of the last 200 have been recorded
	always @(*)
	begin
		if (sw_i[15])
			led_o[15:0] = output_count;
		else if (sw_i[14])
			led_o[15:0] = {8'b0, index_count};
		else if (sw_i[13])
			led_o[15:0] = {9'b0, cycle_index_reg[sw_i[7:0]]};
		else if (sw_i[12])
			led_o[15:0] = {6'b0, changed_output[sw_i[7:0]]};
		else if (sw_i[11])
			led_o[15:0] = {6'b0, output_store[sw_i[7:0]]};
		else if (sw_i[10])
			led_o[15:0] = {8'b0, store_count};
		else
			led_o[15:0] = {6'b0, output_reg_last};
	end
	// ----------------------------------------------------- LED display control --------------------------------------------------------------
 


 	// ------------------------------------------- CDC for group_ready & dnn_rst generation --------------------------------------------------
 	// group_ready is originally generated by grouper in 100MHz domain, and needs to be synchronized to DNN's 15MHz domain.
 	// It's ok to simply do the double synchronization and directly use the synchronized signal to enable DNN clock. Because UART is so slow
 	// and each collected 256-bit set can stay unchanged for so long and we can expect the 256 bits to be stable and usable even after 2 15MHz
 	// cycles used for double synchronization.
 	// Raw 15MHz clock is generated by Clock Wizard and can only be used after "locked" signal is given. Because DNN is designed to do synchronous
 	// reset, after usable raw 15MHz clock is obtained, we need to have some gated clocks for DNN to do reset, and dnn_rst_count is to give DNN
 	// this reset signal along with clocks by counting down after "locked" and enable DNN clock & give reset signal with dnn_rst_count's MSB.
	always @(posedge clk_15MHz_buf or negedge resetn)
	if (!resetn)
	begin
		dnn_rst_count <= 3'b100;
		group_ready_reg0_10 <= 0;
		group_ready_reg1_10 <= 0;
	end
	else if (locked)
	begin
		if (dnn_rst_count != 0)
			dnn_rst_count <= dnn_rst_count + 1;
		group_ready_reg0_10 <= group_ready;
		group_ready_reg1_10 <= group_ready_reg0_10;
	end
	// ------------------------------------------- CDC for group_ready & dnn_rst generation --------------------------------------------------



	// ---------------------------------------------- DNN outputs capturing and recording ----------------------------------------------------
	always @(posedge clk_15MHz_gated)
	if (dnn_rst)
	begin
		output_count <= 0;
		store_count <= 0;
		index_count <= 0;
		output_reg_last <= 0;
		for (i=0; i<200; i=i+1)
		begin
			output_store[i] <= 0;
			cycle_index_reg[i] <= 0;
			changed_output[i] <= 0;
		end
	end
	else 
	begin
		// When cycle_clk is given by DNN, DNN output is valid and we can store is somewhere
		if (cycle_clk)
		begin
			output_reg_last <= actL_alln[9:0];		// Store the last output from DNN
			output_count <= output_count + 1;		// Increment output counter
			if (output_count > 12343)				// In current test case, there're 12544 images in total. So after 12343 are the last 200 images
			begin
				store_count <= store_count + 1;
				output_store[store_count] <= actL_alln[9:0];	// Store the last 200 outputs into output_store
			end
		end

		// Meant to debug by monitor related information right after transmission begins. Not used any more.
		if (actL_alln != 32'b1 && actL_alln != 0)	// Invalid output is always 0 and outputs in the first several output cycles are 1
		begin
			if (index_count < 200)
			begin
				index_count <= index_count + 1;
				cycle_index_reg[index_count] <= cycle_index;
				changed_output[index_count] <= actL_alln[9:0];
			end
		end
	end
	// ---------------------------------------------- DNN outputs capturing and recording ----------------------------------------------------


	// Input buffer for clk pin
	IBUFG ibufg_clk_i
		( 
			.I		(clk_i), 		// Input clock pin
			.O		(clk_i_buf) 	// Buffered output clock
		);

	// We use Clock Wizard to generate clocks with specified frequency and phase derived from input clock
	clk_wiz_15 clk_wiz_15
		(
			.clk_out1(clk_100MHz_buf),		// Buffered 100MHz output clock
	  		.clk_out2(clk_15MHz_nobuf),		// Unbuffered 15MHz output clock that will go into an always-enabled buffer and a gating buffer
	  		.reset(rst),
	  		.locked(locked),				// Indicating clk generation is done and clks are steady now
	  		.clk_in1(clk_i_buf)				// Source clock
	 	);

	// Always-enabled clock buffer that outputs a free running 15MHz clock for some control logic 
	BUFG bufg_clk_10 
		( 
			.I		(clk_15MHz_nobuf), 		// Unbuffered input 15MHz clock
			.O		(clk_15MHz_buf) 		// Buffered output clock. Synthesizer will take care of properly putting outputs from clock buffers into clock trees
		);

	// Clock buffer with a enable line. Details in slides.
	BUFGCE bufgce_clk_10_gated 
		(      
			.I		(clk_15MHz_nobuf),		// Unbuffered input clock
			.CE		(clk_15MHz_gate_en),	// Enable signal
			.O		(clk_15MHz_gated)    	// Gated output clock
		);

	// UART module. Originally coded by EE560 TA Fangzhou Wang. Modified by Diandian Chen. Integrated with some modules provided by Xilinx.
	IOExpansion #(
		.BAUD_RATE(BAUDRATE),			// Baud rate set here must be consistent with what is set on PC app.
		.CLOCK_RATE_RX(CLKFREQ),		// RX clock frequency. Used to generate oversampling signal inside.
		.CLOCK_RATE_TX(CLKFREQ)
	) inst_IOExpansion 
		(
			.clk     	 	(clk_100MHz_buf),	// Buffered 100MHz clock input
			.rst     	 	(rst),			
			.rxd_pin     	(uart_txd_in),		// UART input pin
			.txd_pin     	(uart_rxd_out),		// UART output pin
			.dwOut       	(dwOut),			// 8-bit data got from PC in one transmission
			.dwIn        	(dwIn),				// Data to be transmitted to PC. Not fully implemented and used
			.rx_data_rdy 	(rx_data_rdy)		// Valid indication for the 8-bit data got from PC
		);

	// As DNN needs 256-bit input data each DNN clock, this grouper collects bytes from UART and offer them to DNN once 256 bits are ready
	grouper_256 inst_grouper
		(
			.clk      		(clk_100MHz_buf),	// Input buffered 100MHz clock
			.rst      		(rst),				
			.data_in  		(dwOut),			// Collects data from UART RX
			.w_en     		(rx_data_rdy),		// Write enable wired to valid signal from UART
			.ready    		(group_ready),		// Once new 256 bits have been collected, output this ready signal for gating logic
			.data_out 		(group_data_out)	// 256-bit output data
		);

	// Top module of DNN
	DNN_top #(
			.width_in(width_in),
			.width(width), 
			.int_bits(int_bits),
			.L(L), 
			.actfn(actfn),
			.costfn(costfn),
			.n(n),
			.fo(fo), 
			.fi(fi), 
			.z(z)
	) DNN_top (
			.clk       		(clk_15MHz_gated),	// Input clock is gated. Needs to wait for steady output from Clock Wizard and wait for available data from grouper
			.reset     		(dnn_rst),
			.act0      		(dnn_input),
			.etapos0		(4), 
			.ansL      		(ansL),
			.actL_alln 		(actL_alln),
			.cycle_clk		(cycle_clk),
			.cycle_index	(cycle_index)
		);

endmodule