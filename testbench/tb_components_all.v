//Mahdi
//Test harness file for the network primitives
`timescale 1ns/1ps

`define Delay 0.1
`define Clk_Delay 2
`define Width 16 
`define IntWidth 5

module test();

  integer data_file    ; // file handler
  integer out_file    ; // file handler

  reg reset = 0;
  reg clk = 0;

  reg [`Width-1:0] a = 0;
  reg [`Width-1:0] b = 0;
  wire [`Width-1:0] multz;
  wire [`Width-1:0] addz;

  reg [`Width-1:0] lga = 0;
  reg [`Width-1:0] lgb = 0;
  wire [`Width-1:0] lgmultz;
  wire [`Width-1:0] lgaddz;

  integer i = 0;

//instantiate DUTs
multiplier #(`Width, `IntWidth) mult
(	.a(a),
	.b(b),
	.z(multz));

logmultiplier #(`Width, `IntWidth) logmult
(	.a(lga),
	.b(lgb),
	.z(lgmultz));

adder #(`Width) add
(	.a(a),
	.b(b),
	.z(addz));

logadder2 #(`Width, `IntWidth) lgadd
(	.a(lga),
	.b(lgb),
	.z(lgaddz));

initial begin
  clk = 0;
  forever #`Clk_Delay clk = ~clk;
end

initial begin
     out_file = $fopen("out.dat", "w");
     if (out_file == 0) begin
          $display("out_file handle was NULL");
          $finish;
     end
end

initial begin
   for (i = 0; i < 16; i = i +1) begin
      	
        lga[`Width-1] = $urandom;
	lga[`Width-2:`Width-2-`IntWidth] = $urandom;
	lga[`Width-2-`IntWidth-1:0] = $urandom;
        #100;
        lgb[`Width-1] = $urandom;
	lgb[`Width-2:`Width-2-`IntWidth] = $urandom;
	lgb[`Width-2-`IntWidth-1:0] = $urandom;
	#100  	  	
	$fwrite (out_file, "Test number %d:  %b   *    %b  =  %b\n", i, lga, lgb, lgmultz);
	$fwrite (out_file, "Test number %d:  %b   +    %b  =  %b\n", i, lga, lgb, lgaddz);
   end
  $finish;
end
endmodule
