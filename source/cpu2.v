module cpu2 (
	input wire clk,
	input wire rstn,
	output reg [7:0] err,
	//instr mem
	//write
	output wire [31:0] iw_addra,
	output wire [31:0] iw_dina,
	output wire iw_ena,
	output wire [3:0] iw_wea,
	//read
	output wire [31:0] ir_addrb,
	input wire [31:0] ir_doutb,
	output wire ir_enb,
	//data mem
	output wire [31:0] d_addr,
	output wire [31:0] d_wdata,
	input wire [31:0] d_rdata,
	output wire d_en,
	output wire [3:0] d_we,
	//fpu
	output reg [3:0] f_ope_data,
	output reg [31:0] f_in1_data,
	output reg [31:0] f_in2_data,
	input wire f_in_rdy,
	output reg f_in_vld,

	input wire [31:0] f_out_data,
	output reg f_out_rdy,
	input wire f_out_vld,

	input wire [2:0] f_err,
	//IO
	input wire [7:0] io_in_data,
	output reg io_in_rdy,
	input wire io_in_vld,

	output reg [7:0] io_out_data,
	input wire io_out_rdy,
	output reg io_out_vld,

	input wire [4:0] io_err
	);

	localparam st_begin = 3'b000;
	localparam st_normal = 3'b001;
	localparam st_stall = 3'b010;

	localparam err_lost  = 8'b10000000;
	localparam err_carry = 8'b01000000;
	localparam err_io    = 8'b00100000;

	localparam user_irgn = 64;

	reg [31:0] pc;
	reg [1:0] cpu_mode;
	reg [2:0] fpu_state;
	reg [2:0] state;

	wire is_branch;
	wire is_exec_wait;

	//if-df
	wire [31:0] id_instr;
	wire [15:0] id_imm;
	wire [25:0] id_jaddr;
	wire id_ds_is_f;
	wire id_dt_is_f;
	wire [31:0] id_pc_jaddr;
	wire [31:0] id_pc_imm;
	wire id_is_jump;
	reg id_is_en;
	reg [31:0] id_pc;
	//df-ex
	reg [31:0] de_instr;
	reg [31:0] de_pc;
	reg de_ds_is_f;
	reg de_dt_is_f;
	reg de_dd_is_f;
	reg de_ds_is_en;
	reg de_dt_is_en;
	reg [15:0] de_imm;
	reg [31:0] de_ds;
	reg [31:0] de_dt;
	reg [31:0] de_pc_imm;
	reg de_is_jump;
	//ex-wa
	reg [31:0] ew_instr;
	reg [31:0] ew_dd;
	reg ew_dd_is_f;
	reg ew_dd_is_en;
	reg [31:0] ew_wdata;
	//wa-wr
	reg [31:0] ww_instr;
	reg [31:0] ww_dd;
	reg ww_dd_is_f;
	reg ww_dd_is_en;

	//regfile
	wire [31:0] r_ds;
	wire [31:0] r_dt;
	wire [31:0] gp_rs;
	wire [31:0] gp_rt;
	wire [31:0] gp_rd;
	wire gp_we;
	wire [31:0] fp_rs;
	wire [31:0] fp_rt;
	wire [31:0] fp_rd;
	wire fp_we;

	//mem
	wire [31:0] ir_addr_tmp;

	//alu etc
	wire [3:0] alu_ope;
	wire [31:0] exec_ds;
	wire [31:0] exec_dt;
	wire [31:0] exec_dd;
	
	//regfile
	gp_regfile gpr(clk,id_instr[20:16],id_instr[15:11],ww_instr[28:26] == 3'b110 ? 5'b11111 : ww_instr[25:21],gp_rs ,gp_rt,gp_rd,gp_we);
	gp_regfile fpr(clk,id_instr[20:16],ww_instr[15:11],ww_instr[25:21],fp_rs,fp_rt,fp_rd,fp_we);

	assign r_ds = id_ds_is_f ? fp_rs : gp_rs;
	assign r_dt = id_dt_is_f ? fp_rt : gp_rt;
	assign gp_rd = ww_instr[31:26] == 6'b001111 ? d_rdata : ww_dd;
	assign fp_rd = ww_dd;
	assign ge_we = state == st_normal && ww_dd_is_en && ~ww_dd_is_f;
	assign fp_we = state == st_normal && ww_dd_is_en && ww_dd_is_f;

	//instr mem
	assign ir_enb = 1;
	assign ir_addr_tmp = is_exec_wait ? id_pc :
											 is_branch ? de_pc_imm :
											 id_instr[31:26] == 6'b000110 || id_instr[31:26] == 6'b100010 ? id_pc_jaddr :	// J,JR
											 hogeyosoku ? hoge : pc;	// B /////////////////////////////////////////////////
	assign ir_addrb = {ir_addr_tmp[29:0],2'b00};

	assign iw_ena = 1;
	assign iw_addra = exec_ds;
	assign iw_dina = exec_dt;
	assign iw_wea = state == st_normal && de_instr[31:26] == 6'b000000 && de_instr[10:0] == 3 ? 4'b1111 : 4'b0000;

	//data mem
	assign d_en = 1;
	assign d_addr = {ew_dd[29:0],2'b00};
	assign d_wdata = ew_wdata;
	assign d_we = state == st_normal && ew_instr[31:26] == 5'b000111;

	//id
	assign id_instr = state == st_begin ? 0 : ir_doutb;
	assign id_imm = (id_instr[27:26] == 2'b00 || id_instr[31:26] == 6'b001111) ?
										 id_instr[15:0] : {id_instr[25:21],id_instr[10:0]};
	assign id_jaddr = id_instr[25:0];
	assign id_ds_is_f = id_instr[27:26] == 2'b01 && id_instr[1] == 1'b0;
	assign id_dt_is_f = id_instr[27:26] == 2'b01;
	assign id_pc_jaddr = $signed(id_pc) + $signed(id_jaddr);
	assign id_pc_imm = $signed(id_pc) + $signed(id_imm);
	assign id_is_jump = yosoku;///////////////////////////////////////////////////////////////
	
	//alu
	assign alu_ope = de_instr[31:28];
	assign exec_ds = //////// forward
	assign exec_dt = ///////

	always @(posedge clk) begin
		if(~rstn) begin
			pc <= 0;
			cpu_mode <= 0;
			fpu_state <= 0;
			state <= st_begin;
		end else if (state == st_begin) begin
			pc <= pc + 1;
			state <= st_normal;
		end else if (state == st_normal) begin
			if (~is_exec_wait) begin	
				if(is_branch) begin // id_is_en
					id_is_en <= 0;
				end else begin
					id_is_en <= 1;
				end
				if (is_branch) begin // PC
					pc <= de_pc_imm + 1;
				end else if (id_instr[31:26] == 6'b000110)  begin // JAL
					pc <= pc_jaddr + 1;
				end else begin
					pc <= pc + 1;
				end
				// dfetch

				// exec
			end else begin // if is_exec_wait
			end

			// wait <- if stall, here

			// write -> see assign reg_we
		end else if (state == st_stall) begin // FPU, IO
			// wait stage
			if (ew_instr[31:26] == 6'b000011) begin // OUT
				if (io_out_rdy && io_out_vld) begin
					io_out_vld <= 0;
					state <= st_normal;
				end else begin
					ew_dd <= ew_dd;
				end
			end else if (ew_instr[31:26] == 6'b001011) begin // IN
				if (io_in_rdy && io_in_vld) begin
					io_in_rdy <= 0;
					ew_dd <= io_in_data;
					state <= st_normal;
				end else begin
					ew_dd <= ew_dd;
				end
			end else if (ew_instr[31:26] == 6'b000001 && ew_instr[5:2] <= 4'b1011) begin // fpu
				if (fpu_state == 1 && f_in_rdy && f_in_vld) begin
					f_in_vld <= 0;
					f_out_rdy <= 1;
					fpu_state <= 2;
				end if (fpu_state == 2 && f_out_rdy && f_out_vld) begin
					f_out_rdy <= 0;
					ew_dd <= f_out_data;
					fpu_state <= 0;
				end else begin
					ew_dd <= ew_dd;
				end
			end
		end else begin
			err <= err | err_lost;
		end
	end

endmodule
