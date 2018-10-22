`timescale 1 ns / 100 ps
module tb_regfile();
	reg clk;
	reg [4:0] saddr,taddr,daddr;
	reg [31:0] rwdata;
	wire [31:0] rrdata1,rrdata2;
	reg [31:0] fwdata;
	wire [31:0] frdata1,frdata2;
	reg we;

	gp_regfile gpr(clk,saddr,taddr,daddr,rrdata1,rrdata2,rwdata,we);

	fp_regfile fpr(clk,saddr,taddr,daddr,frdata1,frdata2,fwdata,we);

	initial begin
		clk <= 0;
		we <= 0;
		saddr <= 0;
		taddr <= 1;
		daddr <= 0;
		rwdata <= 7;
		fwdata <= 15;
	end

	always begin
		#10 clk <= ~clk;
	end

	always begin
		#20 daddr <= 1;
				we <= 1;
		#20 daddr <= 2;
				we <= 0;
		#20 daddr <= 3;
				we <= 1;
		#20 daddr <= 4;
				saddr <= 1;
				taddr <= 2;
	end


endmodule
