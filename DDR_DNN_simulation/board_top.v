`timescale 1ps/100fs

module top;

	reg clk, rstn;

	reg [127:0] input_mem[0:614655];
	reg [19:0] input_addr;
	reg mem_wen_strike_i, mem_ren_strike_i;

	wire wr_done_o, wdf_ack;
	wire [127:0] mem_rd_data_o;
	wire mem_rd_data_valid_o, rd_done_o, init_calib_complete;

	reg ui_clk_en_latched;
	wire ui_clk_gated = ui_clk && ui_clk_en_latched;

	always @(ui_clk or mem_rd_data_valid_o or wr_done_o)
	if (wr_done_o)
		ui_clk_en_latched = (!ui_clk)? (mem_rd_data_valid_o||ui_rst) : ui_clk_en_latched;
	else
		ui_clk_en_latched = 0;

	always @(posedge ui_clk)
	if (init_calib_complete)
	begin
		if (input_addr!=16383 && wdf_ack)
		begin
			input_addr <= input_addr + 1;
		end
	end


	tb_DNN inst_tb_DNN 
	(
		.clk       (ui_clk_gated),
		.reset     (ui_rst),
		.act0      (mem_rd_data_o),
		.ansL      (ansL),
		.actL_alln (actL_alln)
	);

	mig_tb_top inst_mig_tb_top
	(
		.sys_clk_i           	(clk),
		.sys_rst_i             	(rstn),
		.cs_i                	(1'b0),
		.mem_addr_i          	(24'b0),
		.cycle_num				(20'd16383),				// 20'd614655
		.mem_cmd_i           	(2'b1),
		.mem_wdf_data_i      	(input_mem[input_addr]),
		.mem_wen_strike_i    	(mem_wen_strike_i),			
		.mem_ren_strike_i    	(mem_ren_strike_i),

		.ui_clk              	(ui_clk),
		.ui_rst				 	(ui_rst),
		.wdf_ack             	(wdf_ack),
		.mem_rd_data_o       	(mem_rd_data_o),
		.mem_rd_data_valid_o 	(mem_rd_data_valid_o),
		.rd_done_o           	(rd_done_o),
		.wr_done_o             	(wr_done_o),
		.init_calib_complete 	(init_calib_complete)
	);

	initial
	begin
		$readmemh("F:/OneDrive/usc/DR/DNN_vivado_no_change/DNN_vivado_no_change/data/train_input.dat", input_mem);
		input_addr = 0;
		clk = 0;
		rstn = 0;
		mem_wen_strike_i = 0;
		mem_ren_strike_i = 0;
		repeat (200) @(posedge clk);
		rstn = 1;
		wait(init_calib_complete);
		mem_wen_strike_i = 1;
		@(posedge ui_clk);
		mem_wen_strike_i = 0;
		wait(wr_done_o);
		repeat (2) @(posedge ui_clk);
		mem_ren_strike_i = 1;
		@(posedge ui_clk);
		mem_ren_strike_i = 0;
		wait(rd_done_o);
		$stop;
		
	end

	always #2500 clk = ~clk;

endmodule