`timescale 1ns/10ps

module ddr_ctrl(
	input ui_clk_i,
	input ui_rst_i,
	input btnl_i,
	input w_en, 					// comes from 100Mhz clk domain, for consecutive write only
	input r_en,						// comes from ui_clk_i clk domain, for consecutive read only
	// input btnc_i,
	// output [15:0] led_o,
	input rd_pause_i,				// high-active, to stop current continuous reading
	input [9:0] cycle_num,			// how many consecutive R/W will happen
	input [23:0] mem_addr_i,		// internal addr is {mem_addr_i, 3'b0}
	input [1:0] mem_cmd_i,			// 00: write    01: read    11: keep reading (rd_pause_i to stop)
	input [127:0] app_wdf_data_i,
	// input [15:0] app_wdf_mask_i,	// low-active mask, each bit masks one byte

	// ddr
	input app_rdy,
	input app_wdf_rdy,
	output [26:0] app_addr_o,
	output rd_done_o,
	output reg [127:0] app_wdf_data_o,
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

	reg [3:0] cycle_num_r, cycle_count;

	reg [23:0] app_addr_next_wr;		// for consecutive write
	reg [23:0] app_addr_next_rd;		// for consecutive read
	reg [23:0] app_addr_r;

	reg [3:0] state;

	wire btnl_db, btnl_pulse;
	reg btnl_reg0, btnl_reg1;
	wire w_en_pulse;
	reg w_en_reg0, w_en_reg1, w_en_reg2;
	wire r_en_pulse;
	reg r_en_reg0, r_en_reg1;

	assign app_addr_o = {app_addr_r, 3'b0};

	// debounce d_btn_l 
	// 	(
	// 		.clock			(ui_clk_i), 
	// 		.reset			(ui_rst_i),
	// 		.button			(btnl_i), 
	// 		.out			(btnl_db)
	// 	);

	always @(posedge ui_clk_i)
	if (ui_rst_i)
	begin
		btnl_reg0 <= 0;
		btnl_reg1 <= 0;
		w_en_reg0 <= 0;
		w_en_reg1 <= 0;
		w_en_reg2 <= 0;
		r_en_reg0 <= 0;
		r_en_reg1 <= 0;
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
	end

	assign btnl_pulse = btnl_reg0 && (!btnl_reg1);
	assign w_en_pulse = w_en_reg1 && (!w_en_reg2);
	assign r_en_pulse = r_en_reg0 && (!r_en_reg1);

	assign rd_done_o = (app_addr_next_wr!=0) && (app_addr_r>=app_addr_next_wr);

	always @(posedge ui_clk_i)
	begin
		if (ui_rst_i)
		begin
			state <= IDLE;
			app_addr_r <= 0;
			app_en_o <= 0;
			app_cmd_o <= 1;
			app_wdf_data_o <= 0;
			app_wdf_wren_o <= 0;
			app_wdf_end_o <= 0;
			app_addr_next_wr <= 0;
			app_addr_next_rd <= 0;
			cycle_count <= 0;
		end

		else
		begin
			case (state)
				IDLE:
				begin
					app_en_o <= 0;
					app_wdf_wren_o <= 0;
					// if (w_en_pulse)
					if (w_en)
					begin
						app_addr_r <= app_addr_next_wr;
						app_addr_next_wr <= app_addr_next_wr + 1;
						app_en_o <= 1;
						app_cmd_o <= 0;
						// cycle_num_r <= cycle_num;
						// cycle_count <= 1;
						app_wdf_data_o <= app_wdf_data_i;
						app_wdf_wren_o <= 1;
						app_wdf_end_o <= 1;
						state <= WRITING_SINGLE;
					end
					if (r_en_pulse)
					// begin
					// 	if (app_addr_next_rd < app_addr_next_wr)
					// 	begin
					// 		app_addr_r <= app_addr_next_rd;
					// 		app_addr_next_rd <= app_addr_next_rd + 8;
					// 		app_en_o <= 1;
					// 		app_cmd_o <= 1;
					// 		cycle_count <= 0;
					// 		state <= READING_BURST8;
					// 	end
					// end
					begin
						app_addr_r <= app_addr_next_rd;
						app_en_o <= 1;
						app_cmd_o <= 1;
						state <= READING_KEEP;
					end
					if (btnl_pulse)
					begin
						app_addr_r <= mem_addr_i;
						app_en_o <= 1;
						case (mem_cmd_i)
							2'b00:
							begin
								app_cmd_o <= 0;
								// cycle_num_r <= cycle_num;
								// cycle_count <= 1;
								app_wdf_data_o <= app_wdf_data_i;
								app_wdf_wren_o <= 1;
								app_wdf_end_o <= 1;
								state <= WRITING_SINGLE;
							end
							2'b01:
							begin
								app_cmd_o <= 1;
								// cycle_num_r <= cycle_num;
								// cycle_count <= 1;
								state <= READING_SINGLE;
							end
							2'b11:
							begin
								app_cmd_o <= 1;

								cycle_count <= 0;
								state <= READING_BURST8;
							end
						endcase
					end
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
						state <= IDLE;
					end
				end
				READING_SINGLE:
				begin
					if (app_rdy)
					begin
						app_en_o <= 0;
						state <= IDLE;
					end
				end
				READING_KEEP:
				begin
					if (rd_pause_i)
					begin
						app_en_o <= 0;
					end
					else
					begin
						app_en_o <= 1;
						if (app_rdy && app_en_o)
						begin
							app_addr_r <= app_addr_r + 1;
							if (app_addr_r == app_addr_next_wr-1)
							begin
								app_en_o <= 0;
								state <= IDLE;
							end
						end
					end
				end
				READING_BURST8:
				begin
					if (app_rdy)
					begin
						app_addr_r <= app_addr_r + 1;
						if (cycle_count == 15)
						begin
							app_en_o <= 0;
							state <= IDLE;
							cycle_count <= 0;
						end
						cycle_count <= cycle_count + 1;
					end
				end
				default:
				begin
					state <= IDLE;
				end
			endcase
		end
	end

endmodule