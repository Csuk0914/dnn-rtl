`timescale 1ns/100ps

`define CLOCKPERIOD 10
`define INITMEMSIZE 64 //number of elements in gaussian_list

`define MNIST //Dataset
`define NIN 784 //Number of inputs AS IN DATASET
`define NOUT 10 //Number of outputs AS IN DATASET
`define TC 12544 //Training cases to be considered in 1 epoch
`define TTC 10*`TC //Total training cases over all epochs
`define CHECKLAST 1000 //How many last inputs to check for accuracy

module DNN_top #(
	parameter width = 10,
	parameter width_in = 8,
	parameter int_bits = 2,
	parameter frac_bits = width-int_bits-1,
	parameter L = 3
)(
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

	parameter [31:0] fo [0:L-2] = '{8, 4};//Fanout of all layers except for output
	parameter [31:0] fi [0:L-2]  = '{128, 4}; //Fanin of all layers except for input
	parameter [31:0] z [0:L-2]  = '{128, 4}; //Degree of parallelism of all junctions. No. of junctions = L-1
	parameter [31:0] n [0:L-1] = '{1024, 64, 64}; //No. of neurons in every layer

	localparam cpc =  n[0] * fo[0] / z[0] + 2;
	
	wire [`NOUT-1:0] ans_mem;//ideal output

	wire [width_in*z[0]/fo[0]-1:0] act0; //No. of input activations coming into input layer per clock, each having width_in bits
	wire [z[L-2]/fi[L-2]-1:0] ans0; //No. of ideal outputs coming into input layer per clock
	wire [z[L-2]/fi[L-2]-1:0] ansL; //ideal output (ans0 after going through all layers)
	wire [n[L-1]-1:0] actL_alln; //Actual output [Eg: 4/4=1 output neuron processed per clock] of ALL output neurons

	parameter CLKFREQ = 100_000_000;
	parameter BAUDRATE = 115_200;

	wire rst, resetn, rst_syn_10m;
	wire clk10mhz, clk_100MHz_buf, clk_200MHz_buf;
	wire locked;
	wire [7:0] dwOut;
	reg [7:0] dwIn = 0;
	wire rx_data_rdy;

	assign rst = ~rstn_i;
	assign resetn = ~(rst || (!locked));

	wire [127:0] mem_rd_data_o;
	wire mem_rd_data_valid_o;
	wire calib_complete_o;
	wire ui_clk_o;
	wire [23:0] mem_addr_r;
	wire [127:0] mem_wdf_data_r;
	wire [2:0] mem_cmd;
	wire mem_en;
	wire mem_wdf_end;
	wire mem_wdf_wren;
	wire mem_rd_data_end;
	wire mem_rdy;
	wire mem_wdf_rdy;
	wire mem_ui_rst;
	wire [11:0] fpgaTempValue;
	reg cmd_stop_i;

	wire group_ready;
	wire [127:0] group_data_out;

	wire ddr_fifo_empty;
	wire [3:0] ddr_fifo_count;
	wire ddr_fifo_need_data;

	//input process logic signal
	reg [$clog2(`TC)-1:0] sel_tc = 0; //MUX select to choose training case each block cycle
	wire [$clog2(cpc-2)-1:0] sel_network; //MUX select to choose which input/output pair to feed to network within a block cycle
	wire [n[L-1]-1:0] ans0_tc; //Complete 1b ideal output for 1 training case, i.e. No. of output neurons x 1 x 1
	wire [width_in*n[0]-1:0] act0_tc; //Complete 8b act input for 1 training case, i.e. No. of input neurons x 8 x 1


	assign ddr_fifo_need_data = (ddr_fifo_count < 8) && sw_i[14];

	clk_wiz clk_wiz(

  		.clk_out1(clk10mhz),
  		.clk_out2(clk_200MHz_buf),
  		.clk_out3(clk_100MHz_buf),
  		.reset(rst),
  		.locked(locked),
  		.clk_in1(clk_i)
 	);

	ddr dut
		(
			.ddr2_dq             	(ddr2_dq),
			.ddr2_dqs_p          	(ddr2_dqs_p),
			.ddr2_dqs_n          	(ddr2_dqs_n),
			.ddr2_addr           	(ddr2_addr),
			.ddr2_ba             	(ddr2_ba),
			.ddr2_ras_n          	(ddr2_ras_n),
			.ddr2_cas_n          	(ddr2_cas_n),
			.ddr2_we_n           	(ddr2_we_n),
			.ddr2_ck_p           	(ddr2_ck_p),
			.ddr2_ck_n           	(ddr2_ck_n),
			.ddr2_cke            	(ddr2_cke),
			.ddr2_cs_n           	(ddr2_cs_n),
			.ddr2_dm             	(ddr2_dm),
			.ddr2_odt            	(ddr2_odt),
			.sys_clk_i           	(clk_200MHz_buf),
			.sys_rst             	(resetn),
			.app_addr            	({mem_addr_r, 3'b0}),
			.app_cmd             	(mem_cmd),
			.app_en              	(mem_en),
			.app_wdf_data        	(mem_wdf_data_r),
			.app_wdf_end         	(mem_wdf_end),
			.app_wdf_mask        	(16'b0),
			.app_wdf_wren        	(mem_wdf_wren),
			.app_rd_data         	(mem_rd_data_o),		//read data from DRAM
			.app_rd_data_end     	(mem_rd_data_end),
			.app_rd_data_valid   	(mem_rd_data_valid_o),	//write enable
			.app_rdy             	(mem_rdy),
			.app_wdf_rdy         	(mem_wdf_rdy),
			.app_sr_req          	(1'b0),
			.app_sr_active       	(),
			.app_ref_req         	(1'b0),
			.app_ref_ack         	(),
			.app_zq_req          	(1'b0),
			.app_zq_ack          	(),
			.ui_clk              	(ui_clk_o),				//user clk
			.ui_clk_sync_rst     	(mem_ui_rst),
			.device_temp_i       	(fpgaTempValue),
			.init_calib_complete 	(calib_complete_o) 		// only after calibration is done can we do R/W with ddr
		);

	ddr_ctrl ddr_ctrl
		(
			.clk_100MHz_i   (clk_100MHz_buf),
			.rst            (rst),
			.btnl_i         (btnl_i),
			.w_en			(group_ready),
			.r_en 			(ddr_fifo_need_data),
			.cmd_stop_i     (cmd_stop_i),
			.cycle_num      (),
			.mem_addr_i     ({20'b0, sw_i[3:0]}),
			.mem_cmd_i      (sw_i[13:12]),
			.mem_wdf_data_i (group_data_out),
			// .mem_wdf_mask_i (mem_wdf_mask_i),
			.ui_clk_i       (ui_clk_o),
			.mem_rdy        (mem_rdy),
			.mem_wdf_rdy    (mem_wdf_rdy),
			.mem_addr_r     (mem_addr_r),
			.mem_wdf_data_r (mem_wdf_data_r),
			.mem_cmd        (mem_cmd),
			.mem_en         (mem_en),
			.mem_wdf_end    (mem_wdf_end),
			.mem_wdf_wren   (mem_wdf_wren)
		);

	FPGAMonitor moni
		(
			.CLK_I          (clk_100MHz_buf),
			.RST_I          (rst),
			.TEMP_O         (fpgaTempValue)
		);

	IOExpansion #(
		.BAUD_RATE(BAUDRATE),
		.CLOCK_RATE_RX(CLKFREQ),
		.CLOCK_RATE_TX(CLKFREQ)
	) inst_IOExpansion 
		(
			.clk     	 	(clk_100MHz_buf),
			.rst     	 	(rst),
			.rxd_pin     	(uart_txd_in),
			.txd_pin     	(uart_rxd_out),
			.dwOut       	(dwOut),
			.dwIn        	(dwIn),
			.rx_data_rdy 	(rx_data_rdy)
		);

	grouper inst_grouper
		(
			.clk      		(clk_100MHz_buf),
			.rst      		(rst),
			.data_in  		(dwOut),
			.w_en     		(rx_data_rdy),
			.ready    		(group_ready),
			.data_out 		(group_data_out)
		);


	reg [127:0] read_reg;

	assign led_o[15] = calib_complete_o;
	assign led_o[14] = (ddr_fifo_count < 4);
	assign led_o[13] = (ddr_fifo_count > 10);
	assign led_o[9:0] = actL_alln[9:0];

	always @(posedge ui_clk_o)
	if (!resetn)
	begin
		read_reg <= 0;
		cmd_stop_i <= 0;
	end
	else
	begin
		if (mem_rd_data_valid_o)
			read_reg <= mem_rd_data_o;
		// if (mem_addr_r == sw_i[11:8])
		// 	cmd_stop_i <= 1;
		// if (sw_i[7])
		// 	cmd_stop_i <= 0;
	end

	////////////////////////////////////////////////////////////////////////////////////
	// Instantiate DNN and ideal output memory
	////////////////////////////////////////////////////////////////////////////////////
	rst_gen rst_gen_top (
	.clk_i		(clk10mhz),			// Receive clock
	.rst_i		(~sw_i[15]),			// Asynchronous input - from IBUF
	.rst_o		(rst_syn_10m)			// Reset, synchronized to clk_rx
	);

	DNN #(
		.width(width), 
		.width_in(width_in),
		.int_bits(int_bits),
		.frac_bits(frac_bits),
		.L(L), 
		.fo(fo), 
		.fi(fi), 
		.z(z), 
		.n(n)
		//.eta(eta), 
		//.lamda(lamda),
	) DNN (
		.act0(act0),
		.ans0(ans0), 
		.etapos0(2), 
		.clk(clk10mhz),
		.reset(rst_syn_10m),
		.ansL(ansL),
		.actL_alln(actL_alln)
	);

 	ddr_read_fifo ddr_read_fifo(
    	.rst(rst),
    	.wr_clk(ui_clk_o),
    	.rd_clk(clk10mhz),
    	.din(mem_rd_data_o),
    	.wr_en(mem_rd_data_valid_o),
    	.rd_en(~rst_syn_10m),
    	.dout(act0),
    	.full(),
    	.empty(ddr_fifo_empty),
    	.wr_data_count(ddr_fifo_count)
  	);

	ideal_out_mem ideal_out_mem(
		.clka(clk10mhz),
		.wea(1'b0),
		.addra(sel_tc),
		.dina(),
		.douta(ans_mem)
	);

	////////////////////////////////////////////////////////////////////////////////////
	// Generate Cycle Clock for input layer
	////////////////////////////////////////////////////////////////////////////////////
	
	wire cycle_clk;
	wire [$clog2(cpc)-1:0] cycle_index;
	cycle_block_counter #(
		.cpc(cpc)
	) cycle_counter (
		.clk(clk10mhz),
		.reset(rst_syn_10m),
		.cycle_clk(cycle_clk),
		.count(cycle_index)
	);

	////////////////////////////////////////////////////////////////////////////////////
	// Training cases Pre-Processing
	////////////////////////////////////////////////////////////////////////////////////
	
	assign sel_network = cycle_index[$clog2(cpc-2)-1:0]-2;
	/* cycle_index goes from 0-17, so its 4 LSB go from 0 to cpc-3 then 0 to 1
	* But nothing happens in the last 2 cycles since pipeline delay is 2
	* So take values of cycle_index from 0-15 and subtract 2 to make its 4 LSB go from 14-15, then 0-13
	* Note that the jumbled order isn't important as long as all inputs from 0-15 are fed */
	always @(posedge cycle_clk) begin
		if(!rst_syn_10m) begin
			sel_tc <= (sel_tc == `TC-1)? 0 : sel_tc + 1;
		end
		else begin
			sel_tc <= 0;
		end
	end
	
	////////////////////////////////////////////////////////////////////////////////////
	// ideal out input logic
	////////////////////////////////////////////////////////////////////////////////////

	mux #( //Choose the required no. of ideal outputs for feeding to DNN
		.width(z[L-2]/fi[L-2]), 
		.N(n[L-1]*fi[L-2]/z[L-2]) //This is basically cpc-2 of the last junction
	) mux_idealoutput_feednetwork (
		ans0_tc, sel_network, ans0);

	genvar ideal_i;
	generate for (ideal_i = 0; ideal_i<n[L-1]; ideal_i = ideal_i + 1)
	begin: ideal_out_input
		assign ans0_tc[ideal_i] = (ideal_i<`NOUT)? ans_mem[ideal_i]:0;
	end
	endgenerate


endmodule
