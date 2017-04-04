`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/10/2015 12:33:28 PM
// Design Name: 
// Module Name: sw_led
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


module sw_led(
    input [15:0]SW,   // Slide switch inputs
    output [15:0]LED  //LED outputs
    );
    
    // Assign each sw to it's respective led
    assign LED = SW;
endmodule
