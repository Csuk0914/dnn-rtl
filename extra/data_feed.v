//this is a module co-work with the DRP sparse neuron network
//this module store all the data used to train the network.
//data will be chosen randomly, and will be sent to DRP network base on the timing sequence.

`timescale 1ns/100ps

module data_feed #(
	parameter cpc = 6, //clocks per cycle block = Weights/parallelism + 2.
	parameter num = 8, //the number of training data.
	parameter in = 16, //the neuron number for the input layer
	parameter out = 4 //the neuron number for the output layer
)(
	input clk, 
	input reset, //active high 
	output [in/(cpc-2)-1:0]act, 
	output [out/(cpc-2)-1:0]y
);
	
	reg [in+out-1:0] mem[num-1:0];
	reg [in+out-1:0] data_out;
	reg [$clog2(cpc)-1:0] c;
	reg [$clog2(num)-1:0]address;
	wire [in-1:0] act_raw;
	wire [out-1:0] y_raw;

	//memory stores all the training data(activaion, ideal output).
	//a set of train data is store in one address. 
	//the first n/(cpc-2) bits are activation. then p/(cpc-2) bits y.
	always @(posedge clk)
	begin
		if (!reset)
			data_out = mem[address];
	end

	mux #(.width(out/(cpc-2)), 
		.N(cpc-2)) mux0
		(data_out[out-1:0], c[$clog2(cpc-2)-1:0], y);

	mux #(.width(in/(cpc-2)), 
		.N(cpc-2)) mux1
		(data_out[in+out-1:out], c[$clog2(cpc-2)-1:0], act);

	always @(posedge clk)
	begin
		if (reset)
			c <= cpc-3;
		else if (cpc == 5)
			c <= 0;
		else 
			c <= c + 1;
	end

	always @(clk)
	address = $random;//need a synthesizable solution  

	initial begin
		mem[0] = {16'h000f, 4'b0001};
		mem[1] = {16'h00f0, 4'b0010}; 
		mem[2] = {16'h0f00, 4'b0100}; 
		mem[3] = {16'hf000, 4'b1000}; 
		mem[4] = {16'hfff0, 4'b1110}; 
		mem[5] = {16'hff0f, 4'b1101}; 
		mem[6] = {16'hf0ff, 4'b1011}; 
		mem[7] = {16'h0fff, 4'b0111};
	end
endmodule
