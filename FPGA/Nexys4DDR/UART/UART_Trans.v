//UART TRANSMITTER
//Data Framing: 1 START BIT + DATA_WIDTH + 1 STOP BIT

`timescale 1ns/100ps

module UART_TX #(
	parameter DATA_WIDTH = 8,
	parameter baud_count = 868
)(
	input wire CLK100MHZ,
	input wire RESET, 
	input wire TXEN, 
	input wire [DATA_WIDTH-1:0] DATA,
	output wire TXD,
	output wire DONE
);



reg rTXD, rDONE;
reg [3:0] i;
reg [9:0] counter;
reg [DATA_WIDTH+1:0] dout;
reg [3:0] state;

assign TXD 	= rTXD;
assign DONE = rDONE;

localparam
	TX_IDLE 	= 4'b0001,
	TX_SENDING	= 4'b0010,
	TX_DONE		= 4'b0100,
	TX_END		= 4'b1000;
	
	
always @ (posedge CLK100MHZ, posedge RESET)
begin
	if (RESET)
	begin
		state	<= TX_IDLE;
		
		rTXD	<= 1'b1;
		rDONE	<= 1'b0;
		dout	<= 10'd0;
	end
	
	else if (TXEN)
	begin
		case (state)
			
			TX_IDLE:
			begin
				state <= TX_SENDING;
				
				dout <= {1'b1, DATA, 1'b0};
				i <= 0;
				counter	<= 10'b0;
			end
			
			TX_SENDING: //Sending the entire data packet, including start bit and stop bit.
			begin
				if (counter == baud_count-1)
				begin
					counter <= 10'b0;
					
					if (i == DATA_WIDTH+1) 
						state <= TX_DONE;
					else
						i <= i + 1'b1;					
				end
				else
				begin
					rTXD <= dout[i];
					counter <= counter + 1;
				end
			end
			
			TX_DONE:
			begin
				state <= TX_END;
				rDONE <= 1'b1;
			
			end
			
			TX_END:
			begin
				state <= TX_IDLE;
				rDONE <= 1'b0;
			end
			
		endcase
	
	end

end
endmodule