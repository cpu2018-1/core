module cpu (
	input wire clk,
	input wire rstn,
	(* mark_debug = "true" *) output reg [7:0] err,
	// instruction memory
	(* mark_debug = "true" *) output wire [31:0] i_addr, // pc,2'b00
	(* mark_debug = "true" *) output wire [31:0] i_wdata,
	(* mark_debug = "true" *) input wire [31:0] i_rdata,
	(* mark_debug = "true" *) output wire i_en, // always 1	
	(* mark_debug = "true" *) output wire [3:0] i_we, 
	// data memory
	output wire [31:0] d_addr,
	output wire [31:0] d_wdata,
	input wire [31:0] d_rdata,
	output wire d_en,	// always 1
	output wire [3:0] d_we, 
	//FPU
	output wire [3:0] f_ope_data,
	output wire [31:0] f_in1_data,
	output wire [31:0] f_in2_data,
	input wire f_in_rdy,
	output reg f_in_vld,

	input wire [31:0] f_out_data,
	output reg f_out_rdy,
	input wire f_out_vld,

	input wire [2:0] f_err,
	//IO
	input wire [7:0] io_in_data,
	output reg  io_in_rdy,
	input wire io_in_vld,

	output reg [7:0] io_out_data,
	input wire io_out_rdy,
	output reg io_out_vld,

	input wire [4:0] io_err
	);

	localparam st_ifetch = 3'b001;
	localparam st_dfetch = 3'b010;
	localparam st_exec   = 3'b011;
	localparam st_wait   = 3'b100;
	localparam st_write  = 3'b101;

	localparam err_lost  = 8'b10000000;
	localparam err_carry = 8'b01000000;
	localparam err_io    = 8'b00100000;

	localparam user_irgn = 64;

	(* mark_debug = "true" *) reg [31:0] pc;
	(* mark_debug = "true" *) reg [2:0] state;
	(* mark_debug = "true" *) reg [1:0] cpu_mode;
	reg [2:0] fpu_state;

	wire is_io;
	wire is_fpu;
	(* mark_debug = "true" *) wire [31:0] ds;
	(* mark_debug = "true" *) wire [31:0] dt;
	wire [15:0] imm;
	wire [25:0] jaddr;
	(* mark_debug = "true" *) reg [31:0] dd;
	wire [31:0] gp_rs,gp_rt,gp_rd;
	wire gp_we;
	wire [31:0] fp_rs,fp_rt,fp_rd;
	wire fp_we;

	wire [31:0] tmp_d_addr;

	// JAL, JALR-> r31
	gp_regfile gpr(clk,i_rdata[20:16],i_rdata[15:11],i_rdata[28:26] == 3'b110 ? 5'b11111 : i_rdata[25:21],gp_rs,gp_rt,gp_rd,gp_we);
	gp_regfile fpr(clk,i_rdata[20:16],i_rdata[15:11],i_rdata[25:21],fp_rs,fp_rt,fp_rd,fp_we);

	//nearly const
	assign i_en = 1;
	assign d_en = 1;

	// decode
	assign is_io = i_rdata[28:26] == 3'b011;
	assign is_fpu = i_rdata[31:26] == 6'b000001 && i_rdata[5:2] <= 4'b1011;
	assign ds = (i_rdata[27:26] == 2'b01 && i_rdata[1] == 1'b0) ? fp_rs : gp_rs;
	assign dt = i_rdata[27:26] == 2'b01 ? fp_rt : gp_rt;
	assign gp_rd = dd;
	assign fp_rd = dd;
	assign imm = (i_rdata[27:26] == 2'b00 || i_rdata[31:26] == 6'b001111)
								? i_rdata[15:0] : { i_rdata[25:21],i_rdata[10:0] };
	assign jaddr = i_rdata[25:0];
	// reg write condition
	assign gp_we = (state == st_write && (i_rdata[27:26] == 2'b00 || i_rdata[28:26] == 3'b110 || i_rdata[31:26] == 6'b001111 || i_rdata[31:26] == 6'b001011 || (i_rdata[27:26] == 2'b01 && i_rdata[0] == 1'b1))) ? 1 : 0;
	assign fp_we = (state == st_write && i_rdata[27:26] == 2'b01 && i_rdata[0] == 1'b0) ? 1 : 0;

	//memory
	assign tmp_d_addr = $signed(ds) + $signed(imm);
	assign d_addr = { tmp_d_addr[29:0], 2'b00 };
	assign d_wdata = dt;
	assign d_we = state == st_exec && i_rdata[31:26] == 6'b000111 ? 4'b1111 : 4'b0000;

	assign i_addr = (state == st_exec && i_rdata[31:26] == 6'b000000 && i_rdata[10:0] == 3) ? {ds[29:0], 2'b00} : {pc[29:0], 2'b00};
	assign i_wdata = dt;
	assign i_we = (state == st_exec && i_rdata[31:26] == 6'b000000 && i_rdata[10:0] == 3)	? 4'b1111 : 4'b0000;

	//fpu
	assign f_ope_data = i_rdata[5:2];
	assign f_in1_data = ds;
	assign f_in2_data = dt;

	always @(posedge clk) begin
		if (~rstn) begin
			err <= 0;
			pc <= 0;
			cpu_mode <= 0;
			fpu_state <= 0;
			io_in_rdy <= 0;
			io_out_data <= 0;
			io_out_vld <= 0;
			f_in_vld <= 0;
			f_out_rdy <= 0;
			state <= st_ifetch;
		end else if (state == st_ifetch) begin	// instraction fetch
			state <= st_dfetch;
		end else if (state == st_dfetch) begin  // data fetch
			// for reading reg, you need 1clk
			// auth check
			if (i_rdata[31:26] == 6'b000000 && (i_rdata[10:0] >= 3) && cpu_mode != 0) begin
				err <= err | err_lost;
			end else begin
				state <= 	st_exec;
			end
		end else if (state == st_exec) begin    // exec
			// you must write case (subst dd)			
			case (i_rdata[31:26])
				// arith logic
				6'b110000: dd <= { imm, ds[15:0] };
				6'b001100: dd <= $signed(ds) + $signed(dt);
				6'b001000: dd <= $signed(ds) + $signed(imm);
				6'b010100: dd <= $signed(ds) - $signed(dt);
				6'b011100: dd <= ds << dt[4:0];
				6'b011000: dd <= ds << imm[4:0];
				6'b100100: dd <= ds >> dt[4:0];
				6'b100000: dd <= ds >> imm[4:0];
				6'b101100: dd <= ds >>> dt[4:0];
				6'b101000: dd <= ds >>> imm[4:0];
				// jump branch
				6'b100010: dd <= dd; // J
				6'b101010: dd <= dd; // JR
				6'b000110: dd <= pc + 1;
				6'b001110: dd <= pc + 1;
				6'b000010: dd <= dd;
				6'b001010: dd <= dd;
				6'b010010: dd <= dd;
				6'b011010: dd <= dd;
				// load store
				6'b001111: dd <= dd;
				6'b000111: dd <= dd;
				// IO
				6'b000011: begin //out
										io_out_data <= ds[7:0];
										io_out_vld <= 1'b1;
									 end
				6'b001011: io_in_rdy <= 1'b1;
				// super
				6'b000000: begin
										if (i_rdata[10:0] == 1)  //CMU
											cpu_mode <= 1;
										else if (i_rdata[10:0] == 2) // CMS
											cpu_mode <= 0;
										else if (i_rdata[10:0] == 3) // ISW
											dd <= dd;
										else if (i_rdata[10:0] == 4) // ECLR
											err <= 0;
										else if (i_rdata[10:0] == 5) // ESET
											err <= ds[7:0];
										else
											err <= err | err_lost;
									 end
				//fpu
				6'b000001: begin
										if (i_rdata[5:2] <= 4'b1011) begin
											f_in_vld <= 1;
											fpu_state <= 1;
										end else if (i_rdata[5:2] == 4'b1100 || i_rdata[5:2] == 4'b1101) begin
											dd <= ds;
										end else begin
											err <= err | err_lost;
										end
									end
				default: err <= err | err_lost;
			endcase
			// state
			state <= st_wait;
		end else if (state == st_wait) begin
			if (is_io) begin
				// IO proc
				if (i_rdata[29]) begin //in
					if (io_in_rdy && io_in_vld) begin
						dd <= io_in_data;	
						io_in_rdy <= 1'b0;
						state <= st_write;
					end else begin
						state <= st_wait;
					end
				end else begin       //out
					if (io_out_rdy && io_out_vld) begin
						io_out_vld <= 1'b0;
						io_out_data <= 0;	
						state <= st_write;
					end else begin
						state <= st_wait;
					end
				end
				err <=  err | {3'b000,io_err};
			end else if (is_fpu) begin
				// FPU proc
				if (fpu_state == 1 && f_in_rdy && f_in_vld) begin
					f_in_vld <= 0;
					f_out_rdy <= 1;
					fpu_state <= 2;
				end else if (fpu_state == 2 && f_out_rdy && f_out_vld) begin
					f_out_rdy <= 0;
					fpu_state <= 0;
					dd <= f_out_data;
					state <= st_write;
				end else begin
					dd <= dd;
				end
			end else if (i_rdata[31:26] == 6'b001111) begin
				dd <= d_rdata;
				state <= st_write;
			end else begin
				state <= st_write;
			end
		end else if (state == st_write) begin   // write
			// for writing reg, you need 1clk

			//pc update
			if (i_rdata[31:26] == 6'b000110 || i_rdata[31:26] == 6'b100010) begin // JAL J
				pc <= $signed(pc) + $signed({ {6{jaddr[25]}},jaddr });
			end else if (i_rdata[31:26] == 6'b001110 || i_rdata[31:26] == 6'b101010) begin // JALR JR
				pc <= ds;
			end else if (i_rdata[27:26] == 2'b10) begin // B
				if((i_rdata[31:28] == 4'b0000 && ds == dt) ||
					 (i_rdata[31:28] == 4'b0010 && ds != dt) ||
					 (i_rdata[31:28] == 4'b0100 && ds < dt)  ||
					 (i_rdata[31:28] == 4'b0110 && ds <= dt)) begin
					pc <= $signed(pc) + $signed({ {16{imm[15]}},imm });
				end else begin
					pc <= pc + 1;
				end
			end else if (i_rdata[31:26] == 6'b000000) begin
				if (i_rdata[10:0] == 1) begin
					pc <= user_irgn;
				end else if (i_rdata[10:0] == 2) begin
					pc <= 0;
				end else begin
					pc <= pc + 1;
				end
			end else begin
				pc <= pc + 1;
			end
			//state
			state <= st_ifetch;
		end else begin
			err <= err | err_lost;
		end
	end
endmodule
			
