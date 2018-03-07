`timescale 1ps/100fs

module board_top (
	input clk_i,
	input rstn_i,
	input btnl_i,
	input btnc_i,
	input btnr_i,
	input btnd_i,
	input btnu_i,
	input [15:0] sw_i,
	output [15:0] led_o,
	input uart_txd_in,
	output uart_rxd_out,

	output [12:0] ddr2_addr,
	output [2:0] ddr2_ba,
	output ddr2_ras_n,
	output ddr2_cas_n,
	output ddr2_we_n,
	output ddr2_ck_p,
	output ddr2_ck_n,
	output ddr2_cke,
	output ddr2_cs_n,
	output [1:0] ddr2_dm,
	output ddr2_odt,
	inout [15:0] ddr2_dq,
	inout [1:0] ddr2_dqs_p,
	inout [1:0] ddr2_dqs_n
	);

	parameter CLKFREQ = 75_000_000;
	parameter BAUDRATE = 115_200;

	wire clk_i_buf, clk_75MHz, clk_200MHz, clk_10MHz_nobuf, clk_10MHz_buf, clk_10MHz_gated;
	wire ui_clk, ui_clk_buf;
	wire rst, reset, resetn;
	wire locked;
	wire [7:0] dwOut;
	reg [7:0] dwIn = 0;
	wire rx_data_rdy;
	wire group_ready;
	wire [127:0] group_data_out;
	// wire read_cycle_begin;

	reg [12:0] output_count;
	reg [9:0] output_store [0:199];
	reg [7:0] store_count;

	wire wr_done_o, wdf_ack;
	wire [127:0] mem_rd_data_o;
	wire mem_rd_data_valid_o, rd_done_o, init_calib_complete;

	wire [127:0] dnn_input;
	wire cycle_clk;
	wire [6:0] cycle_index;
	wire cycle_zero;
	wire ansL;
	wire [63:0] actL_alln;

	wire clk_10MHz_gate_en;
	wire fifo_empty;
	wire fifo_rd;
	wire [6:0] wr_data_count;
	wire [127:0] fifo_out;

	reg [2:0] dnn_rst_count;
	reg dnn_begin;
	wire dnn_rst;
	wire dnn_stop;

	assign led_o[15] = init_calib_complete;
	assign led_o[14] = wr_done_o;
	assign led_o[13] = dnn_stop;
	assign led_o[9:0] = output_store[sw_i[7:0]];

	assign rst = ~rstn_i;
	assign reset = ~locked || rst;
	assign resetn = locked && ~rst;

	// assign read_cycle_begin = (cycle_index == 2);
	assign cycle_zero = (cycle_index<2) || (cycle_index>50);
	assign dnn_rst = dnn_rst_count[2];
	assign clk_10MHz_gate_en = (dnn_rst_count[2] || dnn_begin) && !dnn_stop;
	assign fifo_rd = ~cycle_zero;
	assign dnn_input = cycle_zero? 0 : fifo_out;
	assign dnn_stop = (output_count > 198);

	always @(posedge clk_10MHz_buf or negedge resetn)
	if (!resetn)
	begin
		dnn_rst_count <= 3'b100;
		dnn_begin <= 0;
	end
	else if (init_calib_complete)
	begin
		if (dnn_rst_count != 0)
			dnn_rst_count <= dnn_rst_count + 1;
		if (wr_data_count == 49)
			dnn_begin <= 1;
	end

	always @(posedge clk_10MHz_gated)
	if (dnn_rst)
	begin
		output_count <= 0;
		store_count <= 0;
	end
	else if (cycle_clk)
	begin
		output_count <= output_count + 1;
		if (output_count < 100 || (output_count>99 && output_count<200))
		begin
			store_count <= store_count + 1;
			output_store[store_count] <= actL_alln[9:0];
		end
	end

	IBUFG ibufg_clk_i
		( 
			.I		(clk_i), 
			.O		(clk_i_buf) 
		);

	clk_wiz clk_wiz
		(
	  		.clk_out1(clk_200MHz),
	  		.clk_out2(clk_75MHz),
	  		.clk_out3(clk_10MHz_nobuf),
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

	BUFG bufg_ui_clk 
		( 
			.I		(ui_clk), 
			.O		(ui_clk_buf) 
		);

	IOExpansion #(
		.BAUD_RATE(BAUDRATE),
		.CLOCK_RATE_RX(CLKFREQ),
		.CLOCK_RATE_TX(CLKFREQ)
	) inst_IOExpansion 
		(
			.clk     	 	(clk_75MHz),
			.rst     	 	(reset),
			.rxd_pin     	(uart_txd_in),
			.txd_pin     	(uart_rxd_out),
			.dwOut       	(dwOut),
			.dwIn        	(dwIn),
			.rx_data_rdy 	(rx_data_rdy)
		);

	grouper inst_grouper
		(
			.clk      		(clk_75MHz),
			.rst      		(reset),
			.data_in  		(dwOut),
			.w_en     		(rx_data_rdy),
			.ready    		(group_ready),
			.data_out 		(group_data_out)
		);

	mig_top #(
  			.MAX_NUM			 (9800)
  	) inst_mig_top
		(
			.ddr2_dq             (ddr2_dq),
			.ddr2_dqs_n          (ddr2_dqs_n),
			.ddr2_dqs_p          (ddr2_dqs_p),
			.ddr2_addr           (ddr2_addr),
			.ddr2_ba             (ddr2_ba),
			.ddr2_ras_n          (ddr2_ras_n),
			.ddr2_cas_n          (ddr2_cas_n),
			.ddr2_we_n           (ddr2_we_n),
			.ddr2_ck_p           (ddr2_ck_p),
			.ddr2_ck_n           (ddr2_ck_n),
			.ddr2_cke            (ddr2_cke),
			.ddr2_cs_n           (ddr2_cs_n),
			.ddr2_dm             (ddr2_dm),
			.ddr2_odt            (ddr2_odt),

			.sys_clk_i           (clk_200MHz),
			.sys_rst_n           (resetn),

			.init_calib_complete (init_calib_complete),
			// .device_temp_i       (12'b0),		// XADC instantiated inside MIG
			.ui_clk              (ui_clk),
			.ui_rst              (ui_rst),
			.rst_ctrl			 (sw_i[13]),
			.cs_i                (1'b0),
			.mem_addr_i          (/*{14'b0, sw_i[9:0]}*/24'b0),
			.mem_cmd_i           (2'b01),
			.mem_wdf_data_i      (group_data_out),
			// .cycle_num           ({10'b0, sw_i[13:0]}),
			.read_cycle_begin	 (fifo_empty),
			.mem_wen_strike_i    (group_ready),
			.mem_ren_strike_i    (sw_i[15]),
			// .rd_pause_i          (rd_pause_i),
			.wdf_ack             (wdf_ack),
			.mem_rd_data_o       (mem_rd_data_o),
			.mem_rd_data_valid_o (mem_rd_data_valid_o),
			.rd_done_o           (rd_done_o),
			.wr_done_o           (wr_done_o)
		);

	fifo_128b_49d fifo_ins
	(
	    .rst 			(ui_rst),
	    .wr_clk			(ui_clk_buf), 		
	    .rd_clk			(clk_10MHz_buf), 	
	    .din			(mem_rd_data_o), 
	    .wr_en			(mem_rd_data_valid_o), 	
	    .rd_en			(fifo_rd), 	
	    .dout			(fifo_out), 
	    .full			(), 
	    .empty			(fifo_empty), 
	    .wr_data_count	(wr_data_count),
	    .wr_rst_busy 	(),
	    .rd_rst_busy 	()
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