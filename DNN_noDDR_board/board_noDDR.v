`timescale 1ps/100fs

module board_top_noDDR (
	input clk_i,
	input rstn_i,
	input btnl_i,
	input btnc_i,
	input btnr_i,
	input btnd_i,
	input btnu_i,
	input [15:0] sw_i,
	output reg [15:0] led_o,
	input uart_txd_in,
	output uart_rxd_out
	);

	parameter CLKFREQ = 100_000_000;
	parameter BAUDRATE = 115_200;

	wire clk_i_buf, clk_10MHz_nobuf, clk_10MHz_buf, clk_10MHz_gated, clk_100MHz_buf;
	wire rst, reset, resetn;
	wire locked;
	wire [7:0] dwOut;
	reg [7:0] dwIn = 0;
	wire rx_data_rdy;
	wire group_ready;
	reg group_ready_reg0_10, group_ready_reg1_10;
	wire group_ready_pulse;
	wire [127:0] group_data_out;

	reg [15:0] output_count;
	reg [9:0] output_store [0:255];
	reg [7:0] store_count;
	reg [6:0] cycle_index_reg [0:199];
	reg [7:0] index_count;
	reg [9:0] changed_output [0:199];
	reg [9:0] output_reg_last;

	wire [127:0] dnn_input;
	wire cycle_clk;
	wire [6:0] cycle_index;
	wire cycle_zero;
	wire ansL;
	wire [63:0] actL_alln;

	wire clk_10MHz_gate_en;

	reg [2:0] dnn_rst_count;
	wire dnn_rst;
	wire dnn_stop;
	integer i;

	assign rst = ~rstn_i;
	assign reset = ~locked || rst;
	assign resetn = locked && ~rst;

	// assign read_cycle_begin = (cycle_index == 2);
	assign cycle_zero = (cycle_index<2) || (cycle_index>50);
	assign dnn_rst = dnn_rst_count[2];
	assign clk_10MHz_gate_en = dnn_rst_count[2] || cycle_zero || group_ready_pulse;
	assign dnn_input = cycle_zero? 0 : group_data_out;
	assign group_ready_pulse = group_ready_reg0_10 && ~group_ready_reg1_10;

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
 
	always @(posedge clk_10MHz_buf or negedge resetn)
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

	always @(posedge clk_10MHz_gated)
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
		if (cycle_clk)
		begin
			output_reg_last <= actL_alln[9:0];
			output_count <= output_count + 1;
			// if (output_count < 100 || (output_count>99 && output_count<200))
			if (output_count > 12343)
			begin
				store_count <= store_count + 1;
				output_store[store_count] <= actL_alln[9:0];
			end
		end
		if (actL_alln != 64'b1 && actL_alln != 0)
		begin
			if (index_count < 200)
			begin
				index_count <= index_count + 1;
				cycle_index_reg[index_count] <= cycle_index;
				changed_output[index_count] <= actL_alln[9:0];
			end
		end
	end

	IBUFG ibufg_clk_i
		( 
			.I		(clk_i), 
			.O		(clk_i_buf) 
		);

	clk_wiz_10 clk_wiz_10
		(
			.clk_out1(clk_100MHz_buf),
	  		.clk_out2(clk_10MHz_nobuf),
	  		.reset(rst),
	  		.locked(locked),			// indicating clk generation is done and clks are steady now
	  		.clk_in1(clk_i_buf)
	 	);

	BUFG bufg_clk_10 
		( 
			.I		(clk_10MHz_nobuf), 
			.O		(clk_10MHz_buf) 
		);

	BUFGCE bufgce_clk_10_gated 
		(      
			.I		(clk_10MHz_nobuf),
			.CE		(clk_10MHz_gate_en),
			.O		(clk_10MHz_gated)    
		);

	IOExpansion #(
		.BAUD_RATE(BAUDRATE),
		.CLOCK_RATE_RX(CLKFREQ),
		.CLOCK_RATE_TX(CLKFREQ)
	) inst_IOExpansion 
		(
			.clk     	 	(clk_100MHz_buf),
			.rst     	 	(dnn_rst),
			.rxd_pin     	(uart_txd_in),
			.txd_pin     	(uart_rxd_out),
			.dwOut       	(dwOut),
			.dwIn        	(dwIn),
			.rx_data_rdy 	(rx_data_rdy)
		);

	grouper inst_grouper
		(
			.clk      		(clk_100MHz_buf),
			.rst      		(dnn_rst),
			.data_in  		(dwOut),
			.w_en     		(rx_data_rdy),
			.ready    		(group_ready),
			.data_out 		(group_data_out)
		);

	DNN_top inst_DNN_top 
		(
			.clk       		(clk_10MHz_gated),
			.reset     		(dnn_rst),
			.act0      		(dnn_input),
			.ansL      		(ansL),
			.actL_alln 		(actL_alln),
			.cycle_clk		(cycle_clk),
			.cycle_index	(cycle_index)
		);

endmodule