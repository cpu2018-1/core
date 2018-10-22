`timescale 1 ns / 100 ps
module tb_cpu0();
	// cpu pin
	reg clk;
	reg rstn;
	wire [7:0] err;

	wire [31:0] i_addr;
	wire [31:0] i_wdata;
	reg [31:0] i_rdata;
	wire i_en;
	wire [3:0] i_we;

	wire [31:0] d_addr;
	wire [31:0] d_wdata;
	reg [31:0] d_rdata;
	wire d_en;
	wire [3:0] d_we;

	wire [3:0] f_ope_data;
	wire [31:0] f_in1_data;
	wire [31:0] f_in2_data;
	wire f_in_rdy;
	wire f_in_vld;
	wire [31:0] f_out_data;
	wire f_out_rdy;
	wire f_out_vld;
	wire [2:0] f_err;

	dFPU dfunit(
		clk,
		rstn,
		f_ope_data,
		f_in1_data,
		f_in2_data,
		f_in_rdy,
		f_in_vld,
		f_out_data,
		f_out_rdy,
		f_out_vld,
		f_err);


	wire [7:0] io_in_data;
	wire io_in_rdy;
	wire io_in_vld;
	wire [7:0] io_out_data;
	wire io_out_rdy;
	wire io_out_vld;
	wire [4:0] io_err;

	wire [7:0] red;
	
	dIOcontroller dio(
		clk,
		rstn,
		red,
		io_in_data,
		io_in_rdy,
		io_in_vld,
		io_out_data,
		io_out_rdy,
		io_out_vld,
		io_err);

	
	cpu core(
		clk,
		rstn,
		err,
		i_addr,
		i_wdata,
		i_rdata,
		i_en,
		i_we,
		d_addr,
		d_wdata,
		d_rdata,
		d_en,
		d_we,
		f_ope_data,
		f_in1_data,
		f_in2_data,
		f_in_rdy,
		f_in_vld,
		f_out_data,
		f_out_rdy,
		f_out_vld,
		f_err,
		io_in_data,
		io_in_rdy,
		io_in_vld,
		io_out_data,
		io_out_rdy,
		io_out_vld,
		io_err);

		reg [31:0] imem [31:0];
		reg [31:0] dmem [7:0];
		reg [7:0] outputs;

	//clk
	initial begin
		clk <= 0;
	end
	always begin
	 #1 clk <= ~clk;
	end
	// rstn
	initial begin
			rstn <= 0;
	 #2	rstn <= 1;
	end
	//memory
	initial begin
	   imem[0] <= 32'b00100000001000000000000000000111;
	   imem[1] <= 32'b00100000010000000000000000000001;
	   imem[2] <= 32'b00011100000000100000100000000000;
	   imem[3] <= 32'b00111100011000100000000000000000;
	   imem[4] <= 32'b00001100000000110000000000000000;
	   imem[5] <= 32'b00011000000000000000000000000000;
	   imem[6] <= 32'b0;
     imem[7] <= 32'b0;
	   imem[8] <= 32'b0;
	   imem[9] <= 32'b0;
	   imem[10] <= 32'b0;
	   imem[11] <= 32'b0;
	   imem[12] <= 32'b0;
	   imem[13] <= 32'b0;
	   imem[14] <= 32'b0;
	   imem[15] <= 32'b0;
	   
		
		dmem[0] <= 0;
		dmem[1] <= 0;
		dmem[2] <= 0;
		dmem[3] <= 0;
		dmem[4] <= 0;
		dmem[5] <= 0;
		dmem[6] <= 0;
		dmem[7] <= 0;
	end
	always @(posedge clk) begin
		i_rdata <= imem[i_addr>>2];
		d_rdata <= dmem[d_addr>>2];
		if (i_we != 0) begin
			imem[i_addr>>2] <= i_wdata;
		end
		if (d_we != 0) begin
			dmem[d_addr>>2] <= d_wdata;
		end
	end

	//IO
/*
	initial begin
		io_in_data <= 5;
		io_in_vld <= 1;
		io_out_rdy <= 1;
	end
	always @(posedge clk) begin
		if(io_out_rdy && io_out_vld) begin
			outputs <= io_out_data;
		end
	end
*/
endmodule
