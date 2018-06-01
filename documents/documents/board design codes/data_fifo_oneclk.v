`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/02/2014 09:47:29 PM
// Design Name: 
// Module Name: data_fifo_oneclk
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
// 
//////////////////////////////////////////////////////////////////////////////////


module data_fifo_oneclk(
    input [7:0] din,
    input clk,
    input rst,
    input wr_en,
    input rd_en,
    output [7:0] dout,
    output empty,
    output full
    );
    
    reg [7:0] data [0:7];
    reg [3:0] rd_pt;
    reg [3:0] wr_pt;
   
    assign empty = (wr_pt == rd_pt);
    assign full = (wr_pt - rd_pt == 4'b1000);
    assign dout = data[rd_pt[2:0]];
    
    always @ (posedge clk)
    begin
        if (rst)
        begin
            rd_pt <= 4'b0000;
            wr_pt <= 4'b0000;
        end
        else
        begin
            if (wr_en && ~full)
            begin
                data[wr_pt[2:0]] <= din;
                wr_pt <= wr_pt + 1'b1;
            end
            if (rd_en && ~empty)
            begin
                rd_pt <= rd_pt + 1'b1;
            end
        end
    end
endmodule
