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
	reg [2:0] state;
	reg [1:0] cpu_mode;
	reg [2:0] fpu_state;

	wire [31:0] ir_addrb_tmp;
	wire is_branch;
	wire is_exec_wait;
	wire [31:0] pc_jaddr;

	//ID
	reg [31:0] id_pc;
	reg id_is_en;
	wire [31:0] id_instr;
	wire [15:0] id_imm;
	wire [25:0] id_jaddr;
	wire id_ds_is_f;
	wire id_dt_is_f;
	//DE
	reg [31:0] de_instr;
	reg [31:0] de_pc;
	reg [31:0] de_ds;
	reg [31:0] de_dt;
	reg [31:0] de_pc_imm;
	wire de_ds_is_f;
	wire de_dt_is_f;
	wire de_ds_en;
	wire de_dt_en;
	wire [15:0] de_imm;
	wire [31:0] exec_ds;
	wire [31:0] exec_dt;
	//EW
	reg [31:0] ew_instr;
	reg [31:0] ew_dd;
	reg [31:0] ew_wdata;
	wire ew_dd_is_f;
	wire ew_dd_en;
	//WW
	reg [31:0] ww_instr;
	reg [31:0] ww_dd;
	wire ww_dd_is_f;
	wire ww_dd_en;
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
	gp_regfile gpr(clk,id_instr[20:16],id_instr[15:11],ww_instr[28:26] == 3'b110 ? 5'b11111 : ww_instr[25:21],gp_rs,gp_rt,gp_rd,gp_we);
	gp_regfile fpr(clk,id_instr[20:16],ww_instr[15:11],ww_instr[25:21],fp_rs,fp_rt,fp_rd,fp_we);

	assign r_ds = (id_instr[27:26] == 2'b01 && id_instr[1] == 1'b0) ? fp_rs : gp_rs;
	assign r_dt = id_instr[27:26] == 2'b01 ? fp_rt : gp_rt;
	assign gp_rd = ww_instr[31:26] == 6'b001111 ? d_rdata : ww_dd;
	assign fp_rd = ww_dd;
	assign gp_we = ww_instr != 0 &&
								(ww_instr[27:26] == 2'b00 ||
								 ww_instr[28:26] == 3'b110 ||
								 ww_instr[31:26] == 6'b001111 ||
								 ww_instr[31:26] == 6'b001011 ||
								 (ww_instr[27:26] == 2'b01 && ww_instr[0] == 1'b1)) && state == st_normal;
	assign fp_we = ww_instr[27:26] == 2'b01 && ww_instr[0] == 1'b0 && state == st_normal;

	//instr memory
	assign id_instr = state == st_begin ? 0 : ir_doutb;
	assign id_imm = (id_instr[27:26] == 2'b00 || id_instr[31:26] == 6'b001111)
										? id_instr[15:0] : {id_instr[25:21],id_instr[10:0]};
	assign id_jaddr = id_instr[25:0];

	assign ir_enb = 1;
	// JAL ? JALR or B : other >> 比較のところでうまくやればlut減らせる,分割も
	assign is_branch = (de_instr[31:26] == 6'b000010 && exec_ds == exec_dt) ||
										 (de_instr[31:26] == 6'b001010 && exec_ds != exec_dt) ||
										 (de_instr[31:26] == 6'b010010 && exec_ds <  exec_dt) ||
										 (de_instr[31:26] == 6'b011010 && exec_ds <= exec_dt);
	assign pc_jaddr = $signed(id_pc) + $signed(id_jaddr);
	assign ir_addrb_tmp = is_exec_wait ? id_pc :
												is_branch ? de_pc_imm : 
												id_instr[31:26] == 6'b000110 ? pc_jaddr : pc;
	assign ir_addrb = {ir_addrb_tmp[29:0],2'b00};				

	assign iw_ena = 1;
	assign iw_addra = exec_ds;
	assign iw_dina = exec_dt;
	assign iw_wea = state == st_normal && de_instr[31:26] == 6'b000000 && de_instr[10:0] == 3;

	//data memory
	assign d_en = 1;
	assign d_addr = {ew_dd[29:0],2'b00};
	assign d_wdata = ew_wdata;
	assign d_we = state == st_normal && ew_instr[31:26] == 6'b000111;

	// exec
	assign de_imm = (de_instr[27:26] == 2'b00 || de_instr[31:26] == 6'b001111)
	                  ? de_instr[15:0] : {de_instr[25:21],de_instr[10:0]};
	// forwarding
	assign id_ds_is_f = id_instr[31:26] == 6'b000001 && id_instr[0] == 1'b0;
	assign id_dt_is_f = id_instr[31:26] == 6'b000001;
	assign de_ds_is_f = de_instr[31:26] == 6'b000001 && de_instr[0] == 1'b0;
	assign de_dt_is_f = de_instr[31:26] == 6'b000001;
	assign de_ds_en = ~(de_instr[31:26] == 6'b001011 || 
											(de_instr[31:26] == 6'b000000 && (de_instr[10:0] == 1 || de_instr[10:0] == 2 || de_instr[10:0] == 4)));
	assign de_dt_en = de_instr[28:26] == 3'b100 || de_instr[28:26] == 3'b010 ||
										de_instr[31:26] == 6'b000111 || (de_instr[31:26] == 6'b000000 && de_instr[10:0] == 3) ||
										(de_instr[27:26] == 2'b01 && de_instr[5:2] <= 4'b0111);
	assign ew_dd_is_f = ew_instr[31:26] == 6'b000001 && ew_instr[1] == 1'b0;
	assign ew_dd_en = ew_instr[27:26] == 2'b00 || ew_instr[31:26] == 6'b001111 || ew_instr[31:26] == 6'b001011 || ew_instr[27:26] == 2'b01;
	assign ww_dd_is_f = ww_instr[31:26] == 6'b000001 && ww_instr[1] == 1'b0;
	assign ww_dd_en = ww_instr[27:26] == 2'b00 || ww_instr[31:26] == 6'b000111 || ww_instr[31:26] == 6'b001011 || ww_instr[27:26] == 2'b01;
	assign is_exec_wait = (de_ds_en && ew_dd_en && de_instr[20:16] != 5'b00000 && ew_instr[25:21] == de_instr[20:16] && ~(ew_dd_is_f ^ de_ds_is_f)) ||
												(de_dt_en && ew_dd_en && de_instr[15:11] != 5'b00000 && ew_instr[25:21] == de_instr[15:11] && ~(ew_dd_is_f ^ de_dt_is_f));
	assign exec_ds = (ww_dd_en && de_instr[20:16] != 5'b00000 && ww_instr[25:21] == de_instr[20:16] && ~(ww_dd_is_f ^ de_ds_is_f)) ? ww_dd : de_ds;
	assign exec_dt = (ww_dd_en && de_instr[15:11] != 5'b00000 && ww_instr[25:21] == de_instr[15:11] && ~(ww_dd_is_f ^ de_dt_is_f)) ? ww_dd : de_dt;

// 特権はまだちゃんと実装してない
	always @(posedge clk) begin
		if(~rstn) begin
			pc <= 0;
			cpu_mode <= 0;
			fpu_state <= 0;
			id_pc <= 0;
			id_is_en <= 1;
			de_instr <= 0;
			de_pc <= 0;
			de_ds <= 0;
			de_dt <= 0;
			de_pc_imm <= 0;
			ew_instr <= 0;
			ew_dd <= 0;
			ew_wdata <= 0;
			ww_instr <= 0;
			ww_dd <= 0;
			state <= st_begin;
		end else if (state == st_begin) begin
			pc <= pc + 1;
			state <= st_normal;
		end else if (state == st_normal) begin
			if (~is_exec_wait) begin	
				// ifetch -> see assign area imem
				id_pc <= ir_addrb_tmp;
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
				if (is_branch || ~id_is_en) begin
					de_instr <= 0;
				end else begin
					de_instr <= id_instr;
				end
				de_pc <= id_pc;
				// if write back
				if(ww_dd_en && id_instr[20:16] != 5'b00000 && ww_instr[25:21] == id_instr[20:16] && ~(ww_dd_is_f ^ id_ds_is_f)) begin
					de_ds <= ww_dd;	
				end else begin 
					de_ds <= r_ds;
				end
				if(ww_dd_en && id_instr[15:11] != 5'b00000 && ww_instr[25:21] == id_instr[15:11] && ~(ww_dd_is_f ^ id_dt_is_f)) begin
					de_dt <= ww_dd;
				end else begin
					de_dt <= r_dt;
				end
				de_pc_imm <= $signed(id_pc) + $signed(id_imm);
				// exec
				ew_instr <= de_instr;
				case (de_instr[31:26])  // ew_dd and ew_wdata
					// arith
					6'b110000: ew_dd <= { de_imm, exec_ds[15:0] };
					6'b001100: ew_dd <= $signed(exec_ds) + $signed(exec_dt);
					6'b001000: ew_dd <= $signed(exec_ds) + $signed(de_imm);
					6'b010100: ew_dd <= $signed(exec_ds) - $signed(exec_dt);
					6'b011100: ew_dd <= exec_ds << exec_dt[4:0];
					6'b011000: ew_dd <= exec_ds << de_imm[4:0];
					6'b100100: ew_dd <= exec_ds >> exec_dt[4:0];
					6'b100000: ew_dd <= exec_ds >> de_imm[4:0];
					6'b101100: ew_dd <= exec_ds >>> exec_dt[4:0];	
					6'b101000: ew_dd <= exec_ds >>> de_imm[4:0];
					// jump
					6'b000110: ew_dd <= de_pc + 1;
					6'b001110: ew_dd <= de_pc + 1;
					6'b000010: ew_dd <= ew_dd;
					6'b001010: ew_dd <= ew_dd;
					6'b010010: ew_dd <= ew_dd;
					6'b011010: ew_dd <= ew_dd;
					// load store
					6'b001111: ew_dd <= $signed(exec_ds) + $signed(de_imm); // LW
					6'b000111: begin  // SW
											ew_dd <= $signed(exec_ds) + $signed(de_imm);
											ew_wdata <= exec_dt;
										 end
					// IO
					6'b000011: begin //out
											io_out_data <= exec_ds[7:0];
											io_out_vld <= 1'b1;
											state <= st_stall;
										 end
					6'b001011: begin //in
											io_in_rdy <= 1'b1;
											state <= st_stall;
										 end
					//fpu
					6'b000001: begin
											if (de_instr[5:2] <= 4'b1011) begin
												f_in_vld <= 1'b1;
												f_ope_data <= de_instr[5:2];
												f_in1_data <= exec_ds;
												f_in2_data <= exec_dt;
												fpu_state <= 1;  
												state <= st_stall;
											end else if (de_instr[5:2] == 4'b1100 || de_instr[5:2] == 4'b1101) begin
												ew_dd <= exec_ds;
											end else begin
												err <= err | err_lost;
											end
										 end
					// super
					6'b000000: begin
											if (de_instr[10:0] == 1) begin  //CMU
					              cpu_mode <= 1;
					            end else if (de_instr[10:0] == 2) begin // CMS
					              cpu_mode <= 0;
					            end else if (de_instr[10:0] == 3) begin // ISW
				  	            ew_dd <= ew_dd;
				    	        end else if (de_instr[10:0] == 4) begin // ECLR
				      	        err <= 0;
				        	    end else if (de_instr[10:0] == 5) begin// ESET
				          	    err <= exec_ds[7:0];
					            end else begin
						            ew_dd <= ew_dd; 
											end
					           end
					default: err <= err | err_lost;
				endcase
			end else begin // if is_exec_wait
				de_ds <= exec_ds;
				de_dt <= exec_dt;
				ew_instr <= 0;
			end

			// wait <- if stall, here
			ww_instr <= ew_instr;
				// ww_dd
			ww_dd <= ew_dd;
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
