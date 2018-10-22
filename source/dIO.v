module dIOcontroller (
	input clk,
	input rstn,
	output reg [7:0] red,

	output reg [7:0] io_in_data,
	input wire io_in_rdy,
	output wire io_in_vld,

	input wire [7:0] io_out_data,
	output wire io_out_rdy,
	input wire io_out_vld,

	output reg [4:0] io_err);

	assign io_in_vld = 1;
	assign io_out_rdy = 1;

	always @(posedge clk) begin
		if (~rstn) begin
			red <= 0;
			io_err <= 0;
			io_in_data <= 5;
		end else begin
			if(io_out_rdy && io_out_vld) begin
				red <= io_out_data;		
			end
			if(io_in_rdy && io_in_vld) begin
				io_in_data <= io_in_data + 1;
			end
		end
	end

endmodule
