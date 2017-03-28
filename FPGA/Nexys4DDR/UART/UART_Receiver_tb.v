`timescale 1ns / 1ps

module UART_Receiver_tb;

reg 	   Clk_tb;
parameter CLK_PERIOD=100;
always 	#(CLK_PERIOD/2) Clk_tb=~Clk_tb;
reg reset_tb;
reg switch_tb, isSending_tb;
wire tx1, tx2, done;
wire [7:0] data;

initial 
begin
Clk_tb=0;
switch_tb = 0;
reset_tb=0;
isSending_tb=0;
#(CLK_PERIOD*100)
reset_tb=1;
#(CLK_PERIOD*100)
reset_tb=0;
#(CLK_PERIOD*30)
switch_tb=1;
#(CLK_PERIOD*2)
//switch_tb=0;
#(CLK_PERIOD*40000)
isSending_tb = 1;



$stop;
end
UART_Control U1 (.CLK100MHZ(Clk_tb),.reset(reset_tb), .start(switch_tb), .TXD(tx1));
//UART_echo U2 (.CLK100MHZ(Clk_tb), .SW0(reset_tb), .SW1(switch_tb), .SW2(isSending_tb),.RXD(tx1), .TXD(tx2));
UART_RX U2 (.CLK100MHZ(Clk_tb), .RESET(reset_tb), .RXEN(switch_tb), .RXD(tx1), .DATA(data), .DONE(done));
//UART_Trans s1 (.CLK100MHZ(Clk_tb), .SW0(reset_tb), .SW1(switch_tb),.UART_RXD_OUT(out));
endmodule
