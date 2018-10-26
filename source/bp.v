module branch_pred(
	input wire clk,
	input wire rstn,
	input wire is_branch,
	input wire is_b_op,
	output wire is_taken 
	);
	
	reg [1:0] bp2bit;

	assign is_taken = bp2bit[1];

	always @(posedge clk) begin
		if (~rstn) begin
			bp2bit <= 2'b01;
		end else if(is_b_op) begin
			if (is_branch) begin
				if (bp2bit != 2'b11) begin
					bp2bit <= bp2bit + 1;
				end
			end else begin
				if (bp2bit != 2'b00) begin
					bp2bit <= bp2bit - 1;
				end				
			end
		end
	end
	
endmodule
