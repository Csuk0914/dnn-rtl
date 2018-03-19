//Mahdi
// THIS MODULE DEFINES VARIOUS BASIC LOG-DOMAIN COMPONENTS TO BE USED IN THE DESIGN
`timescale 1ns/100ps

//[ToDo] check overflow conditions if exists
module logmultiplier #(
	parameter width = 16,
	parameter int_bits = 5 //No. of bits in integer portion
)(
	input [width-1:0] a, //1,5,10
	input [width-1:0] b, //1,5,10
	output [width-1:0] z //1,5,10
);
	//assumes that the sign bits are enclosed.
	//this preserves the in/out ports as they are.
	wire sa;
	wire sb;
	wire sz;
	assign sa = a[width-1]; 
	assign sb = b[width-1];
	assign sz = !(sa ^ sb);
	assign z = {sz, a + b}; //encloses the sign bit (sz).

endmodule

//log multiplier set
module logmultiplier_set #(
	parameter z = 4, 
	parameter width = 16,
	parameter int_bits = 5
)(
	input [width*z-1:0] a_set,
	input [width*z-1:0] b_set,
	output [width*z-1:0] z_set
);
	wire [width-1:0] a[z-1:0], b[z-1:0], out[z-1:0];

	genvar gv_i;
	
	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : package_data
		assign a[gv_i] = a_set[width*(gv_i+1)-1:width*gv_i];
		assign b[gv_i] = b_set[width*(gv_i+1)-1:width*gv_i];
		assign z_set[width*(gv_i+1)-1:width*gv_i] = out[gv_i];
	end
	endgenerate

	generate for (gv_i = 0; gv_i<z; gv_i = gv_i + 1)
	begin : logmultiplier_set
		logmultiplier #(.width(width),.int_bits(int_bits)) mul (a[gv_i], b[gv_i], out[gv_i]);
	end
	endgenerate
endmodule

module logadder #(
	parameter width = 16,
	parameter int_width = 5
)(
	input [width-1:0] a,
	input [width-1:0] b,
	output [width-1:0] z
);

        function [width-1:0] cf;
                input [width-2:width-2-int_width] r;
                cf = 10'b1000000000 >> r;
        endfunction

        //assumes that the sign bits are enclosed.
        //this preserves the in/out ports as they are.
        wire sa;
        wire sb;
	wire sz;
	assign sa = a[width-1];
	assign sb = b[width-1]; 
	//a greater than b flag
	wire agb_flag; 
	wire [width-1:0] r;
	wire [width-1:0] max;
	
	assign agb_flag = (a[width-2:0] > b[width-2:0]) ? 1 : 0;
	assign sz = (!agb_flag & sb) | (!agb_flag & sa);
	assign r = agb_flag ? (a - b) : (b - a); //abs of a and b
	assign max = ($signed(a)>$signed(b)) ? a : b;
	assign z = (sa == sb) ? (max + cf(r[width-2:width-2-int_width])) : (max - cf(r[width-2:width-2-int_width]-1)); //CF: Correction Factor implemented as a LUT
	  							// if the difference between a and b is significant then CF ~ 0	

//        always @(*)begin
//                if (sa == sb && sa == 1) max = (a[width-2:0] > b[width-2:0]) ? b : a;
//                else                     max = ($signed(a)>$signed(b)) ? a : b;
//        end

endmodule

//Lookup table implementation of logadder
/*module logadder #(
	parameter width = 16
)(
	input [width-1:0] a,
	input [width-1:0] b,
	output [width-1:0] z
);
	function  cf;
		input r;		
			case (r)
				0 : cf = 1.000;
				1 : cf = 0.500;
				2 : cf = 0.250;
                                3 : cf = 0.125;
                                4 : cf = 0.062;
                                5 : cf = 0.031;
                                6 : cf = 0.015;
                                7 : cf = 0.007;
                                8 : cf = 0.003;
                                9 : cf = 0.001;
                                10 : cf = 0;
                                11 : cf = 0;
                                12 : cf = 0;
                                13 : cf = 0;
                                14 : cf = 0;	
                                15 : cf = 0;
                                16 : cf = 0;			
			endcase
	endfunction

        //assumes that the sign bits are enclosed.
        //this preserves the in/out ports as they are.
        wire sa;
        wire sb;
	wire sz;
	assign sa = a[width-1];
	assign sb = b[width-1]; 
	//a greater than b flag
	wire agb_flag; 
	wire [width-1:0] r;
	wire [width-1:0] max;
	
	assign agb_flag = (a[width-2:0] > b[width-2:0]) ? 1 : 0;
	assign sz = (!agb_flag & sb) | (!agb_flag & sa);
	assign r = agb_flag ? (a - b) : (b - a); //abs of a and b
	assign max = agb_flag ? a : b;
	assign z = (sa == sb) ? (max + cf(r)) : (max - cf(r-1)); //CF: Correction Factor implemented as a LUT
	  							// if the difference between a and b is significant then CF ~ 0	
endmodule*/
