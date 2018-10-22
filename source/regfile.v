module gp_regfile(
	input clk,
	input [4:0] saddr, taddr, daddr,
	output [31:0] rs, rt,
	input [31:0] rd,
	input we
	);

	reg [31:0] rfile [31:0];
	// read
	assign rs = saddr == 0 ? 0 : rfile[saddr];
	assign rt = taddr == 0 ? 0 : rfile[taddr];

	//write
	always @(posedge clk) begin
		if (we && daddr != 0)
			rfile[daddr] <= rd;
	end
endmodule

module fp_regfile(
	input clk,
	input [4:0] saddr, taddr, daddr,
	output [31:0] fs, ft,
	input [31:0] fd,
	input we
	);

	reg [31:0] rfile [31:0];

	assign fs = rfile[saddr];
	assign ft = rfile[taddr];

	always @(posedge clk) begin
		if (we)
			rfile[daddr] <= fd;
	end
endmodule
