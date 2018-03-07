`timescale 1ns/10ps

module grouper(
	input clk,
	input rst,
	input [7:0] data_in,
	input w_en,
	output reg ready,
	output reg [127:0] data_out
	);

	reg [3:0] counter;

	always @(posedge clk)
	if (rst)
	begin
		data_out <= 0;
		counter <= 0;
		ready <= 0;
	end
	else
	begin
		if (w_en)
		begin
			case (counter)
				0:	
				begin
					data_out[127:120] <= data_in;
					ready <= 0;
				end
				1:	data_out[119:112] <= data_in;
				2:	data_out[111:104] <= data_in;
				3:	data_out[103:96] <= data_in;
				4:	data_out[95:88] <= data_in;
				5:	data_out[87:80] <= data_in;
				6:	data_out[79:72] <= data_in;
				7:	data_out[71:64] <= data_in;
				8:	data_out[63:56] <= data_in;
				9:	data_out[55:48] <= data_in;
				10:	data_out[47:40] <= data_in;
				11:	data_out[39:32] <= data_in;
				12:	data_out[31:24] <= data_in;
				13:	data_out[23:16] <= data_in;
				14:	data_out[15:8] <= data_in;
				15:	
				begin
					data_out[7:0] <= data_in;
					ready <= 1;
				end
			endcase
			counter <= counter + 1;
		end
	end

endmodule
