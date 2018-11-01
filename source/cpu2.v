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

	(* mark_debug = "true" *) reg [31:0] pc;
	reg [1:0] cpu_mode;
	reg [2:0] fpu_state;
	reg [2:0] state;

	//hazard
	(* mark_debug = "true" *) wire jump_by_reg;
	(* mark_debug = "true" *) wire is_branch;
	(* mark_debug = "true" *) wire is_exec_wait;
	wire is_cmu;
	wire is_cms;

	//if-df
	(* mark_debug = "true" *) wire [31:0] id_instr;
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
	(* mark_debug = "true" *) reg [31:0] de_instr;
	reg [31:0] de_pc;
	reg de_ds_is_f;
	reg de_dt_is_f;
	reg de_ds_is_en;
	reg de_dt_is_en;
	reg [15:0] de_imm;
	reg [31:0] de_ds;
	reg [31:0] de_dt;
	reg [31:0] de_pc_imm;
	reg de_is_jump;
	//ex-wa
	(* mark_debug = "true" *) reg [31:0] ew_instr;
	reg [31:0] ew_dd;
	reg ew_dd_is_f;
	reg ew_dd_is_en;
	reg [31:0] ew_wdata;
	//wa-wr
	(* mark_debug = "true" *) reg [31:0] ww_instr;
	reg [31:0] ww_dd;
	reg ww_dd_is_f;
	reg ww_dd_is_en;

	wire [31:0] ww_dd_rdata;

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
	(* mark_debug = "true" *) wire [31:0] ir_addr_tmp;

	//branch
	wire b_ds_eq_dt;
	wire b_ds_lt_dt;
	wire bp_is_branch;
	wire bp_is_b_op;
	wire bp_is_taken;

	branch_pred bp(clk,rstn,bp_is_branch,bp_is_b_op,bp_is_taken);

	//alu etc
	wire [31:0] exec_ds;
	wire [31:0] exec_dt;
	wire [2:0] alu_ope;
	wire [31:0] alu_ds;
	wire [31:0] alu_dt;
	wire [31:0] alu_dd;

	alu u_alu(alu_ope,alu_ds,alu_dt,alu_dd);

	//debug
	wire test_sig;
	(* mark_debug = "true" *) reg [63:0] dbg_counter;
	
	//regfile
	gp_regfile gpr(clk,id_instr[20:16],id_instr[15:11],ww_instr[25:21],gp_rs ,gp_rt,gp_rd,gp_we);
	gp_regfile fpr(clk,id_instr[20:16],id_instr[15:11],ww_instr[25:21],fp_rs,fp_rt,fp_rd,fp_we);

	assign r_ds = id_ds_is_f ? fp_rs : gp_rs;
	assign r_dt = id_dt_is_f ? fp_rt : gp_rt;
	assign gp_rd = ww_dd_rdata;
	assign fp_rd = ww_dd_rdata;
	assign gp_we = state == st_normal && ww_dd_is_en && ~ww_dd_is_f;
	assign fp_we = state == st_normal && ww_dd_is_en && ww_dd_is_f;

	assign ww_dd_rdata = ww_instr[31:26] == 6'b001111 ? d_rdata : ww_dd;

	//instr mem
	assign ir_enb = 1;
	assign ir_addr_tmp = is_exec_wait || state == st_stall ? id_pc :
											 jump_by_reg ? exec_ds :
											 is_branch && ~de_is_jump ? de_pc_imm :
											 ~is_branch && de_is_jump ? de_pc + 1 :
											 id_instr[31:26] == 6'b000110 || id_instr[31:26] == 6'b100010 ? id_pc_jaddr :	// J,JAL
											 is_cmu ? user_irgn :
											 is_cms ? 0 :
											 id_is_jump ? id_pc_imm :	// B 
											 is_branch && de_is_jump ? id_pc + 1 : pc;
	assign ir_addrb = {ir_addr_tmp[29:0],2'b00};

	assign iw_ena = 1;
	assign iw_addra = exec_ds;
	assign iw_dina = exec_dt;
	assign iw_wea = state == st_normal && de_instr[31:26] == 6'b000000 && de_instr[10:0] == 3 ? 4'b1111 : 4'b0000;

	//data mem
	assign d_en = 1;
	assign d_addr = {ew_dd[29:0],2'b00};
	assign d_wdata = ew_wdata;
	assign d_we = state == st_normal && ew_instr[31:26] == 6'b000111 ? 4'b1111 : 4'b0000;

	//id
	assign id_instr = state == st_begin ? 0 : ir_doutb;
	assign id_imm = (id_instr[27:26] == 2'b00 || id_instr[31:26] == 6'b001111) ?
										 id_instr[15:0] : {id_instr[25:21],id_instr[10:0]};
	assign id_jaddr = id_instr[25:0];
	assign id_ds_is_f = id_instr[27:26] == 2'b01 && id_instr[1] == 1'b0;
	assign id_dt_is_f = id_instr[27:26] == 2'b01;
	assign id_pc_jaddr = $signed(id_pc) + $signed(id_jaddr);
	assign id_pc_imm = $signed(id_pc) + $signed(id_imm);
	assign id_is_jump = bp_is_taken && id_instr[28:26] == 3'b010 && id_instr[31] == 1'b0;
	assign is_cmu = id_instr[31:26] == 6'b0 && id_instr[10:0] == 1;
	assign is_cms = id_instr[31:26] == 6'b0 && id_instr[10:0] == 2;
	
	// hazard
	assign is_exec_wait = ew_dd_is_en &&
												((de_ds_is_en && de_instr[20:16] != 5'b0 && 
														de_instr[20:16] == ew_instr[25:21] && ~(de_ds_is_f ^ ew_dd_is_f)) ||
													(de_dt_is_en && de_instr[15:11] != 5'b0 &&
														de_instr[15:11] == ew_instr[25:21] && ~(de_dt_is_f ^ ew_dd_is_f)));
	assign is_branch =  (de_instr[31:26] == 6'b000010 && b_ds_eq_dt) ||
											(de_instr[31:26] == 6'b001010 && ~b_ds_eq_dt) ||
											(de_instr[31:26] == 6'b010010 && b_ds_lt_dt) ||
											(de_instr[31:26] == 6'b011010 && (b_ds_eq_dt || b_ds_lt_dt)) ||
											jump_by_reg;  // JALR,JR

	assign jump_by_reg = de_instr[31:26] == 6'b001110 || de_instr[31:26] == 6'b101010;  // JALR,JR
											
	assign b_ds_eq_dt = $signed(exec_ds) == $signed(exec_dt);
	assign b_ds_lt_dt = $signed(exec_ds) < $signed(exec_dt);
	assign bp_is_branch = is_branch;
	assign bp_is_b_op = de_instr[28:26] == 3'b010 && de_instr[31] == 1'b0;


	//alu
	assign alu_ope = de_instr[27:26] == 2'b11 ? 3'b001 : de_instr[31:29]; // SW,LW?
	assign alu_ds = exec_ds;
	assign alu_dt = de_instr[28:26] == 3'b100 ? exec_dt : de_imm;
	assign exec_ds = (ww_dd_is_en && (de_instr[20:16] != 5'b0) && (ww_instr[25:21] == de_instr[20:16]) && ~(de_ds_is_f ^ ww_dd_is_f)) ? ww_dd_rdata : de_ds; 
	assign exec_dt = (ww_dd_is_en && (de_instr[15:11] != 5'b0) && (ww_instr[25:21] == de_instr[15:11]) && ~(de_dt_is_f ^ ww_dd_is_f)) ? ww_dd_rdata : de_dt;
	assign test_sig = ~(de_ds_is_f ^ ww_dd_is_f);

	always @(posedge clk) begin
		if(~rstn) begin
			pc <= 0;
			cpu_mode <= 0;
			fpu_state <= 0;
			state <= st_begin;
			err <= 0;
			f_ope_data <= 0;
			f_in1_data <= 0;
			f_in2_data <= 0;
			f_in_vld <= 0;
			f_out_rdy <= 0;
			io_in_rdy <= 0;
			io_out_data <= 0;
			io_out_vld <= 0;
			id_is_en <= 0;
			id_pc <= 0;
			de_instr <= 0;
			de_pc <= 0;
			de_ds_is_f <= 0;
			de_dt_is_f <= 0;
			de_ds_is_en <= 0;
			de_dt_is_en <= 0;
			de_imm <= 0;
			de_ds <= 0;
			de_dt <= 0;
			de_pc_imm <= 0;
			de_is_jump <= 0;
			ew_instr <= 0;
			ew_dd <= 0;
			ew_dd_is_f <= 0;
			ew_dd_is_en <= 0;
			ew_wdata <= 0;
			ww_instr <= 0;
			ww_dd <= 0;
			ww_dd_is_f <= 0;
			ww_dd_is_en <= 0;
			dbg_counter <= 0;
		end else if (state == st_begin) begin
			pc <= pc + 1;
			id_is_en <= 1;
			state <= st_normal;
		end else if (state == st_normal) begin
			if (~is_exec_wait) begin	
//				if((is_branch && ~de_is_jump) || (~is_branch && de_is_jump)) begin // id_is_en
//					id_is_en <= 0;
//				end else begin
					id_is_en <= 1;
//				end
				//PC
				if (jump_by_reg) begin
					pc <= exec_ds + 1;
				end else if (is_branch && ~de_is_jump) begin 
					pc <= de_pc_imm + 1;
				end else if (~is_branch && de_is_jump) begin
					pc <= de_pc + 2;
				end else if (id_instr[31:26] == 6'b000110 || id_instr[31:26] == 6'b100010)  begin // JAL,J
					pc <= id_pc_jaddr + 1;
				end else if(is_cmu) begin
					pc <= user_irgn + 1;
				end else if (is_cms) begin
					pc <= 1;
				end else if (id_is_jump) begin
					pc <= id_pc_imm + 1;
				end else if (is_branch && de_is_jump) begin
					pc <= id_pc + 2;
				end else begin
					pc <= pc + 1;
				end
				id_pc <= ir_addr_tmp;
				// dfetch
				if (id_is_en && ~((is_branch && ~de_is_jump) || (~is_branch && de_is_jump))) begin
					de_instr <= id_instr;
					de_pc <= id_pc;
					de_ds_is_f <= id_ds_is_f;
					de_dt_is_f <= id_dt_is_f;
					de_ds_is_en <= (id_instr[31:26] != 6'b0 && id_instr[27:26] == 2'b0) ||
													(id_instr[28:26] == 3'b010 && id_instr[31] == 1'b0) ||
													id_instr[31:26] == 6'b001110 ||
													id_instr[31:26] == 6'b101010 ||
													id_instr[28:26] == 3'b111 ||
													id_instr[31:26] == 6'b000011 ||
													id_instr[27:26] == 2'b01 ||
													(id_instr[31:26] == 6'b0 && (id_instr[10:0] == 3 || id_instr[10:0] == 5));
					de_dt_is_en <= id_instr[28:26] == 3'b100 ||
													(id_instr[28:26] == 3'b010 && id_instr[31] == 1'b0) ||
													id_instr[31:26] == 6'b000111 ||
													(id_instr[27:26] == 2'b01 && id_instr[5] == 1'b0) ||
													(id_instr[31:26] == 6'b0 && id_instr[10:0] == 3);
					de_imm <= id_imm;
					de_pc_imm <= id_pc_imm;
					de_is_jump <= id_is_jump;
				end else begin
					de_instr <= 0;
					de_pc <= 0;
					de_ds_is_f <= 0;
					de_dt_is_f <= 0;
					de_ds_is_en <= 0;
					de_dt_is_en <= 0;
					de_imm <= 0;
					de_pc_imm <= 0;
					de_is_jump <= 0;
				end
				// forward
				if(ww_dd_is_en && id_instr[20:16] != 5'b0 && id_instr[20:16] == ww_instr[25:21] && ~(id_ds_is_f ^ ww_dd_is_f)) begin
					de_ds <= ww_dd_rdata;
				end else begin	
					de_ds <= r_ds;
				end
				if(ww_dd_is_en && id_instr[15:11] != 5'b0 && id_instr[15:11] == ww_instr[25:21] && ~(id_dt_is_f ^ ww_dd_is_f)) begin
					de_dt <= ww_dd_rdata;
				end else begin
					de_dt <= r_dt;
				end
				// exec
				if(de_instr[28:26] == 3'b110) begin
					ew_instr <= {de_instr[31:26],5'b11111,de_instr[20:0]};
				end else begin
					ew_instr <= de_instr;
				end
				case(de_instr[27:26])
					2'b00: 	begin
										if (de_instr[31:26] == 6'b0) begin
											ew_dd_is_en <= 0;
											ew_dd_is_f <= 0;
											if(de_instr[10:0] == 1) begin //CMU
												cpu_mode <= 1;
											end else if(de_instr[10:0] == 2) begin // CMS
												cpu_mode <= 0;
											end else if(de_instr[10:0] == 3) begin //ISW
												ew_dd <= ew_dd;
											end else if(de_instr[10:0] == 4) begin //ECLR
												err <= 0;
											end else if(de_instr[10:0] == 5) begin //ESET
												err <= exec_ds[7:0];
											end else begin
												ew_dd <= ew_dd;
											end
										end else begin
											ew_dd <= alu_dd;
											ew_dd_is_en <= 1;
											ew_dd_is_f <= 0;
										end	
									end
					2'b10: 	begin
										if (de_instr[28]) begin
											ew_dd <= de_pc + 1;
											ew_dd_is_en <= 1;
											ew_dd_is_f <= 0;
										end else begin
											ew_dd <= 0;
											ew_dd_is_en <= 0;
											ew_dd_is_f <= 0;
										end				
									end
					2'b11:	begin
										if(de_instr[31:28] == 4'b0011) begin // LW
											ew_dd <= alu_dd;
											ew_dd_is_en <= 1;
											ew_dd_is_f <= 0;
										end else if(de_instr[31:28] == 4'b0001) begin // SW
											ew_dd <= alu_dd;
											ew_dd_is_en <= 0;
											ew_dd_is_f <= 0;
											ew_wdata <= exec_dt;
										end else if(de_instr[31:28] == 4'b0000) begin // OUT
											io_out_data <= exec_ds[7:0];
											io_out_vld <= 1;
											ew_dd_is_en <= 0;
											ew_dd_is_f <= 0;
											state <= st_stall;
										end else if (de_instr[31:28] == 4'b0010) begin //IN
											io_in_rdy <= 1;
											ew_dd_is_en <= 1;
											ew_dd_is_f <= 0;
											state <= st_stall;
										end else begin
											err <= err | err_lost;
										end
									end
					2'b01:		begin
										if(de_instr[5:2] <= 4'b1011) begin
											f_in_vld <= 1;
											f_ope_data <= de_instr[5:2];
											f_in1_data <= exec_ds;
											f_in2_data <= exec_dt;
											ew_dd_is_en <= 1;
											ew_dd_is_f <= de_instr[0] == 1'b0;
											fpu_state <= 1;
											state <= st_stall;
										end else if(de_instr[5:2] == 4'b1100) begin
											ew_dd <= exec_ds;
											ew_dd_is_en <= 1;
											ew_dd_is_f <= 1;
										end else if(de_instr[5:2] == 4'b1101) begin
											ew_dd <= exec_ds;
											ew_dd_is_en <= 1;
											ew_dd_is_f <= 0;
										end else begin
											err <= err | err_lost;
										end
									end
					default: err <= err | err_lost;
				endcase
			end else begin // if is_exec_wait
				de_ds <= exec_ds;
				de_dt <= exec_dt;
				ew_instr <= 0;
				ew_dd_is_en <= 0;
			end

			// wait <- if stall, here
			ww_instr <= ew_instr;
			ww_dd <= ew_dd;
			ww_dd_is_f <= ew_dd_is_f;
			ww_dd_is_en <= ew_dd_is_en;
			// write -> see assign reg_we
			if(ww_instr != 0) begin
				dbg_counter <= dbg_counter + 1;
			end

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
					state <= st_normal;
				end else begin
					ew_dd <= ew_dd;
				end
			end
		end else begin
			err <= err | err_lost;
		end
	end

endmodule
