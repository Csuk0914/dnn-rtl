`timescale 1ns / 1ps

module UART_Tran_tb;

reg 	   Clk_tb;
parameter CLK_PERIOD=100;
always 	#(CLK_PERIOD/2) Clk_tb=~Clk_tb;
reg reset_tb;
reg switch_tb;
wire out;

initial 
begin
Clk_tb=0;
switch_tb = 0;
reset_tb=0;
#(CLK_PERIOD*100)
reset_tb=1;
#(CLK_PERIOD*100)
reset_tb=0;
#(CLK_PERIOD*30)
switch_tb=1;
#(CLK_PERIOD*2)
//switch_tb=0;
#(CLK_PERIOD*1000)



$stop;
end
UART_Control U1 (.CLK100MHZ(Clk_tb),.reset(reset_tb), .start(switch_tb), .TXD(out));
//UART_Trans s1 (.CLK100MHZ(Clk_tb), .SW0(reset_tb), .SW1(switch_tb),.UART_RXD_OUT(out));
endmodule