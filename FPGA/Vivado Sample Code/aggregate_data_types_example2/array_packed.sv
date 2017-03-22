`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/09/2012 06:04:09 PM
// Design Name: 
// Module Name: array_packed
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// This example contains one file:
//   array_packed.sv : top level module
//
// This example covers the following SystemVerilog structures:
// 1. parameter
// 2. always procedural block
// 3. block statements
// 4. operators : && , unary
// 5. packed array
// 
//////////////////////////////////////////////////////////////////////////////////

module array_packed #(parameter DATA_WIDTH = 16,
                  parameter ADDR_WIDTH = 1024
                 )(
input  wire                  clk      , // Clock Input
input  wire [ADDR_WIDTH-1:0] address  , // Address Input
inout  wire [DATA_WIDTH-1:0] data     , // Data bi-directional
input  wire                  cs       , // Chip Select
input  wire                  we       , // Write Enable/Read Enable
input  wire                  oe         // Output Enable
); 

reg [DATA_WIDTH-1:0]   data_out ;
reg [DATA_WIDTH-1:0] [ADDR_WIDTH-1:0] mem ;    //packed array declaration

// Tri-State Buffer control 
// output : When we = 0, oe = 1, cs = 1
assign data = (cs && oe && !we) ? data_out : 8'bz; 

// Memory Write Block 
// Write Operation : When we = 1, cs = 1
always @ (posedge clk)
begin : MEM_WRITE
   if ( cs && we ) begin
       mem[address] = data;
   end
end

// Memory Read Block 
// Read Operation : When we = 0, oe = 1, cs = 1
always @ (posedge clk)
begin : MEM_READ
    if (cs && !we && oe) begin
         data_out = mem[address];
    end
end

endmodule