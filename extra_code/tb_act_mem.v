//this testbench verifies the function of the memory_ctr.v, which contains the address generator of activation memory
`timescale 1ns/100ps

module a_L0_act_mem_tb();

	parameter fo = 2;
	parameter fi  = 4;
	parameter p  = 16;
	parameter n  = 8;
	parameter z  = 8;
	parameter eta = 0.05;
	parameter lamda = 0.99;
	parameter L = 2;
	parameter cpc = p/z*fo+2;
	parameter width = 16;
	parameter collection = 2 * L - 1;

	reg clk = 1, reset=1;
	reg [width-1:0] act0[z/fo-1:0];
	reg [width-1:0] d1[z/fi-1:0];

	wire [$clog2(cpc)-1:0] cycle_index;
	wire cycle_clk;
	wire [width*p/z*fo-1:0]act0_package;
	wire [width-1:0] r0_data[z-1:0], r1_data[z-1:0];
	wire [width*z/fi-1:0] act1_package, d1_package, sp1_package;
	wire [width-1:0] act1[z/fi-1:0], sp1[z/fi-1:0];

	genvar gv_i;
	integer i, j = 0;

	generate for (gv_i = 0; gv_i<p/z*fo; gv_i = gv_i + 1)
	begin: package
		assign act0_package[width*(gv_i+1)-1:width*gv_i] = act0[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z/fi; gv_i = gv_i + 1)
	begin: package_z
		assign act1[gv_i] = act1_package[width*(gv_i+1)-1:width*gv_i];
		assign sp1[gv_i] = sp1_package[width*(gv_i+1)-1:width*gv_i];
		assign d1_package[width*(gv_i+1)-1:width*gv_i] = d1[gv_i];
	end
	endgenerate

	input_layer_block #(.fo(fo), 
		.fi(fi), 
	 	.p(p), 
	 	.n(n), 
	 	.z(z), 
	 	.eta(eta), 
	 	.lamda(lamda),
	 	.width(width), 
	 	.L(L)) input_layer_block(clk, reset, cycle_index, cycle_clk, 
	 		act0_package, d1_package, 
			act1_package, sp1_package);

	 //for some reason, the clk_per_block should greater than 1
	cycle_block_counter #(.clk_per_block(cpc), 
			.ini(0)) cycle_counter
			(clk, reset, cycle_clk, cycle_index);

	always begin
		# 15;
		while(1) begin
			for (i = 0; i<z/fo; i = i + 1)
			begin
				act0[i] = j%(2**width);
				d1[i] = j%(2**width);
				j = j + 1;
			end
		# 10;
		end
	end

	always
		# 5 clk = ~clk;

	initial begin
		for (i = 0; i<z/fo; i = i + 1)
			begin
				act0[i] = 0;
			end
		#15 reset = 0;
	end
	// first_layer_state_machine #(	
	// 	.fo(fo), 
	// 	.fi(fi), 
	// 	.p(p), 
	// 	.n(n), 
	// 	.z(z), 
	// 	.cpc(cpc), 
	// 	.width(width), 
	// 	.collection(collection)) first_layer_state_machine
	// 	// (clk, reset, data_in_package, 
	// 	// address_package, r_en_package, w_en_package, mux_sel, 
	// 	// data_in_mem, r0_pt, r1_pt);
	// 	(clk, reset, data_in, cycle_index, 
	// 	addrA_package, weA_package, addrB_package, weB_package, mux_sel, 
	// 	data_in_mem, r0_pt, r1_pt);

	// mem_collection #(
	// 	.collection(collection), 
	// 	.width(width), 
	// 	.depth(p/z), 
	// 	.z(z)) act_mem0
	// 	// (clk, r_en_package, w_en_package, address_package, 
	// 	// data_in_mem, data_out_package);
	// 	(clk, 
	// 	weA_package, addrA_package, data_in_mem, , 
	// 	weB_package, addrB_package, , data_out_package);

	// mux #(.width(width*z), 
	// 	.N_to_1(collection)) r0
	// 	(data_out_package, r0_pt, r0_raw);

	// mux #(.width(width*z), 
	// 	.N_to_1(collection)) r1
	// 	(data_out_package, r1_pt, r1_raw);

	// mux_set #(.width(width), 
	// 	.N_to_1(z)) r0_mux
	// 	(r0_raw, mux_sel, r0_package);

	// mux_set #(.width(width), 
	// 	.N_to_1(z)) r1_mux
	// 	(r1_raw, mux_sel, r1_package);


	
		

endmodule

