module cpu3 (
	input wire clk,
	input wire rstn,
	output reg [7:0] err,
	//instr mem
	(* mark_debug = "true" *) output wire [31:0] i_addr,
	(* mark_debug = "true" *) output wire [31:0] i_wdata,
	(* mark_debug = "true" *) input wire [31:0] i_rdata,
	output wire i_en,
	(* mark_debug = "true" *) output wire [3:0] i_we,
	//data mem
	(* mark_debug = "true" *) output wire [31:0] d_addr,
	(* mark_debug = "true" *) output wire [31:0] d_wdata,
	(* mark_debug = "true" *) input wire [31:0] d_rdata,
	output wire d_en,
	(* mark_debug = "true" *) output wire [3:0] d_we,
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

	//mem
	(* mark_debug = "true" *) reg [31:0] i_addr_tmp;

	(* mark_debug = "true" *) reg [31:0] pc;
	reg [2:0] state;


	//if1-if2
	reg [31:0] ii_pc;
	wire [31:0] ii_instr;
	reg ii_is_en;
	//if2-df1
	reg [31:0] id_pc;
	reg [31:0] id_instr;
	reg id_is_en;
	wire id_imm;
	wire id_is_jump;
	//df1-df2
	reg [31:0] dd_pc;
	reg [31:0] dd_instr;
	reg dd_is_en;
	reg [31:0] dd_ds;
	reg [31:0] dd_dt;
	reg [31:0] dd_imm;
	reg dd_ds_is_en;
	reg dd_dt_is_en;
	reg dd_dd_is_en;
	reg dd_is_jump;
	//df2-ex1
	reg [31:0] de_pc;
	reg [31:0] de_instr;
	reg de_is_en;
	reg [31:0] de_ds;
	reg [31:0] de_dt;
	reg [31:0] de_imm;
	reg de_ds_is_en;
	reg de_dt_is_en;
	reg de_dd_is_en;
	reg de_is_jump;
	//ex1-ex2
	reg [31:0] ee_instr;
	reg [31:0] ee_dd;
	reg ee_dd_is_en;
	//ex2-wr
	reg [31:0] ew_instr;
	reg [31:0] ew_dd;
	reg ew_dd_is_en;


	//regfile
	wire [31:0] gp_rs;
	wire [31:0] gp_rt;
	wire [31:0] gp_rd;
	(* mark_debug = "true" *) wire gp_we;

	gp_regfile gpr(clk,id_instr[20:16],id_instr[15:11],ew_instr[25:21],gp_rs,gp_rt,gp_rd,gp_we);
	

	//branch
	wire b_ds_eq_dt;
	wire b_ds_lt_dt;
	wire bp_is_branch;
	wire bp_is_b_op;
	wire bp_is_taken;

	branch_pred bp(clk,rstn,bp_is_branch,bp_is_b_op,bp_is_taken);

	//alu etc
	(* mark_debug = "true" *) wire [2:0] alu_ope;
	(* mark_debug = "true" *) wire [31:0] alu_ds;
	(* mark_debug = "true" *) wire [31:0] alu_dt;
	(* mark_debug = "true" *) wire [31:0] alu_dd;

	alu u_alu(alu_ope,alu_ds,alu_dt,alu_dd);

	//hazard
	wire is_jump_by_reg;
	wire is_branch;
	wire is_exec_wait;
	

	//i mem
	assign i_addr = {pc[29:0],0}; // i_addr_tmp ,2'b00
	assign i_wdata = 0;
	assign i_en = 1'b1;
	assign i_we = 4'b0000;
	//d mem
	assign d_addr = {de_ds[29:0],2'b0};
	assign d_wdata = de_dt;
	assign d_en = 1'b1;
	assign d_we = de_instr[31:26] == 6'b000111 ? 4'b1111 : 4'b0000;
	
	//ii
	assign ii_instr = i_rdata;
	//id
	assign id_imm = 0;//////////////////////
	assign id_is_jump = 0;/////////////////

	//regfile
	assign gp_we = ew_dd_is_en;
	
	//branch
	assign b_ds_eq_dt = $signed(de_ds) == $signed(de_dt);
	assign b_ds_lt_dt = $signed(de_ds) < $signed(de_dt);
	assign bp_is_branch = is_branch;
	assign bp_is_b_op = de_instr[28:26] == 3'b010 && de_instr[31] == 1'b1;

	//alu
	assign alu_ope = de_instr[31:29];
	assign alu_ds = de_ds;
	assign alu_dt = de_dt;

	//hazard
	assign is_jump_by_reg = de_instr[31:26] == 6'b001010 || de_instr[31:26] == 6'b001110;
	assign is_branch = (de_instr[31:26] == 6'b100010 && b_ds_eq_dt) ||
										 (de_instr[31:26] == 6'b101010 && ~b_ds_eq_dt) ||
										 (de_instr[31:26] == 6'b110010 && b_ds_lt_dt) ||
										 (de_instr[31:26] == 6'b111010 && (b_ds_eq_dt || b_ds_lt_dt)) ||
										 is_jump_by_reg;

	assign is_exec_wait = (ee_dd_is_en && dd_ds_is_en && dd_instr[20:16] != 5'b0 &&
													dd_instr[20:16] == ee_instr[25:21]) ||
												(ee_dd_is_en && dd_dt_is_en && dd_instr[15:11] != 5'b0 &&
													dd_instr[15:11] == ee_instr[25:21]);
	



	always @(posedge clk) begin
		if(~rstn) begin
			err <= 0;
			io_in_rdy <= 0;
			io_out_data <= 0;
			io_out_vld <= 0;
			pc <= 0;
			state <= st_begin;
			ii_pc <= 0;
			ii_is_en <= 0;
			id_pc <= 0;
			id_instr <= 0;
			id_is_en <= 0;
			dd_pc <= 0;
			dd_instr <= 0;
			dd_is_en <= 0;
			dd_ds <= 0;
			dd_dt <= 0;
			dd_imm <= 0;
			dd_ds_is_en <= 0;
			dd_dt_is_en <= 0;
			dd_dd_is_en <= 0;
			dd_is_jump <= 0;
			de_pc <= 0;
			de_instr <= 0;
			de_is_en <= 0;
			de_ds <= 0;
			de_dt <= 0;
			de_imm <= 0;
			de_ds_is_en <= 0;
			de_dt_is_en <= 0;
			de_dd_is_en <= 0;
			dd_is_jump <= 0;
			ee_instr <= 0;
			ee_dd <= 0;
			ee_dd_is_en <= 0;
			ew_instr <= 0;
			ew_dd <= 0;
			ew_dd_is_en <= 0;
		end else if (state == st_begin) begin
			pc <= pc + 1;
			ii_is_en <= 1;
			state <= st_normal;
		end else if (state == st_normal) begin
			if (~is_exec_wait) begin
				if(is_jump_by_reg) begin // この辺の数字はうそっぽい　よく考えろ
					pc <= de_ds + 1;
				end else if(is_branch && ~de_is_jump) begin
					pc <= de_imm + 1;
				end else if(~is_branch && de_is_jump) begin
					pc <= de_pc + 2;
				end else if(ii_instr[31:26] == 6'b000010 || ii_instr[31:26] == 6'b000110) begin
					pc <= ii_instr[15:0];
				end else if(id_is_jump) begin
					pc <= id_imm + 1;
				end else if(is_branch && de_is_jump) begin
					pc <= id_pc + 2;
				end else begin
					pc <= pc + 1;
				end

/*				i_addr_tmp <= is_exec_wait || state == st_stall ? id_pc ://////////////////
				                  is_jump_by_reg ? de_ds :
				                  is_branch && ~de_is_jump ? de_imm :
				                  ~is_branch && de_is_jump ? de_pc + 1 :
				                  id_instr[31:26] == 6'b000010 || id_instr[31:26] == 6'b000110 ? id_imm :
				                  id_is_jump ? id_imm :
				                  is_branch && de_is_jump ? id_pc + 1 : pc; ///////////////////
*/
				//id 
				id_is_en <= ii_is_en;
				id_instr <= ii_instr;
				id_pc <= ii_pc;

				//dd
				dd_ds <= gp_rs;
				dd_dt <= gp_rt;
				dd_pc <= id_pc;
				dd_instr <= id_instr;
				dd_is_en <= id_is_en;
				dd_imm <= id_imm;
				dd_ds_is_en <= 1;/////////
				dd_dt_is_en <= 1;/////////////////
				
				//de
				if(id_is_en && ~((is_branch && ~de_is_jump) || (~is_branch && de_is_jump))) begin
					de_instr <= id_instr;
					de_pc <= id_pc;
					de_is_en <= id_is_en;
					de_ds_is_en <= dd_ds_is_en;
					de_dt_is_en <= dd_dt_is_en;
					de_dd_is_en <= 1; //////
					de_imm <= id_imm;
					de_is_jump <= id_is_jump;
				end else begin
				///
				end
				if(ew_dd_is_en && id_instr[20:16] != 5'b0 && id_instr[20:16] == ew_instr[25:21]) begin
					de_ds <= ew_dd;
				end else begin
					de_ds <= dd_ds;
				end
				if(ew_dd_is_en && id_instr[15:11] != 5'b0 && id_instr[15:11] == ew_instr[25:21]) begin
					de_dt <= ew_dd;
				end else begin
					de_dt <= dd_dt;
				end

				//ee usodesu
				ee_instr <= de_instr;
				ee_dd_is_en <= de_dd_is_en;
				case(de_instr[27:26])
					2'b00: begin
									ee_dd <= alu_dd;
								end
					2'b10: begin
									ee_dd <= de_pc + 1;
								end
					2'b11: begin
									if(de_instr[31:26] == 6'b001111) begin //LW
										ee_dd <= d_rdata;
									end else if(de_instr[31:26] == 6'b000111) begin //SW
										ee_dd <= alu_dd;
									end else begin
										ee_dd <= alu_dd;
									end
								end
					2'b01: begin
									ee_dd <= alu_dd;
									state <= st_stall;
								end
				endcase
			end
			ew_instr <= ee_instr;
			ew_dd <= ee_dd;
			ew_dd_is_en <= ee_dd_is_en;

		end else if (state == st_stall) begin // FPU sync, IO
			
		end else begin
			err <= err | err_lost;
		end
	end

endmodule
