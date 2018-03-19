`timescale 1ns / 100ps

module tb_multipliers #(
	parameter z = 5,
	parameter width = 12,
	parameter int_bits = 3
)(
);

logic signed [width-1:0] A,B,P;
logic signed [2*width-1:0] P_raw;
logic signed [width-1:0] As [z-1:0], Bs [z-1:0], Ps [z-1:0];
logic signed [width-1:0] dummy;

mult_IP_LUT mult_IP (
  .A(A),  // input wire [11 : 0] A
  .B(B),  // input wire [11 : 0] B
  .P(P_raw)  // output wire [23 : 0] P
);

multiplier #(
	.width(width),
	.int_bits(int_bits)
) mult (
	.a(A),
	.b(B),
	.p(P)
);

multiplier_set #(
	.z(z),
	.width(width),
	.int_bits(int_bits)
) multset (
	.a(As),
	.b(Bs),
	.p(Ps)
);

initial begin
	A = 12'b000000000000;
	B = 12'habc; //-1348, 
	dummy = '1>>1; //NOT related to multiplier
	As[0] = A;
	Bs[0] = B;
	// P_raw 0
	// P 0
	#10;
	A = 12'h001; //1, 2^-8
	dummy ++; //NOT related to multiplier
	// P_raw 24'hfffabc
	// P 12'hffb
	#10;
	A = '1; //-1, -2^-8
	// P_raw 24'h000544
	// P 12'h005
	#10;
	A = B;
	// P_raw 24'h1bba10
	// P 12'h7ff
	#10;
	A = 12'b011111111111; //2^11 - 1, 2^3 - 2^-8
	B = A;
	As[1] = A;
	Bs[1] = B;
	// P_raw 24'h3ff001
	// P 12'h7ff
	#10;
	A = 12'b100000000000; //-2^11, -2^3
	B = A;
	As[2] = A;
	Bs[2] = B;
	// P_raw 24'h400000 : most positive number possible = 2^22
	// P 12'h7ff
	#10;
	B = 12'b011111111111; //2^11 - 1, 2^3 - 2^-8
	// P_raw 24'hc00800 : most negative number possible = -2^22+2^11
	// P 12'h800
	#10;
	A = 12'h001; // 1, 2^-8
	B = A;
	// P_raw 24'h000001 : least positive number possible
	// P 0
	#10;
	B = '1; // -1, -2^-8
	As[3] = A;
	Bs[3] = B;
	//P_raw '1 : least magnitude negative number possible
	// P 0
	#10;
	A = 12'h080; //0.5
	B = 12'h101; //1 + 2^-8
	// P 12'h081 (round up)
	#10;
	A = 12'hf80; //-0.5
	B = 12'h0ff; //1 - 2^-8
	// P f81 (round up)
	As[4] = A;
	Bs[4] = B;
	#10 $stop;
end
endmodule


// Collection of z multipliers
module multiplier_set #(
	parameter z = 4,
	parameter width = 12,
	parameter int_bits = 3
)(
	input [width-1:0] a [z-1:0],
	input [width-1:0] b [z-1:0],
	output [width-1:0] p [z-1:0]
);
	genvar gv_i;	
	generate for (gv_i = 0; gv_i<z; gv_i++) begin
		multiplier #(
			.width(width),
			.int_bits(int_bits)
		) mul (
			.a(a[gv_i]),
			.b(b[gv_i]),
			.p(p[gv_i])
		);
	end
	endgenerate
endmodule
