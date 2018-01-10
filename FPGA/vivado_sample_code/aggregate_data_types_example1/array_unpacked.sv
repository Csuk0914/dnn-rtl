`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/09/2012 06:04:09 PM
// Design Name: 
// Module Name: array_unpacked
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
//   array_unpacked.sv : top level module
//
// This example covers the following SystemVerilog structures:
// 1. parameter
// 2. always procedural block
// 3. block statements
// 4. operators : && , unary
// 5. unpacked array
// 
//////////////////////////////////////////////////////////////////////////////////

module array_unpacked #(parameter DATA_WIDTH = 8,
                      parameter ADDR_WIDTH = 8)(
input  wire                  clk      , // Clock Input
input  wire [ADDR_WIDTH-1:0] address  , // Address Input
inout  wire [DATA_WIDTH-1:0] data     , // Data bi-directional
input  wire                  cs       , // Chip Select
input  wire                  we       , // Write Enable/Read Enable
input  wire                  oe         // Output Enable
); 

reg [DATA_WIDTH-1:0]   data_out ;
reg [DATA_WIDTH-1:0] mem [ADDR_WIDTH-1:0]; //Unpacked array declaration

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