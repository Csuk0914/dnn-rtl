`timescale 1ps/100fs

module sim_tb_top;


   //***************************************************************************
   // Traffic Gen related parameters
   //***************************************************************************
   parameter SIMULATION            = "TRUE";
   parameter PORT_MODE             = "BI_MODE";
   parameter DATA_MODE             = 4'b0010;
   parameter TST_MEM_INSTR_MODE    = "R_W_INSTR_MODE";
   parameter EYE_TEST              = "FALSE";
									 // set EYE_TEST = "TRUE" to probe memory
									 // signals. Traffic Generator will only
									 // write to one single location and no
									 // read transactions will be generated.
   parameter DATA_PATTERN          = "DGEN_ALL";
									  // For small devices, choose one only.
									  // For large device, choose "DGEN_ALL"
									  // "DGEN_HAMMER", "DGEN_WALKING1",
									  // "DGEN_WALKING0","DGEN_ADDR","
									  // "DGEN_NEIGHBOR","DGEN_PRBS","DGEN_ALL"
   parameter CMD_PATTERN           = "CGEN_ALL";
									  // "CGEN_PRBS","CGEN_FIXED","CGEN_BRAM",
									  // "CGEN_SEQUENTIAL", "CGEN_ALL"
   parameter BEGIN_ADDRESS         = 32'h00000000;
   parameter END_ADDRESS           = 32'h00000fff;
   parameter PRBS_EADDR_MASK_POS   = 32'hff000000;

   //***************************************************************************
   // The following parameters refer to width of various ports
   //***************************************************************************
   parameter BANK_WIDTH            = 3;
									 // # of memory Bank Address bits.
   parameter CK_WIDTH              = 1;
									 // # of CK/CK# outputs to memory.
   parameter COL_WIDTH             = 10;
									 // # of memory Column Address bits.
   parameter CS_WIDTH              = 1;
									 // # of unique CS outputs to memory.
   parameter nCS_PER_RANK          = 1;
									 // # of unique CS outputs per rank for phy
   parameter CKE_WIDTH             = 1;
									 // # of CKE outputs to memory.
   parameter DM_WIDTH              = 2;
									 // # of DM (data mask)
   parameter DQ_WIDTH              = 16;
									 // # of DQ (data)
   parameter DQS_WIDTH             = 2;
   parameter DQS_CNT_WIDTH         = 1;
									 // = ceil(log2(DQS_WIDTH))
   parameter DRAM_WIDTH            = 8;
									 // # of DQ per DQS
   parameter ECC                   = "OFF";
   parameter RANKS                 = 1;
									 // # of Ranks.
   parameter ODT_WIDTH             = 1;
									 // # of ODT outputs to memory.
   parameter ROW_WIDTH             = 13;
									 // # of memory Row Address bits.
   parameter ADDR_WIDTH            = 27;
									 // # = RANK_WIDTH + BANK_WIDTH
									 //     + ROW_WIDTH + COL_WIDTH;
									 // Chip Select is always tied to low for
									 // single rank devices
   //***************************************************************************
   // The following parameters are mode register settings
   //***************************************************************************
   parameter BURST_MODE            = "8";
									 // DDR3 SDRAM:
									 // Burst Length (Mode Register 0).
									 // # = "8", "4", "OTF".
									 // DDR2 SDRAM:
									 // Burst Length (Mode Register).
									 // # = "8", "4".
   
   //***************************************************************************
   // The following parameters are multiplier and divisor factors for PLLE2.
   // Based on the selected design frequency these parameters vary.
   //***************************************************************************
   parameter CLKIN_PERIOD          = 4999;
									 // Input Clock Period

   //***************************************************************************
   // Simulation parameters
   //***************************************************************************
   parameter SIM_BYPASS_INIT_CAL   = "FAST";
									 // # = "SIM_INIT_CAL_FULL" -  Complete
									 //              memory init &
									 //              calibration sequence
									 // # = "SKIP" - Not supported
									 // # = "FAST" - Complete memory init & use
									 //              abbreviated calib sequence

   //***************************************************************************
   // IODELAY and PHY related parameters
   //***************************************************************************
   parameter TCQ                   = 100;
   //***************************************************************************
   // IODELAY and PHY related parameters
   //***************************************************************************
   parameter RST_ACT_LOW           = 1;
									 // =1 for active low reset,
									 // =0 for active high.

   //***************************************************************************
   // Referece clock frequency parameters
   //***************************************************************************
   parameter REFCLK_FREQ           = 200.0;
									 // IODELAYCTRL reference clock frequency
   //***************************************************************************
   // System clock frequency parameters
   //***************************************************************************
   parameter tCK                   = 3333;
									 // memory tCK paramter.
					 // # = Clock Period in pS.

   

   //***************************************************************************
   // Debug and Internal parameters
   //***************************************************************************
   parameter DEBUG_PORT            = "OFF";
									 // # = "ON" Enable debug signals/controls.
									 //   = "OFF" Disable debug signals/controls.
   //***************************************************************************
   // Debug and Internal parameters
   //***************************************************************************
   parameter DRAM_TYPE             = "DDR2";

	

  //**************************************************************************//
  // Local parameters Declarations
  //**************************************************************************//

  localparam real TPROP_DQS          = 0.00;
									   // Delay for DQS signal during Write Operation
  localparam real TPROP_DQS_RD       = 0.00;
					   // Delay for DQS signal during Read Operation
  localparam real TPROP_PCB_CTRL     = 0.00;
					   // Delay for Address and Ctrl signals
  localparam real TPROP_PCB_DATA     = 0.00;
					   // Delay for data signal during Write operation
  localparam real TPROP_PCB_DATA_RD  = 0.00;
					   // Delay for data signal during Read operation

  localparam MEMORY_WIDTH            = 16;
  localparam NUM_COMP                = DQ_WIDTH/MEMORY_WIDTH;
  localparam ECC_TEST 		   	= "OFF" ;
  localparam ERR_INSERT = (ECC_TEST == "ON") ? "OFF" : ECC ;

  localparam real REFCLK_PERIOD = (1000000.0/(2*REFCLK_FREQ));
  localparam RESET_PERIOD = 200000; //in pSec  
  localparam real SYSCLK_PERIOD = tCK;
	
	

  //**************************************************************************//
  // Wire Declarations
  //**************************************************************************//
  reg                                sys_rst_n;
  wire                               sys_rst;


  reg                     sys_clk_i;

  reg clk_ref_i;

  
  wire                               ddr2_reset_n;
  wire [DQ_WIDTH-1:0]                ddr2_dq_fpga;
  wire [DQS_WIDTH-1:0]               ddr2_dqs_p_fpga;
  wire [DQS_WIDTH-1:0]               ddr2_dqs_n_fpga;
  wire [ROW_WIDTH-1:0]               ddr2_addr_fpga;
  wire [BANK_WIDTH-1:0]              ddr2_ba_fpga;
  wire                               ddr2_ras_n_fpga;
  wire                               ddr2_cas_n_fpga;
  wire                               ddr2_we_n_fpga;
  wire [CKE_WIDTH-1:0]               ddr2_cke_fpga;
  wire [CK_WIDTH-1:0]                ddr2_ck_p_fpga;
  wire [CK_WIDTH-1:0]                ddr2_ck_n_fpga;
	
  
  wire                               init_calib_complete;
  wire                               tg_compare_error;
  wire [(CS_WIDTH*nCS_PER_RANK)-1:0] ddr2_cs_n_fpga;
	
  wire [DM_WIDTH-1:0]                ddr2_dm_fpga;
	
  wire [ODT_WIDTH-1:0]               ddr2_odt_fpga;
	
  
  reg [(CS_WIDTH*nCS_PER_RANK)-1:0] ddr2_cs_n_sdram_tmp;
	
  reg [DM_WIDTH-1:0]                 ddr2_dm_sdram_tmp;
	
  reg [ODT_WIDTH-1:0]                ddr2_odt_sdram_tmp;
	

  
  wire [DQ_WIDTH-1:0]                ddr2_dq_sdram;
  reg [ROW_WIDTH-1:0]                ddr2_addr_sdram;
  reg [BANK_WIDTH-1:0]               ddr2_ba_sdram;
  reg                                ddr2_ras_n_sdram;
  reg                                ddr2_cas_n_sdram;
  reg                                ddr2_we_n_sdram;
  wire [(CS_WIDTH*nCS_PER_RANK)-1:0] ddr2_cs_n_sdram;
  wire [ODT_WIDTH-1:0]               ddr2_odt_sdram;
  reg [CKE_WIDTH-1:0]                ddr2_cke_sdram;
  wire [DM_WIDTH-1:0]                ddr2_dm_sdram;
  wire [DQS_WIDTH-1:0]               ddr2_dqs_p_sdram;
  wire [DQS_WIDTH-1:0]               ddr2_dqs_n_sdram;
  reg [CK_WIDTH-1:0]                 ddr2_ck_p_sdram;
  reg [CK_WIDTH-1:0]                 ddr2_ck_n_sdram;

  reg cs_i;
  reg [23:0] mem_addr_i;
  reg [1:0] mem_cmd_i;
  reg [127:0] mem_wdf_data_i;
  reg mem_wen_strike_i;
  reg mem_ren_strike_i;
  wire ui_clk, ui_clk_buf;
  wire wdf_ack;
  wire [127:0] mem_rd_data_o;
  wire mem_rd_data_valid_o;
  wire rd_done_o;
  wire wr_done_o;
  wire [5:0] ddr_fifo_count;
  reg rd_begin;
  // reg wr_done;
  reg clk62_5mhz;
  wire rd_pause_i;
  wire [127:0] fifo_rd_out;
  reg ui_clk_en_latched;
  // wire ui_clk_gated = ui_clk && ui_clk_en_latched;
  wire ui_clk_gated;

  // assign mem_ren_strike_i = (wr_done&&(ddr_fifo_count<14)&&!rd_done_o);
  assign rd_pause_i = ddr_fifo_count > 26;

  // always @(ui_clk or mem_rd_data_valid_o or wr_done_o)
  // if (wr_done_o)
  // 	ui_clk_en_latched = (!ui_clk)? mem_rd_data_valid_o : ui_clk_en_latched;
  // else
  // 	ui_clk_en_latched = 0;

  BUFG clk_buf_p_i0 ( 
   .I(ui_clk), 
   .O(ui_clk_buf) 
	);


	BUFGCE bufgce_i0 (      
	   .I(ui_clk),
	   .CE(mem_rd_data_valid_o),
	   .O(ui_clk_gated)    
	);
	

//**************************************************************************//

  //**************************************************************************//
  // Reset Generation
  //**************************************************************************//
  initial begin
	sys_rst_n = 1'b0;
	#RESET_PERIOD
	  sys_rst_n = 1'b1;
   end

   assign sys_rst = RST_ACT_LOW ? sys_rst_n : ~sys_rst_n;

  //**************************************************************************//
  // Clock Generation
  //**************************************************************************//

  initial
	sys_clk_i = 1'b0;
  always
	sys_clk_i = #(CLKIN_PERIOD/2.0) ~sys_clk_i;


  initial
	clk_ref_i = 1'b0;
  always
	clk_ref_i = #REFCLK_PERIOD ~clk_ref_i;




  always @( * ) begin
	ddr2_ck_p_sdram   <=  #(TPROP_PCB_CTRL) ddr2_ck_p_fpga;
	ddr2_ck_n_sdram   <=  #(TPROP_PCB_CTRL) ddr2_ck_n_fpga;
	ddr2_addr_sdram   <=  #(TPROP_PCB_CTRL) ddr2_addr_fpga;
	ddr2_ba_sdram     <=  #(TPROP_PCB_CTRL) ddr2_ba_fpga;
	ddr2_ras_n_sdram  <=  #(TPROP_PCB_CTRL) ddr2_ras_n_fpga;
	ddr2_cas_n_sdram  <=  #(TPROP_PCB_CTRL) ddr2_cas_n_fpga;
	ddr2_we_n_sdram   <=  #(TPROP_PCB_CTRL) ddr2_we_n_fpga;
	ddr2_cke_sdram    <=  #(TPROP_PCB_CTRL) ddr2_cke_fpga;
  end
	

  always @( * )
	ddr2_cs_n_sdram_tmp   <=  #(TPROP_PCB_CTRL) ddr2_cs_n_fpga;
  assign ddr2_cs_n_sdram =  ddr2_cs_n_sdram_tmp;
	

  always @( * )
	ddr2_dm_sdram_tmp <=  #(TPROP_PCB_DATA) ddr2_dm_fpga;//DM signal generation
  assign ddr2_dm_sdram = ddr2_dm_sdram_tmp;
	

  always @( * )
	ddr2_odt_sdram_tmp  <=  #(TPROP_PCB_CTRL) ddr2_odt_fpga;
  assign ddr2_odt_sdram =  ddr2_odt_sdram_tmp;
	

// Controlling the bi-directional BUS

  genvar dqwd;
  generate
	for (dqwd = 1;dqwd < DQ_WIDTH;dqwd = dqwd+1) begin : dq_delay
	  WireDelay #
	   (
		.Delay_g    (TPROP_PCB_DATA),
		.Delay_rd   (TPROP_PCB_DATA_RD),
		.ERR_INSERT ("OFF")
	   )
	  u_delay_dq
	   (
		.A             (ddr2_dq_fpga[dqwd]),
		.B             (ddr2_dq_sdram[dqwd]),
		.reset         (sys_rst_n),
		.phy_init_done (init_calib_complete)
	   );
	end
	// For ECC ON case error is inserted on LSB bit from DRAM to FPGA
		  WireDelay #
	   (
		.Delay_g    (TPROP_PCB_DATA),
		.Delay_rd   (TPROP_PCB_DATA_RD),
		.ERR_INSERT ("OFF")
	   )
	  u_delay_dq_0
	   (
		.A             (ddr2_dq_fpga[0]),
		.B             (ddr2_dq_sdram[0]),
		.reset         (sys_rst_n),
		.phy_init_done (init_calib_complete)
	   );
  endgenerate

  genvar dqswd;
  generate
	for (dqswd = 0;dqswd < DQS_WIDTH;dqswd = dqswd+1) begin : dqs_delay
	  WireDelay #
	   (
		.Delay_g    (TPROP_DQS),
		.Delay_rd   (TPROP_DQS_RD),
		.ERR_INSERT ("OFF")
	   )
	  u_delay_dqs_p
	   (
		.A             (ddr2_dqs_p_fpga[dqswd]),
		.B             (ddr2_dqs_p_sdram[dqswd]),
		.reset         (sys_rst_n),
		.phy_init_done (init_calib_complete)
	   );

	  WireDelay #
	   (
		.Delay_g    (TPROP_DQS),
		.Delay_rd   (TPROP_DQS_RD),
		.ERR_INSERT ("OFF")
	   )
	  u_delay_dqs_n
	   (
		.A             (ddr2_dqs_n_fpga[dqswd]),
		.B             (ddr2_dqs_n_sdram[dqswd]),
		.reset         (sys_rst_n),
		.phy_init_done (init_calib_complete)
	   );
	end
  endgenerate
	

	

  //===========================================================================
  //                         FPGA Memory Controller
  //===========================================================================

  mig_top u_ip_top
	(
		.ddr2_dq              (ddr2_dq_fpga),
		.ddr2_dqs_n           (ddr2_dqs_n_fpga),
		.ddr2_dqs_p           (ddr2_dqs_p_fpga),
		.ddr2_addr            (ddr2_addr_fpga),
		.ddr2_ba              (ddr2_ba_fpga),
		.ddr2_ras_n           (ddr2_ras_n_fpga),
		.ddr2_cas_n           (ddr2_cas_n_fpga),
		.ddr2_we_n            (ddr2_we_n_fpga),
		.ddr2_ck_p            (ddr2_ck_p_fpga),
		.ddr2_ck_n            (ddr2_ck_n_fpga),
		.ddr2_cke             (ddr2_cke_fpga),
		.ddr2_cs_n            (ddr2_cs_n_fpga),
		.ddr2_dm              (ddr2_dm_fpga),
		.ddr2_odt             (ddr2_odt_fpga),
	 
		.sys_clk_i            (sys_clk_i),
	
		.device_temp_i        (12'b0),

		.cs_i                 (cs_i),
		.mem_addr_i				(24'b0),
		.cycle_num				(24'd511),
		.mem_cmd_i				(mem_cmd_i),
		.mem_wdf_data_i			(mem_wdf_data_i),
		.mem_wen_strike_i		(mem_wen_strike_i),
		.mem_ren_strike_i		(mem_ren_strike_i),
		.rd_pause_i				(1'b0),
		.ui_clk					(ui_clk),
		.wdf_ack				(wdf_ack),
		.mem_rd_data_o			(mem_rd_data_o),
		.mem_rd_data_valid_o	(mem_rd_data_valid_o),
		.rd_done_o				(rd_done_o),
		.wr_done_o				(wr_done_o),
	
		.init_calib_complete (init_calib_complete),
		.sys_rst_n           (sys_rst)
	 );

  //**************************************************************************//
  // Memory Models instantiations
  //**************************************************************************//

  genvar r,i;
  generate
	for (r = 0; r < CS_WIDTH; r = r + 1) begin: mem_rnk
	  if(DQ_WIDTH/16) begin: mem
		for (i = 0; i < NUM_COMP; i = i + 1) begin: gen_mem
		  ddr2_model u_comp_ddr2
			(
			 .ck      (ddr2_ck_p_sdram[0+(NUM_COMP*r)]),
			 .ck_n    (ddr2_ck_n_sdram[0+(NUM_COMP*r)]),
			 .cke     (ddr2_cke_sdram[0+(NUM_COMP*r)]),
			 .cs_n    (ddr2_cs_n_sdram[0+(NUM_COMP*r)]),
			 .ras_n   (ddr2_ras_n_sdram),
			 .cas_n   (ddr2_cas_n_sdram),
			 .we_n    (ddr2_we_n_sdram),
			 .dm_rdqs (ddr2_dm_sdram[(2*(i+1)-1):(2*i)]),
			 .ba      (ddr2_ba_sdram),
			 .addr    (ddr2_addr_sdram),
			 .dq      (ddr2_dq_sdram[16*(i+1)-1:16*(i)]),
			 .dqs     (ddr2_dqs_p_sdram[(2*(i+1)-1):(2*i)]),
			 .dqs_n   (ddr2_dqs_n_sdram[(2*(i+1)-1):(2*i)]),
			 .rdqs_n  (),
			 .odt     (ddr2_odt_sdram[0+(NUM_COMP*r)])
			 );
		end
	  end
	  if (DQ_WIDTH%16) begin: gen_mem_extrabits
		ddr2_model u_comp_ddr2
		  (
		   .ck      (ddr2_ck_p_sdram[0+(NUM_COMP*r)]),
		   .ck_n    (ddr2_ck_n_sdram[0+(NUM_COMP*r)]),
		   .cke     (ddr2_cke_sdram[0+(NUM_COMP*r)]),
		   .cs_n    (ddr2_cs_n_sdram[0+(NUM_COMP*r)]),
		   .ras_n   (ddr2_ras_n_sdram),
		   .cas_n   (ddr2_cas_n_sdram),
		   .we_n    (ddr2_we_n_sdram),
		   .dm_rdqs ({ddr2_dm_sdram[DM_WIDTH-1],ddr2_dm_sdram[DM_WIDTH-1]}),
		   .ba      (ddr2_ba_sdram),
		   .addr    (ddr2_addr_sdram),
		   .dq      ({ddr2_dq_sdram[DQ_WIDTH-1:(DQ_WIDTH-8)],
					  ddr2_dq_sdram[DQ_WIDTH-1:(DQ_WIDTH-8)]}),
		   .dqs     ({ddr2_dqs_p_sdram[DQS_WIDTH-1],
					  ddr2_dqs_p_sdram[DQS_WIDTH-1]}),
		   .dqs_n   ({ddr2_dqs_n_sdram[DQS_WIDTH-1],
					  ddr2_dqs_n_sdram[DQS_WIDTH-1]}),
		   .rdqs_n  (),
		   .odt     (ddr2_odt_sdram[0+(NUM_COMP*r)])
		   );
	  end
	end
  endgenerate
	
	


  //***************************************************************************
  // Reporting the test case status
  // Status reporting logic exists both in simulation test bench (sim_tb_top)
  // and sim.do file for ModelSim. Any update in simulation run time or time out
  // in this file need to be updated in sim.do file as well.
  //***************************************************************************
  initial
  begin : Logging
	 fork
		begin : calibration_done
		   wait (init_calib_complete);
		   $display("Calibration Done");
		   #50000000.0;
		   disable calib_not_done;
			// $finish;
		end

		begin : calib_not_done
		   if (SIM_BYPASS_INIT_CAL == "SIM_INIT_CAL_FULL")
			 #2500000000.0;
		   else
			 #1000000000.0;
		   if (!init_calib_complete) begin
			  $display("TEST FAILED: INITIALIZATION DID NOT COMPLETE");
		   end
		   disable calibration_done;
			$finish;
		end
	 join
  end

  initial clk62_5mhz = 0;
  always  #8000 clk62_5mhz = ~clk62_5mhz;

  // ddr_read_fifo ddr_read_fifo(
  //   	.resetn(sys_rst_n),
  //   	.wr_clk(ui_clk),
  //   	.rd_clk(clk62_5mhz),
  //   	.din(mem_rd_data_o),
  //   	.wr_en(mem_rd_data_valid_o),
  //   	.rd_en((rd_begin&&!rd_done_o)),
  //   	.dout(),
  //   	.wr_data_count(ddr_fifo_count)
  // 	);

  fifo_128 ddr_read_fifo (
  		.rst			(~sys_rst),
    	.wr_clk			(ui_clk),
    	.rd_clk			(clk62_5mhz),
    	.din			(mem_rd_data_o),
    	.wr_en			(mem_rd_data_valid_o),
    	.rd_en			(rd_begin&&!rd_done_o),
    	.dout			(fifo_rd_out),
    	.full			(),
    	.empty			(),
    	.rd_data_count	(ddr_fifo_count),
    	.wr_rst_busy	(),
    	.rd_rst_busy	()
    	);

  reg [15:0] w_counter;

  always @(posedge ui_clk_buf)
  if (init_calib_complete)
  begin
  	mem_wdf_data_i <= 0;
  	// if (!wr_done_o)
  	// 	mem_wen_strike_i <= 1;
  	if (w_counter!=511 && wdf_ack)
  	begin
  		w_counter <= w_counter + 1;
  		mem_wdf_data_i <= {w_counter[15:0], w_counter[15:0]+16'd1, w_counter[15:0]+16'd2, w_counter[15:0]+16'd3, w_counter[15:0]+16'd4, w_counter[15:0]+16'd5, w_counter[15:0]+16'd6, w_counter[15:0]+16'd7};
  	end
  	// if (w_counter==511 && wdf_ack) 
  	// begin
  	// 	// wr_done <= 1;
  	// 	mem_wen_strike_i <= 0;
  	// end
  end

  always @(posedge clk62_5mhz)
  begin
  	if (ddr_fifo_count>15) rd_begin <= 1;
  end

  initial
	begin
		w_counter = 0;
		rd_begin = 0;
		// wr_done = 0;
		mem_wen_strike_i = 0;
		mem_ren_strike_i = 0;
		mem_cmd_i = 0;
		mem_addr_i = 0;
		wait(init_calib_complete);
		mem_wen_strike_i = 1;
		@(posedge ui_clk_buf);
		mem_wen_strike_i = 0;
		wait(wr_done_o);
		repeat (2) @(posedge ui_clk_buf);
		mem_ren_strike_i = 1;
		@(posedge ui_clk_buf);
		mem_ren_strike_i = 0;
		// mem_wdf_data_i = 128'habcd;
		// cs_i = 0;
		// #(20*tCK);
		// wait(init_calib_complete);
		// #(3*10*tCK);
		// cs_i = 1;
		// #(15*tCK);
		// cs_i = 0;
		// mem_addr_i = 12;
		// mem_wdf_data_i = 128'h1234;
		// #(120*tCK);
		// cs_i = 1;
		// #(15*tCK);
		// cs_i = 0;
		// #(120*tCK);
		// cs_i = 1;
		// mem_cmd_i = 1;
		// mem_addr_i = 0;
		// #(15*tCK);
		// cs_i = 0;
		// mem_addr_i = 2;
		// #(120*tCK);
		// cs_i = 1;
		// #(15*tCK);
		// cs_i = 0;
		// #(120*tCK);
		// cs_i = 1;
		// mem_addr_i = 12;
		// #(15*tCK);
		// cs_i = 0;
		// #500;
		// $stop;
		wait(rd_done_o);
		$stop;

	end
	
endmodule
