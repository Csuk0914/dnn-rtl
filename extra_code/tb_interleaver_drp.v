`timescale 1ns/100ps

module a_tb_interleave();

	parameter DRP_s  =3;
	parameter DRP_p  =5;
	parameter fo = 2;
	parameter fi  = 4;
	parameter p  = 16;
	parameter n  = 8;
	parameter z  = 8;

	reg [$clog2(fo*p/z)-1:0] cycle_index = 0;
	wire [$clog2(p)*z-1:0] memory_index;
	wire [$clog2(p/z)*z-1:0] address_package;
	
	interleaver_set maid(cycle_index, memory_index);
	activation_address_decoder_set AADS(memory_index, address_package);

	initial begin
		while(1) begin
			# 1 cycle_index = cycle_index + 1;
		end
	end

endmodule
