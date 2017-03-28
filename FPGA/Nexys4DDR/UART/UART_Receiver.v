//UART Receiver
//Data Framing: 1 START BIT + DATA_WIDTH + 1 STOP BIT

`timescale 1ns/100ps

module UART_RX #(
	parameter DATA_WIDTH = 8,
	parameter baud_count = 868
)(
	input wire CLK100MHZ,
	input wire RESET, 
	input wire RXEN, 
	input wire RXD,
	output wire [DATA_WIDTH-1:0] DATA,
	output wire DONE
);


reg rDONE;
reg [DATA_WIDTH-1:0] rDATA;
reg [9:0] counter;
reg [5:0] state;
reg [3:0] i;

assign DATA = rDATA;
assign DONE = rDONE;

localparam
	RX_IDLE 		= 6'b000001,
	RX_START		= 6'b000010,
	RX_RECEIVING	= 6'b000100,
	RX_STOP			= 6'b001000,
	RX_DONE			= 6'b010000,
	RX_END			= 6'b100000;

always @ (posedge CLK100MHZ, posedge RESET)
begin
	if (RESET)
	begin
		state <= RX_IDLE;
		
		rDONE <= 1'b0;
		rDATA <= 1'd0;
		counter <= 1'b0;
	end
	
	else if (RXEN)
	begin
		case (state)
		
			RX_IDLE: //Looking for active low start bit
			begin
				if (RXD == 1'b0)
				begin
					state <= RX_START;
					
					counter <= counter + 1'b1;
					i <= 1'b0;
				end
			end
			
			RX_START:
			begin
				if (counter == baud_count - 1'b1)
				begin
					state <= RX_RECEIVING;
					
					counter <= 1'b0;
				end
				else
					counter <= counter + 1'b1;
			end
			
			
			RX_RECEIVING: //Receiving all data bits.
			begin
				if (counter == 216) //Record data at 1/4 of the sampling period. 
					rDATA[i] <= RXD;
					
				if (counter == baud_count - 1)
				begin
					if (i == DATA_WIDTH - 1)
						state <= RX_STOP;
					else
						i <= i + 1'b1;
						
					counter <= 1'd0;	
				end
				else
					counter <= counter + 1'b1;
			end
			
			RX_STOP:
			begin
				if (counter == baud_count - 1'b1)
				begin
					counter <= 1'd0;
					state <= RX_DONE;
				end
				else
					counter <= counter + 1'b1;
			end
			
			RX_DONE:
			begin
				state <= RX_END;
				rDONE <= 1'b1;
			end
			
			RX_END:
			begin
				state <= RX_IDLE;
				rDONE <= 1'b0;
			end
		
		endcase
	
	end

end

endmodule