`timescale 1ns/10ps

module ddr_ctrl #(
	parameter MAX_NUM = 614655
	)(
	input ui_clk_i,
	input ui_rst_i,
	input rst_ctrl_asy,
	input btnl_i,
	input w_en, 					// comes from 100Mhz clk domain, for consecutive write only
	input r_en,						// comes from ui_clk_i clk domain, for consecutive read only
	// input btnc_i,
	// output [15:0] led_o,
	// input rd_pause_i,				// high-active, to stop current continuous reading
	// input [23:0] cycle_num,			// how many consecutive R/W will happen (if want to read 3 times, this should be 2)
	input [23:0] mem_addr_i,		// internal addr is {mem_addr_i, 3'b0}
	input [1:0] mem_cmd_i,			// 00: write    01: read    11: keep reading (rd_pause_i to stop)
	input [127:0] app_wdf_data_i,
	input read_cycle_begin,
	// input [15:0] app_wdf_mask_i,	// low-active mask, each bit masks one byte

	// ddr
	input app_rdy,
	input app_wdf_rdy,
	output wdf_ack,
	output [26:0] app_addr_o,
	output [127:0] app_wdf_data_o,
	output reg rd_done_o,
	output reg wr_done_o,
	output reg [2:0] app_cmd_o,
	output reg app_en_o,
	output reg app_wdf_end_o,
	output reg app_wdf_wren_o
	);

	localparam IDLE				= 0;
	localparam WRITING_SINGLE	= 1;
	localparam READING_SINGLE	= 2;
	localparam READING_KEEP		= 3;
	localparam READING_BURST8	= 4;
	localparam WRITING_KEEP		= 5;
	localparam READING_KEEP_W	= 6;

	reg [3:0] cycle_num_r, cycle_count;

	reg [23:0] data_written_count;		// for consecutive write
	reg [23:0] app_addr_next_rd;		// for consecutive read
	reg [23:0] app_addr_r;

	reg [3:0] state;

	wire btnl_db, btnl_pulse;
	reg btnl_reg0, btnl_reg1;
	wire w_en_pulse;
	reg w_en_reg0, w_en_reg1, w_en_reg2;
	wire r_en_pulse;
	reg r_en_reg0, r_en_reg1, r_en_reg2;

	reg [5:0] image_count;

	assign app_addr_o = {app_addr_r, 3'b0};
	assign app_wdf_data_o = app_wdf_data_i;
	assign wdf_ack = app_wdf_rdy && app_wdf_wren_o;

	// debounce d_btn_l 
	// 	(
	// 		.clock			(ui_clk_i), 
	// 		.reset			(ui_rst_i),
	// 		.button			(btnl_i), 
	// 		.out			(btnl_db)
	// 	);

	always @(posedge ui_clk_i or posedge rst_ctrl_asy)
	if (ui_rst_i || rst_ctrl_asy)
	begin
		btnl_reg0 <= 0;
		btnl_reg1 <= 0;
		w_en_reg0 <= 0;
		w_en_reg1 <= 0;
		w_en_reg2 <= 0;
		r_en_reg0 <= 0;
		r_en_reg1 <= 0;
		r_en_reg2 <= 0;
	end
	else
	begin
		// btnl_reg0 <= btnl_db;
		btnl_reg0 <= btnl_i;
		btnl_reg1 <= btnl_reg0;
		w_en_reg0 <= w_en;
		w_en_reg1 <= w_en_reg0;
		w_en_reg2 <= w_en_reg1;
		r_en_reg0 <= r_en;
		r_en_reg1 <= r_en_reg0;
		r_en_reg2 <= r_en_reg1;
	end

	assign btnl_pulse = btnl_reg0 && (!btnl_reg1);
	assign w_en_pulse = w_en_reg1 && (!w_en_reg2);
	assign r_en_pulse = r_en_reg1 && (!r_en_reg2);

	// assign rd_done_o = (data_written_count!=0) && (app_addr_r>=data_written_count);

	always @(posedge ui_clk_i or posedge rst_ctrl_asy)
	begin
		if (ui_rst_i || rst_ctrl_asy)
		begin
			state <= IDLE;
			app_addr_r <= 0;
			app_en_o <= 0;
			app_cmd_o <= 1;
			// app_wdf_data_o <= 0;
			app_wdf_wren_o <= 0;
			app_wdf_end_o <= 0;
			data_written_count <= 0;
			app_addr_next_rd <= 0;
			cycle_count <= 0;
			rd_done_o <= 0;
			wr_done_o <= 0;
			image_count <= 0;
		end

		else
		begin
			case (state)
				IDLE:
				begin
					app_en_o <= 0;
					app_wdf_wren_o <= 0;
					if (w_en_pulse)
					begin
						// app_addr_r <= mem_addr_i;			// sim
						// data_written_count <= 0;				// sim
						app_addr_r <= data_written_count;					// syn
						data_written_count <= data_written_count + 1;		// syn
						app_en_o <= 1;
						app_cmd_o <= 0;
						app_wdf_wren_o <= 1;
						app_wdf_end_o <= 1;
						state <= WRITING_SINGLE;
					end
					if (r_en_pulse)
					begin
						app_addr_r <= 0;						
						// app_addr_r <= mem_addr_i;
						app_en_o <= 1;
						app_cmd_o <= 1;
						image_count <= 0;
						state <= READING_KEEP;
					end
					// if (btnl_pulse)
					// begin
					// 	app_addr_r <= mem_addr_i;
					// 	app_en_o <= 1;
					// 	case (mem_cmd_i)
					// 		2'b00:
					// 		begin
					// 			app_cmd_o <= 0;
					// 			// cycle_num_r <= cycle_num;
					// 			// cycle_count <= 1;
								// app_wdf_data_o <= app_wdf_data_i;
					// 			app_wdf_wren_o <= 1;
					// 			app_wdf_end_o <= 1;
					// 			state <= WRITING_SINGLE;
					// 		end
					// 		2'b01:
					// 		begin
					// 			app_cmd_o <= 1;
					// 			// cycle_num_r <= cycle_num;
					// 			// cycle_count <= 1;
					// 			state <= READING_SINGLE;
					// 		end
					// 		2'b11:
					// 		begin
					// 			app_cmd_o <= 1;

					// 			cycle_count <= 0;
					// 			state <= READING_BURST8;
					// 		end
					// 	endcase
					// end
				end
				WRITING_SINGLE:
				begin
					if (app_wdf_rdy)
					begin
						app_wdf_wren_o <= 0;
						app_wdf_end_o <= 0;
					end
					if (app_rdy)
					begin
						app_en_o <= 0;
					end
					if (app_rdy && app_wdf_rdy)
					begin
						if (app_addr_r == MAX_NUM)
							wr_done_o <= 1;
						state <= IDLE;
					end
				end
				READING_KEEP:
				begin
					if (app_rdy && app_en_o)
					begin
						app_addr_r <= app_addr_r + 1;
						image_count <= image_count + 1;

						// for board_top
						if (image_count == 48)
						begin
							app_en_o <= 0;
							state <= READING_KEEP_W;
						end

						// // for board_led
						// if (app_addr_r == mem_addr_i)
						// begin
						// 	app_en_o <= 0;
						// 	state <= IDLE;
						// end
					end
				end
				READING_KEEP_W:
				begin
					if (read_cycle_begin)
					begin
						app_en_o <= 1;
						image_count <= 0;
						state <= READING_KEEP;
					end
					if (app_addr_r == MAX_NUM)
					begin
						rd_done_o <= 1;
						state <= IDLE;
					end
				end
				// WRITING_KEEP:
				// begin
				// 	if (app_wdf_rdy)
				// 	begin
				// 		if (data_written_count == MAX_NUM)
				// 		begin
				// 			app_wdf_wren_o <= 0;
				// 			app_wdf_end_o <= 0;
				// 		end
				// 		else
				// 		begin
				// 			data_written_count <= data_written_count + 1;
				// 			// app_wdf_data_o <= app_wdf_data_i;
				// 		end
				// 	end
				// 	if (app_rdy)
				// 	begin
				// 		if (app_addr_r == MAX_NUM)
				// 			app_en_o <= 0;
				// 		else
				// 			app_addr_r <= app_addr_r + 1;
				// 	end
				// 	if (!app_wdf_wren_o && !app_en_o)
				// 	begin
				// 		wr_done_o <= 1;
				// 		state <= IDLE;
				// 	end
				// end
				// READING_SINGLE:
				// begin
				// 	if (app_rdy)
				// 	begin
				// 		app_en_o <= 0;
				// 		state <= IDLE;
				// 	end
				// end
				// READING_BURST8:
				// begin
				// 	if (app_rdy)
				// 	begin
				// 		app_addr_r <= app_addr_r + 1;
				// 		if (cycle_count == 15)
				// 		begin
				// 			app_en_o <= 0;
				// 			state <= IDLE;
				// 			cycle_count <= 0;
				// 		end
				// 		cycle_count <= cycle_count + 1;
				// 	end
				// end
				default:
				begin
					state <= IDLE;
				end
			endcase
		end
	end

endmodule