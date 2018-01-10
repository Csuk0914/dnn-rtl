`timescale 1ns/100ps
module tb_maxfinder #(
	parameter width = 4,
	parameter N = 32
)(
);

reg [width*N-1:0] in;
reg [width-1:0] in2;
reg [width*8-1:0] in3;
reg [11:0] in4;
wire [width-1:0] out, out2, out3;
wire [5:0] out4;
wire [$clog2(N)-1:0] pos;
wire [2:0] pos3;
wire pos2, pos4;
wire [4:0] test;

max_finder_set #(.width(width),.N(N)) mfs (.in(in),.out(out),.pos(pos));

initial begin
	in = 128'b00000001001000110100010101100111100010011010101111001101111011110000000000000000010101010101010101010101010101011111111111111111;
	#20 in = 128'b00000000000000000101010101010101010101010101010111111111111111110000000000000000010101010101010101010101010101011111111111111111;
	#20 in = 128'b00000000000000000000000000000000000000000000000000000000000000011000111100010001000100100010001011111111111111111111111111011100;
	#20 $stop;
end

max_finder_set #(.width(width),.N(1)) mfs_trivial (.in(in2),.out(out2),.pos(pos2));

initial begin
	in2 = 16'h4;
	#20 in2 = 16'hf;
	#20 in2 = 16'h0;
end

max_finder_set #(.width(width),.N(8)) mfs_N8 (.in(in3),.out(out3),.pos(pos3));

initial begin
	in3 = 32'habcdef04;
	#20 in3 = 32'h12345670;
	#20 in3 = 32'h0000ffff;
end

max_finder_set #(.width(6),.N(2)) mfs_base (.in(in4),.out(out4),.pos(pos4));

initial begin
	in4 = 12'b010101010111;
	#20 in4 = 12'b101110000000;
	#20 in4 = 12'b000001111111;
end

endmodule
