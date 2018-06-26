`timescale 1ps/1ps

module mig_top
(
	// Inouts
	inout [15:0]    ddr2_dq,
	inout [1:0]     ddr2_dqs_n,
	inout [1:0]     ddr2_dqs_p,
	
	// Outputs
	output [12:0]   ddr2_addr,
	output [2:0]    ddr2_ba,
	output          ddr2_ras_n,
	output          ddr2_cas_n,
	output          ddr2_we_n,
	
	output [0:0]    ddr2_ck_p,
	output [0:0]    ddr2_ck_n,
	output [0:0]    ddr2_cke,
	output [0:0]    ddr2_cs_n,
	
	output [1:0]    ddr2_dm,
	
	output [0:0]    ddr2_odt,
	
	
	// Inputs
	// Single-ended system clock
	input           sys_clk_i,
	
	output          init_calib_complete,
	input  [11:0]   device_temp_i,
	// The 12 MSB bits of the temperature sensor transfer
	// function need to be connected to this port. This port
	// will be synchronized w.r.t. to fabric clock internally.

	// for testbench
	input cs_i,
	input [23:0] mem_addr_i,
	input [23:0] cycle_num,
	input [1:0] mem_cmd_i,
	input [127:0] mem_wdf_data_i,
	input mem_wen_strike_i,
	input mem_ren_strike_i,
	input rd_pause_i,
	output ui_clk,
	output wdf_ack,
	output [127:0] mem_rd_data_o,
	output mem_rd_data_valid_o,
	output rd_done_o,
	output wr_done_o,
	
	
	// System reset - Default polarity of sys_rst pin is Active Low.
	// System reset polarity will change based on the option 
	// selected in GUI.
	input           sys_rst_n
);
	
	// Wire declarations
	wire [26:0]     app_addr;
	wire [2:0]      app_cmd;
	wire            app_en;
	wire            app_rdy;
	wire [127:0]     app_rd_data;
	wire            app_rd_data_end;
	wire            mem_rd_data_valid_o;
	wire [127:0]     app_wdf_data;
	wire            app_wdf_end;
	wire [15:0]     app_wdf_mask;
	wire            app_wdf_rdy;
	wire            app_sr_active;
	wire            app_ref_ack;
	wire            app_zq_ack;
	wire            app_wdf_wren;
	wire            mem_pattern_init_done;
	wire            ui_clk;
	wire            ui_rst;


	ddr u_ddr
	(
	// Memory interface ports
	.ddr2_addr                      (ddr2_addr),
	.ddr2_ba                        (ddr2_ba),
	.ddr2_cas_n                     (ddr2_cas_n),
	.ddr2_ck_n                      (ddr2_ck_n),
	.ddr2_ck_p                      (ddr2_ck_p),
	.ddr2_cke                       (ddr2_cke),
	.ddr2_ras_n                     (ddr2_ras_n),
	.ddr2_we_n                      (ddr2_we_n),
	.ddr2_dq                        (ddr2_dq),
	.ddr2_dqs_n                     (ddr2_dqs_n),
	.ddr2_dqs_p                     (ddr2_dqs_p),
	
	.init_calib_complete            (init_calib_complete),
	
	.ddr2_cs_n                      (ddr2_cs_n),
	.ddr2_dm                        (ddr2_dm),
	.ddr2_odt                       (ddr2_odt),
	// Application interface ports
	.app_addr                       (app_addr),
	.app_cmd                        (app_cmd),
	.app_en                         (app_en),
	.app_wdf_data                   (app_wdf_data),
	.app_wdf_end                    (app_wdf_end),
	.app_wdf_wren                   (app_wdf_wren),
	.app_rd_data                    (mem_rd_data_o),
	.app_rd_data_end                (app_rd_data_end),
	.app_rd_data_valid              (mem_rd_data_valid_o),
	.app_rdy                        (app_rdy),
	.app_wdf_rdy                    (app_wdf_rdy),
	.app_sr_req                     (1'b0),
	.app_ref_req                    (1'b0),
	.app_zq_req                     (1'b0),
	.app_sr_active                  (app_sr_active),
	.app_ref_ack                    (app_ref_ack),
	.app_zq_ack                     (app_zq_ack),
	.ui_clk                         (ui_clk),
	.ui_clk_sync_rst                (ui_rst),
	
	.app_wdf_mask                   (16'b0),
	
	
	// System Clock Ports
	.sys_clk_i                      (sys_clk_i),
	.device_temp_i                  (device_temp_i),
	.sys_rst                        (sys_rst_n)
	);


	
	ddr_ctrl inst_ddr_ctrl
		(
			.ui_clk_i       (ui_clk),
			.ui_rst_i       (ui_rst),
			.btnl_i         (cs_i),
			.w_en           (mem_wen_strike_i),
			.r_en           (mem_ren_strike_i),
			.rd_pause_i     (rd_pause_i),
			.cycle_num      (cycle_num),
			.mem_addr_i     (mem_addr_i),
			.mem_cmd_i      (mem_cmd_i),
			.app_wdf_data_i (mem_wdf_data_i),
			.app_rdy        (app_rdy),
			.app_wdf_rdy    (app_wdf_rdy),
			.wdf_ack		(wdf_ack),
			.app_addr_o     (app_addr),
			.rd_done_o      (rd_done_o),
			.wr_done_o		(wr_done_o),
			.app_wdf_data_o (app_wdf_data),
			.app_cmd_o      (app_cmd),
			.app_en_o       (app_en),
			.app_wdf_end_o  (app_wdf_end),
			.app_wdf_wren_o (app_wdf_wren)
		);
	

// End of User Design top instance          
endmodule
