module UART_echo(
	input wire CLK100MHZ,
	input wire SW0, SW1, SW2, 
	input wire RXD,
	output wire TXD
);

wire empty, full;
wire [3:0] depth;
wire [7:0] tx_data, rx_data;
wire rx_done, tx_done;
wire isRX, isTX, reset;

assign reset = SW0;		//Active high reset
assign isRX = SW1;		//Active high RX Enable
assign isTX = SW2;		//Active high TX Enable

//Baudrate=115200: 868 clock cycles of 100MHZ.  Derived from ( 1/115200 )/( 1/100E+6 )  
UART_RX #(8,868) URX (.CLK100MHZ(CLK100MHZ), .RESET(reset), .RXEN(isRX), .RXD(RXD), .DATA(rx_data), .DONE(rx_done));
fifo_reg_array_sc #(8,4)UFIFO (.clk(CLK100MHZ), .reset(reset), .data_in(rx_data), .wen(rx_done), .ren(tx_done), .data_out(tx_data), .depth(depth), .empty(empty), .full(full));
UART_TX #(8,868) UTX (.CLK100MHZ(CLK100MHZ), .RESET(reset), .TXEN(isTX&!empty), .DATA(tx_data), .TXD(TXD), .DONE(tx_done));

endmodule

