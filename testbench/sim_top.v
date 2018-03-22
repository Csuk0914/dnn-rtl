`timescale 1ps/100fs

module noDDR_sim_top;

	reg clk, clk_20, rstn;
	wire clk_20_gated, clk_20_buf;
	
	wire ui_clk, ui_rst;
	wire ansL;
	wire [63:0] actL_alln;

	reg [127:0] input_mem[0:614655];
	reg [19:0] input_addr;
	reg mem_wen_strike_i, mem_ren_strike_i;

	wire wr_done_o, wdf_ack;
	wire [127:0] mem_rd_data_o;
	wire [127:0] dnn_input, fifo_out;
	wire mem_rd_data_valid_o, rd_done_o, init_calib_complete;

	wire cycle_clk;
	wire [6:0] cycle_index;
	// wire read_cycle_begin;
	wire cycle_zero;

	// reg rd_pause_i;

	// reg ui_clk_en_latched;
	// wire ui_clk_gated = ui_clk && ui_clk_en_latched;

	// always @(ui_clk or mem_rd_data_valid_o or wr_done_o or ui_rst)
	// if (wr_done_o || ui_rst)
	// 	ui_clk_en_latched = (!ui_clk)? (mem_rd_data_valid_o||ui_rst) : ui_clk_en_latched;
	// else
	// 	ui_clk_en_latched = 0;

	wire ui_clk_buf, ui_clk_gated;
	wire clk_20_gate_en;
	wire fifo_empty;
	wire fifo_rd;
	wire [6:0] wr_data_count;

	reg [2:0] dnn_rst_count;
	wire dnn_rst;

	reg [15:0] output_count;
	reg [9:0] output_store [0:199];
	reg [7:0] store_count;

	assign cycle_zero = (cycle_index<2) || (cycle_index>50);
	assign dnn_rst = dnn_rst_count[2];
	assign clk_20_gate_en = dnn_rst_count[2] || cycle_zero;
	assign fifo_rd = ~cycle_zero;
	assign dnn_input = cycle_zero? 0 : input_mem[input_addr];
	// assign ui_clk_gate_en = ui_rst || mem_rd_data_valid_o || (cycle_index<2) || (cycle_index>50);
	// assign dnn_input = ((cycle_index<2) || (cycle_index>50))? 0 : mem_rd_data_o;
	// assign read_cycle_begin = (cycle_index == 2);

	// BUFG bufg_ui_clk 
	// 	( 
	// 		.I		(ui_clk), 
	// 		.O		(ui_clk_buf) 
	// 	);

	// BUFG bufg_clk_20 
	// 	( 
	// 		.I		(clk_20), 
	// 		.O		(clk_20_buf) 
	// 	);

	// BUFGCE bufgce_clk_20 
	// 	(      
	// 		.I		(clk_20),
	// 		.CE		(clk_20_gate_en),
	// 		.O		(clk_20_gated)    
	// 	);

	always @(posedge clk_20 or negedge rstn)
	if (!rstn)
	begin
		dnn_rst_count <= 3'b100;
	end
	else
	begin
		if (dnn_rst_count != 0)
			dnn_rst_count <= dnn_rst_count + 1;
	end

	always @(posedge clk_20)
	begin
		if (!cycle_zero)
		begin
			input_addr <= input_addr + 1;
		end
		// if (cycle_index == 1)
		// 	read_cycle_begin <= 1;
		// if (cycle_index == 3)
		// 	read_cycle_begin <= 0;
	end

	always @(posedge clk_20)
	if (dnn_rst)
	begin
		output_count <= 0;
		store_count <= 0;
	end
	else
	begin
		if (cycle_clk)
		begin
			output_count <= output_count + 1;
			if (output_count > 12343)
			begin
        	    store_count <= store_count + 1;
				output_store[store_count] <= actL_alln[9:0];
			end
		end
	end

	tb_DNN_top inst_DNN_top 
		(
			.clk       		(clk_20),
			.reset     		(dnn_rst),
			.act0      		(dnn_input),
			.ansL      		(ansL),
			.actL_alln 		(actL_alln),
			.cycle_clk		(cycle_clk),
			.cycle_index	(cycle_index)
		);

	// tb_DNN_top inst_tb_DNN_top 
	// (
	// 	.clk       		(ui_clk_gated),
	// 	.reset     		(ui_rst),
	// 	.act0      		(dnn_input),
	// 	.ansL      		(ansL),
	// 	.actL_alln 		(actL_alln),
	// 	.cycle_clk		(cycle_clk),
	// 	.cycle_index	(cycle_index)
	// );


	// mig_tb_top #(
	// 	.MAX_NUM				(9800)					// 614655
	// ) inst_mig_tb_top (
	// 	.sys_clk_i           	(clk),
	// 	.sys_rst_i             	(rstn),
	// 	.cs_i                	(1'b0),
		
		
		
	// 	.mem_addr_i          	(24'b0),
	// 	.mem_cmd_i           	(2'b1),
	// 	.mem_wdf_data_i      	(input_mem[input_addr]),
	// 	.mem_wen_strike_i    	(mem_wen_strike_i),			
	// 	.mem_ren_strike_i    	(mem_ren_strike_i),
	// 	.read_cycle_begin		(fifo_empty),
	// 	// .rd_pause_i				(rd_pause_i),

	// 	.ui_clk              	(ui_clk),
	// 	.ui_rst				 	(ui_rst),
	// 	.wdf_ack             	(wdf_ack),
	// 	.mem_rd_data_o       	(mem_rd_data_o),
	// 	.mem_rd_data_valid_o 	(mem_rd_data_valid_o),
	// 	.rd_done_o           	(rd_done_o),
	// 	.wr_done_o             	(wr_done_o),
	// 	.init_calib_complete 	(init_calib_complete)
	// );

	// fifo_128b_49d fifo_ins
	// (
	//     .rst 			(ui_rst),
	//     .wr_clk			(ui_clk_buf), 		
	//     .rd_clk			(clk_20), 	
	//     .din			(mem_rd_data_o), 
	//     .wr_en			(mem_rd_data_valid_o), 	
	//     .rd_en			(fifo_rd), 	
	//     .dout			(fifo_out), 
	//     .full			(), 
	//     .empty			(fifo_empty), 
	//     .wr_data_count	(wr_data_count),
	//     .wr_rst_busy 	(),
	//     .rd_rst_busy 	()
	// );

	initial
	begin
		$readmemh("F:/OneDrive/usc/DNN_DDR_final/final/data/train_input.dat", input_mem);
		input_addr = 0;
		// rd_pause_i = 0;
		clk = 0;
		clk_20 = 0;
		rstn = 0;
		// mem_wen_strike_i = 0;
		// mem_ren_strike_i = 0;
		#50000;
		rstn = 1;
		// wait(init_calib_complete);
		// mem_wen_strike_i = 1;
		// @(posedge ui_clk);
		// mem_wen_strike_i = 0;
		// wait(wr_done_o);
		// repeat (2) @(posedge ui_clk);
		// mem_ren_strike_i = 1;
		// repeat (49) @(posedge ui_clk);
		// @(posedge ui_clk);
		// mem_ren_strike_i = 0;
		wait(output_count==12544);
		$stop;
		
	end

	always #2500 clk = ~clk;
	always #25000 clk_20 = ~clk_20;

endmodule