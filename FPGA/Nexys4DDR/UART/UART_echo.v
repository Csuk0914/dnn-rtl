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
assign reset = SW0;
assign isRX = SW1;
assign isTX = SW2;

UART_Receiver #(8) URX (.CLK100MHZ(CLK100MHZ), .reset(reset), .isRx(isRX), .RXD(RXD), .data(rx_data), .done(rx_done));
fifo_reg_array_sc UFIFO (.clk(CLK100MHZ), .reset(reset), .data_in(rx_data), .wen(rx_done), .ren(tx_done), .data_out(tx_data), .depth(depth), .empty(empty), .full(full));
UART_Trans #(8) UTX (.CLK100MHZ(CLK100MHZ), .reset(reset), .isTX(isTX&!empty), .data(tx_data), .TXD(TXD), .done(tx_done));

endmodule



module pulse_generator (
	input CLK100MHZ,
	input reset,
	input enable,
	output reg pulse
);

reg [9:0] counter;
parameter baudCount = 868; // For 115200 baud rate: 100e6/115200 = 868   8.68us

always @ (posedge CLK100MHZ, posedge reset) 
begin
	if (reset)
		begin
			pulse <= 0;
			counter <= 0;
		end
	else if (enable)	
		begin
			if (counter == baudCount - 1)
				begin
					pulse <= 1;
					counter <= 0;
				end
			else
				begin
					pulse <= 0;
					counter <= counter + 1;
				end
		end
end
endmodule