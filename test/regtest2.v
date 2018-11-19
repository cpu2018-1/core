module reg test2(
	input wire clk,
	input wire rstn,
	input wire [31:0] instr,
	output reg [7:0] led
	);
	reg [31:0] regfile [63:0];
	reg [2:0] state;

	reg [31:0] rdata [3:0];
	reg [31:0] wdata [5:0];

	always @(posedge clk) begin
		if(~rstn) begin
			led <= 0;
			state <= 0;
		end else if (state == 0) begin
			rdata[0] <= regfile[instr[31:26]];
			rdata[1] <= regfile[instr[30:25]];
			rdata[2] <= regfile[instr[29:24]];
			rdata[3] <= regfile[instr[28:23]];
			state <= 1;
		end	else if (state == 1) begin
			wdata[0] <= rdata[instr[18:17]] + rdata[instr[6:5]];
			wdata[1] <= rdata[instr[17:16]] + rdata[instr[5:4]];
			wdata[2] <= rdata[instr[16:15]] + rdata[instr[4:3]];
			wdata[3] <= rdata[instr[15:14]] + rdata[instr[3:2]];
			wdata[4] <= rdata[instr[14:13]] + rdata[instr[2:1]];
			wdata[5] <= rdata[instr[13:12]] + rdata[instr[1:0]];
			state <= 2;
		end else if (state == 2) begin
			regfile[instr[12:7]] <= wdata[0];
			regfile[instr[17:12]] <= wdata[1];
			regfile[instr[16:11]] <= wdata[2];
			regfile[instr[15:10]] <= wdata[3];
			regfile[instr[14:9]] <= wdata[4];
			regfile[instr[13:8]] <= wdata[5];
			led <= wdata[0][7:0];
			state <= 0;
		end else begin
			led <= 1;
		end
	end
	
	integer i;
	initial begin
		for(i=0;i<64;i=i+1) begin
			regfile[i] <= i;
		end
	end
endmodule
