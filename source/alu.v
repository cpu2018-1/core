module alu (
	input wire [2:0] ope,
	input wire [31:0] ds,
	input wire [31:0] dt,
	output wire [31:0] dd
	);
	
	wire [31:0] lui_d;
	wire [31:0] add_d;
	wire [31:0] sub_d;
	wire [31:0] sll_d;
	wire [31:0] srl_d;
	wire [31:0] sra_d;
	

	assign lui_d = {dt[15:0],ds[15:0]};
	assign add_d = $signed(ds) + $signed(dt);
	assign sub_d = $signed(ds) - $signed(dt);
	assign sll_d = ds << dt[4:0];
	assign srl_d = ds >> dt[4:0];
	assign sra_d = ds >>> dt[4:0];

	assign dd = ope == 3'b110 ? lui_d :
							ope == 3'b001 ? add_d :
							ope == 3'b010 ? sub_d :
							ope == 3'b011 ? sll_d :
							ope == 3'b100 ? srl_d :
							ope == 3'b101 ? sra_d : 32'b0;

endmodule
