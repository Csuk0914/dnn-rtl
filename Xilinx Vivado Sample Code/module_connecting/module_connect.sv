`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/16/2012 05:53:40 PM
// Design Name: 
// Module Name: module_connect
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
// This example mainly demonstrates the following SystemVerilog structures:
// 1. module connecting
// 2. module connecting with wildcard ports
// 
//////////////////////////////////////////////////////////////////////////////////


module module_connect(
    input int a, b,
    output int r1,
    output int sum,
    output int r4,
    output logic [15:0] r2
    );
    
    adder #(.delay (5.0)) i1 (a, b, r1); // a 32-bit 2-state adder
    adder #(.delay (5.0)) i3 (.a, .b, .sum); // a 32-bit 2-state adder
    adder #(.dtype (logic[15:0])) i2 (a, b, r2);  // a 16 bit 4-state adder
    adder #(.delay (5.0)) i4 (.*, .sum(r4)); // a 32-bit 2-state adder
    
endmodule

module adder #(parameter type dtype = int, parameter realtime delay = 4) (
    input dtype a, b, 
    output dtype sum
    );
    
    assign sum = a + b;
endmodule