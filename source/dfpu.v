module dFPU (
	input wire clk,
	input wire rstn,
	input wire [3:0] f_ope_data,
	input wire [31:0] f_in1_data,
	input wire [31:0] f_in2_data,
	output reg f_in_rdy,
	input wire f_in_vld,	

	output wire [31:0] f_out_data,
	input wire f_out_rdy,
	output reg f_out_vld,	

	output wire [2:0] f_err);
	
	reg [1:0] state;

	assign f_out_data = f_out_vld ? 1 : 0;
	assign f_err = 0;

	always @(posedge clk) begin
		if (~rstn) begin
			f_in_rdy <= 0;
			f_out_vld <= 0;
			state <= 2'b00;
		end else if (state == 2'b00) begin
			f_in_rdy <= 1;
			state <= 2'b01;
		end else if (state == 2'b01) begin
			if (f_in_rdy && f_in_vld) begin
				f_in_rdy <= 0;
				state <= 2'b10;
			end
		end else if (state == 2'b10) begin
			f_out_vld <= 1;
			state <= 2'b11;
		end else if (state == 2'b11) begin
			if(f_out_vld && f_out_rdy) begin
				f_out_vld <= 0;
				state <= 2'b00;
			end
		end else begin
			state <= 2'b00;
			f_in_rdy <= 0;
			f_out_vld <= 0;
		end
	end

endmodule

