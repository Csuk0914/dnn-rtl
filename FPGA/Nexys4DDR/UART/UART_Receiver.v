module UART_Receiver #(
	parameter DATA_WIDTH = 8
)(
	input wire CLK100MHZ,
	input wire reset, 
	input wire isRx, 
	input wire RXD,
	output wire [DATA_WIDTH-1:0] data,
	output reg done
);

wire en;


reg [4:0] state;
reg pulse_enable;
reg [7:0] counter;
reg [4:0] i;
reg [DATA_WIDTH-1:0] D,Dout;
assign data = Dout;

localparam
	Qini 	= 5'b00001,
	Qstart	= 5'b00010,
	Qrx		= 5'b00100,
	Qstop	= 5'b01000,
	Qdone 	= 5'b10000;
	
pulse_generator Mp(.CLK100MHZ(CLK100MHZ), .reset(reset), .enable(pulse_enable), .pulse(en));


always @ (posedge CLK100MHZ, posedge reset)
begin
	if (reset)
		begin
			state <= Qini;
			done <= 0;
			pulse_enable <= 0;
			D <= 0;
		end
	else if (isRx)
		case (state)
			Qini:
			begin
				if (RXD == 1'b0) //Detected start bit.
					begin
						state <= Qstart;
						pulse_enable = 1;
						i <= 0;
						counter <= 0;
						D <= 0;

					end
			end
			
			Qstart:
			begin
				if (en)
					state <= Qrx;
			end
			
			Qrx:
			begin
				if (en)
					begin
						if (i == DATA_WIDTH-1)
							state <= Qstop;
						else 
							begin
								i <= i + 1;
								counter <= 0;
							end
					end
				else 
					begin //Record the bit at 1/4 of the sampling period
						counter <= counter + 1;
						if (counter == 217)
							begin
								D[i] <= RXD;
							end
			
					end
			end
		
			Qstop:
			begin
				if (en)
					begin
						state <= Qdone;
						done <= 1'b1;
						Dout <= D;
					end
			end
			
			Qdone:
			begin
				state<= Qini;
				done <= 1'b0;
			end
		
		endcase
end

endmodule