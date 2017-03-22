`timescale 1ns/100ps

module UART_Control(
	input wire CLK100MHZ,
	input wire SW0, 
	input wire SW1, 
	output wire UART_RXD_OUT
);

// Variable Declaration
reg [4:0] i;
reg [1:0] state;
reg isTX;

reg [7:0] data;
wire reset;
wire start;
wire done;

assign reset = SW0;
assign start = SW1;

wire [7:0] mem [0:3];
assign mem[0]  = 8'hA1;
assign mem[1]  = 8'hB2;
assign mem[2]  = 8'hC3;
assign mem[3]  = 8'hD4;

parameter data_len = 4;


UART_Trans M1 (.CLK100MHZ(CLK100MHZ), .reset(reset), .isTX(isTX), .data(data), .UART_RXD_OUT(UART_RXD_OUT), .done(done));


localparam
	Qtrans	= 2'b01,
	Qend	= 2'b10;

always @ (posedge CLK100MHZ, posedge reset) 
begin
	if (reset)
		begin
			data <= 0;
			i <= 0;
		    state <= Qtrans;
            isTX <= 0;
		end
	else if (start)
		begin
			case(state)
			
				Qtrans:
					begin
						if (i == data_len)
							begin
								state <= Qend;
							end
						else
							if (done)
								begin
									isTX <= 1'b0;
									i <= i + 1'b1;
															
								end
							else
								begin
									data <= mem[i];
									isTX <= 1'b1;
								
								end
				
					end
				Qend:
					state <= Qend;
		
			endcase
		end







end

endmodule