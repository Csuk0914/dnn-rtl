`timescale 1ns / 100ps

module tb_cost #(
	parameter z = 4,
	parameter width=12,
	parameter int_bits=3
)(
);

logic signed [width-1:0] a [z-1:0]; //computed output from network
logic [z-1:0] y; //ideal output (0 or 1 for each neuron)
logic signed [width-1:0] c [z-1:0]; //cost

costterm_set #(
	.z(z),
	.width(width),
	.int_bits(int_bits)
) cts (
	.a,
	.y,
	.c
);

initial begin
	a[0] = 12'b000000000000; //0
	a[1] = 12'b000001000000; //0.25
	a[2] = 12'b000011110000; //0.9375
	a[3] = 12'b000100000000; //1
	y = 4'b1101;
	//expected out[0,1,2,3] = f00,040,ff0,000
	#1 $stop;
end

endmodule
