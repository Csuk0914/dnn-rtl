`timescale 1ns/100ps


module a_FF_processor_set_tb ();

	parameter fo = 2;
	parameter fi  = 4;
	parameter p  = 8;
	parameter n  = 4;
	parameter z  = 4;
	parameter width =16;

	wire [width*z-1:0] a_package;
	wire [width*z-1:0] w_package;
	wire [width*z/fi -1:0] sigmoid_package;
	wire [width*z/fi -1:0]  sp_package;
	reg [width-1:0] a[z-1:0];
	reg [width-1:0] w[z-1:0];
	integer i;
	genvar gv_i;

	FF_processor_set #(.fo(fo), 
		.fi(fi), 
		.p(p), 
		.n(n), 
		.z(z), 
		.width(width)) FF(a_package, w_package, sigmoid_package, sp_package);

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_z
		assign a_package[width*(gv_i+1)-1:width*gv_i] = a[gv_i];
		assign w_package[width*(gv_i+1)-1:width*gv_i] = w[gv_i];
	end
	endgenerate

	initial begin
		while(1) begin
			for (i=0; i<z; i = i + 1) begin
			a[i] = $random%1024;
			w[i]= $random;
			end
			#1; 
		end
	end

endmodule
