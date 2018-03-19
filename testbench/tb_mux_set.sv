`timescale 1ns / 1ps

module tb_mux_set #(
	parameter width = 8,
	parameter N = 1, //No. of inputs
	parameter M = 1 //No. of MUXes. For our application, generally this will be = N
)(
);

logic [width-1:0] in [N-1:0];
logic [$clog2(N)-(N!=1):0] sel [M-1:0];
logic [width-1:0] out [M-1:0];

mux_set #(
	.width(width),
	.M(M),
	.N(N)
) ms (
	.in,
	.sel,
	.out
);

//For M=3,N=4
/*initial begin
	integer i;
	for (i=0; i<N; i++) begin
		in[i] = i+1;
	end
	sel[0] = 2'b10;
	sel[1] = 2'b00;
	sel[2] = 2'b11;
	//out[0,1,2] should be 3,1,4
	#10 $stop;
end*/

//For M=N=1
initial begin
	in[0] = 8'haa;
	sel[0] = 1;
	//out should be aa
	#10 $stop;
end

endmodule
