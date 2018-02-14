`timescale 1ns/100ps

module DNN_top(
	input CLK100MHZ, //system clock
	input BTNC, //reset signal
	input BTND, //transmitt
	input BTNL, //run

	//LED
	output LED0, //finish of trans
	output LED1, //finish running

	// RS232 signals
	input UART_TXD_IN,
	output UART_RXD_OUT
	);

parameter BAUD_RATE = 115_200; //for UART
wire reset;

//input/output buffers

assign reset = BTNC;


DNN DNN_test (
	.act0(),
	.ans0(),
	.etapos0(4),
	.clk(CLK100MHZ),
    .reset(reset),
	.ansL(),
	.actL_alln()
	);

endmodule