// Diandian Chen, April 2018
//
// This is a 256-bit grouper for collecting bytes from UART and make up 256-bit data for DNN input. Here the grouper simply
// grabs bytes from UART and update its 256-bit output once a new byte is available. We don't need to worry too much about
// whether simple-minded design as UART is too slow even compared
// to 15MHz clock used to double synchronize group_ready signal for DNN, and DNN always have enough time to latch this 256-bit
// data before grouper makes any change to it.
// For one image input into DNN input layer, it has 784 pixels, each pixel made up with 8 bits. So in total one image has 784
// * 8 = 6272 valid bits. 6272 = 256 * 24 + 128, so after 24 sets of 256-bit output data, we should collect 128 bits more and
// fill the rest 128 bits with 0 for a valid image input to DNN.

`timescale 1ns/10ps

module grouper_256(
	input clk,
	input rst,
	input [7:0] data_in,			// Byte input from UART RX
	input w_en,						// Write enabled when new input byte is valid
	output reg ready,				// Output ready when new 256 bits have been collected
	output reg [255:0] data_out		// 256-bit output
	);

	reg [4:0] counter;				// Counts how many bytes have been collected
	reg [4:0] counter_image_cycle;	// Counts how many 256-bit output have been sent
	reg [255:0] data_collected;

	always @(posedge clk)
	if (rst)
	begin
		data_out <= 0;
		data_collected <= 0;
		counter <= 0;
		counter_image_cycle <= 0;
		ready <= 0;
	end
	else
	begin
		if (w_en)
		begin
			counter <= counter + 1;
			case (counter)			// Simple-minded state machine for collecting 256 bits
				0:	
				begin
					data_collected[255:248] <= data_in;
					ready <= 0;
				end
				1:	data_collected[247:240] <= data_in;
				2:	data_collected[239:232] <= data_in;
				3:	data_collected[231:224] <= data_in;
				4:	data_collected[223:216] <= data_in;
				5:	data_collected[215:208] <= data_in;
				6:	data_collected[207:200] <= data_in;
				7:	data_collected[199:192] <= data_in;
				8:	data_collected[191:184] <= data_in;
				9:	data_collected[183:176] <= data_in;
				10:	data_collected[175:168] <= data_in;
				11:	data_collected[167:160] <= data_in;
				12:	data_collected[159:152] <= data_in;
				13:	data_collected[151:144] <= data_in;
				14:	data_collected[143:136] <= data_in;
				15:	
				begin
					data_collected[135:128] <= data_in;
					if (counter_image_cycle == 24)		// When 24 256-bit data have been sent, only 128 bits more need to be collected for current image
					begin
						counter_image_cycle <= 0;
						counter <= 0;
						data_out[255:136] <= data_collected[255:136];
						data_out[135:128] <= data_in;
						data_out[127:0] <= 0;
						ready <= 1;
					end
				end
				16:	data_collected[127:120] <= data_in;
				17:	data_collected[119:112] <= data_in;
				18:	data_collected[111:104] <= data_in;
				19:	data_collected[103:96] <= data_in;
				20:	data_collected[95:88] <= data_in;
				21:	data_collected[87:80] <= data_in;
				22:	data_collected[79:72] <= data_in;
				23:	data_collected[71:64] <= data_in;
				24:	data_collected[63:56] <= data_in;
				25:	data_collected[55:48] <= data_in;
				26:	data_collected[47:40] <= data_in;
				27:	data_collected[39:32] <= data_in;
				28:	data_collected[31:24] <= data_in;
				29:	data_collected[23:16] <= data_in;
				30:	data_collected[15:8] <= data_in;
				31:	
				begin					// New 256 bits have been collected, output ready signal and increment counter for 256-bit output
					data_collected[7:0] <= data_in;
					data_out[255:8] <= data_collected[255:8];
					data_out[7:0] <= data_in;
					counter_image_cycle <= counter_image_cycle + 1;
					ready <= 1;							
				end
			endcase
		end
	end

endmodule