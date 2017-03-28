// File name: 	: fifo_reg_array_sc_n_plus_1_bit_pointers.v (sc = single clock)
// Design       : fifo_reg_array_sc 
// Author       : Gandhi Puvvada
// Date			: 10/26/2014 
// Here, we use (n+1) bit pointers.
// Hence signals almost_empty and almost_full are not needed.


//`timescale 1 ns/100 ps

module fifo_reg_array_sc #(
	parameter DATA_WIDTH = 8,
	parameter ADDR_WIDTH = 4
) (clk, reset, data_in, wen, ren, data_out, depth, empty, full);



input clk, reset;
input wen, ren; // the read or write request for CPU
input [DATA_WIDTH-1:0] data_in;
output [ADDR_WIDTH:0] depth;
output [DATA_WIDTH-1:0] data_out;
output empty, full;

reg [ADDR_WIDTH:0] rdptr, wrptr; //read pointer and write pointer of FIFO
wire [ADDR_WIDTH:0] depth;
wire wenq, renq;// read and write enable for FIFO
reg full, empty;

reg [DATA_WIDTH-1:0] Reg_Array [(2**ADDR_WIDTH)-1:0];// FIFO array

wire [ADDR_WIDTH:0] N_Plus_1_zeros = {(ADDR_WIDTH+1){1'b0}};
wire [ADDR_WIDTH-1:0] N_zeros = {(ADDR_WIDTH){1'b0}};
wire [ADDR_WIDTH:0] A_1_and_N_zeros = {1'b1, N_zeros}; 

assign depth = wrptr - rdptr;

always@(*)
begin
	empty  = 1'b0;
	full   = 1'b0;
	if (depth == N_Plus_1_zeros)
		empty  = 1'b1;
	if (depth ==  A_1_and_N_zeros) 
		full  = 1'b1;
end

assign wenq = (~full) & wen;// only if the FIFO is not full and there is write request from CPU, we enable the write to FIFO.
assign renq = (~empty)& ren;// only if the FIFO is not empty and there is read request from CPU, we enable the read to FIFO.
assign data_out = Reg_Array[rdptr[ADDR_WIDTH-1:0]]; // we use the lower N bits of the (N+1)-bit pointer as index to teh 2**N array.

always@(posedge clk, posedge reset)
begin
    if (reset)
		begin
			wrptr <= N_Plus_1_zeros;
			rdptr <= N_Plus_1_zeros;
		end
	else
		begin
			if (wenq) 
				begin
					Reg_Array[wrptr[ADDR_WIDTH-1:0]] <= data_in;  // we use the lower N bits of the (N+1)-bit pointer as index to teh 2**N array.
					wrptr <= wrptr + 1;
				end
			if (renq)
					rdptr <= rdptr + 1;
		end
end

endmodule