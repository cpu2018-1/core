module loopback (
	input wire clk,
	input wire rstn,

	input wire [7:0] io_in_data,
	output reg io_in_rdy,
	input wire io_in_vld,
	
	(* mark_debug = "true" *) output reg [7:0] io_out_data,
	input wire io_out_rdy,
	output reg io_out_vld,

	input wire [4:0] io_err);

	(* mark_debug = "true" *) reg [2:0] loop_state;

	always @(posedge clk) begin
		if (~rstn) begin
			io_in_rdy <= 0;
			io_out_vld <= 0;
			loop_state <= 0;
		end else if (loop_state == 0) begin
			io_in_rdy <= 1;
			loop_state <= 1;
		end else if (loop_state == 1 && io_in_rdy && io_in_vld) begin
			io_in_rdy <= 0;
			io_out_data <= io_in_data;
			io_out_vld <= 1;
			loop_state <= 2;
		end else if (loop_state == 2 && io_out_rdy && io_out_vld) begin
			io_out_vld <= 0;
			loop_state <= 0;
		end
	end
endmodule
