`timescale 1 ns / 1 ps

module descrambler(
	input logic[31:0] instruction_i,
	output logic[31:0] instruction_o
);

	always_comb begin
		instruction_o = descramble_instruction(instruction_i);
	end

	function automatic logic[31:0] descramble_instruction(logic[31:0] instruction);
		logic[31:0] descrambled_instruction='0;

		logic [6:0] opcode = {instruction[19:13]};
		logic [6:0] funct7 = {instruction[31:25]};
		logic [2:0] funct3 = {instruction[7:5]};
		logic [11:0] imm_I = {instruction[31:20]};
		logic [11:0] imm_S = {instruction[31:25], instruction[4:0]};
		logic [12:1] imm_B = {instruction[31], instruction[0], instruction[30:25], instruction[4:1]}; //imm B doesn't have 0'th bit and scrambled
		logic [31:12] imm_U = {instruction[31:20], instruction[12:5]}; //imm U uses upper bits
		logic [20:1] imm_J = {instruction[31], instruction[12:5], instruction[20], instruction[30:21]}; //imm J doesn't have 0'th bit and scrambled

		logic [24:20] rs1 = {instruction[12:8]};
		logic [19:15] rs2 = {instruction[24:20]};
		logic [11:7] rd = {instruction[4:0]};

		casez({funct7, opcode, funct3})
			{17'b???????1110101???} : descrambled_instruction = {imm_U[31:12], rd, 7'b0110111}; //LUI
			{17'b???????1110100???} : descrambled_instruction = {imm_U[31:12], rd, 7'b0010111}; //AUIPC
			{17'b???????1101111???} : descrambled_instruction = {{imm_J[20], imm_J[10:1], imm_J[11], imm_J[19:12]}, rd, 7'b1101111}; //JAL
			{17'b???????1100111000} : descrambled_instruction = {imm_I, rs1, 3'b000, rd, 7'b1100111}; //JALR
			{17'b???????1100011100} : descrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, rs1, 3'b000, {imm_B[4:1], imm_B[11]}, 7'b1100011}; //BEQ
			{17'b???????1100011101} : descrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, rs1, 3'b001, {imm_B[4:1], imm_B[11]}, 7'b1100011}; //BNE
			{17'b???????1100011011} : descrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, rs1, 3'b100, {imm_B[4:1], imm_B[11]}, 7'b1100011}; //BLT
			{17'b???????1100011010} : descrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, rs1, 3'b101, {imm_B[4:1], imm_B[11]}, 7'b1100011}; //BGE
			{17'b???????1100011001} : descrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, rs1, 3'b110, {imm_B[4:1], imm_B[11]}, 7'b1100011}; //BLTU
			{17'b???????1100011000} : descrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, rs1, 3'b111, {imm_B[4:1], imm_B[11]}, 7'b1100011}; //BGEU
			{17'b???????1100000100} : descrambled_instruction = {imm_I, rs1, 3'b000, rd, 7'b0000011}; //LB
			{17'b???????1100000101} : descrambled_instruction = {imm_I, rs1, 3'b001, rd, 7'b0000011}; //LH
			{17'b???????1100000110} : descrambled_instruction = {imm_I, rs1, 3'b010, rd, 7'b0000011}; //LW
			{17'b???????1100000000} : descrambled_instruction = {imm_I, rs1, 3'b100, rd, 7'b0000011}; //LBU
			{17'b???????1100000001} : descrambled_instruction = {imm_I, rs1, 3'b101, rd, 7'b0000011}; //LHU
			{17'b???????1100001000} : descrambled_instruction = {imm_S[11:5], rs2, rs1, 3'b000, imm_S[4:0], 7'b0100011}; //SB
			{17'b???????1100001001} : descrambled_instruction = {imm_S[11:5], rs2, rs1, 3'b001, imm_S[4:0], 7'b0100011}; //SH
			{17'b???????1100001010} : descrambled_instruction = {imm_S[11:5], rs2, rs1, 3'b010, imm_S[4:0], 7'b0100011}; //SW
			{17'b???????1100100000} : descrambled_instruction = {imm_I, rs1, 3'b000, rd, 7'b0010011}; //ADDI
			{17'b???????1100100010} : descrambled_instruction = {imm_I, rs1, 3'b010, rd, 7'b0010011}; //SLTI
			{17'b???????1100100011} : descrambled_instruction = {imm_I, rs1, 3'b011, rd, 7'b0010011}; //SLTIU
			{17'b???????1100100100} : descrambled_instruction = {imm_I, rs1, 3'b110, rd, 7'b0010011}; //XORI
			{17'b???????1100100110} : descrambled_instruction = {imm_I, rs1, 3'b100, rd, 7'b0010011}; //ORI
			{17'b???????1100100111} : descrambled_instruction = {imm_I, rs1, 3'b111, rd, 7'b0010011}; //ANDI
			{17'b00000001100100001} : descrambled_instruction = {7'b0000000, rs2, rs1, 3'b001, rd, 7'b0010011}; //SLLI
			{17'b00000001100100101} : descrambled_instruction = {7'b0000000, rs2, rs1, 3'b101, rd, 7'b0010011}; //SRLI
			{17'b00000101100100101} : descrambled_instruction = {7'b0100000, rs2, rs1, 3'b101, rd, 7'b0010011}; //SRAI
			{17'b00000001110001000} : descrambled_instruction = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011}; //ADD
			{17'b00000101110001000} : descrambled_instruction = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011}; //SUB
			{17'b00000001110001001} : descrambled_instruction = {7'b0000000, rs2, rs1, 3'b001, rd, 7'b0110011}; //SLL
			{17'b00000001110001010} : descrambled_instruction = {7'b0000000, rs2, rs1, 3'b010, rd, 7'b0110011}; //SLT
			{17'b00000001110001011} : descrambled_instruction = {7'b0000000, rs2, rs1, 3'b011, rd, 7'b0110011}; //SLTU
			{17'b00000001110001100} : descrambled_instruction = {7'b0000000, rs2, rs1, 3'b100, rd, 7'b0110011}; //XOR
			{17'b00000001110001101} : descrambled_instruction = {7'b0000000, rs2, rs1, 3'b101, rd, 7'b0110011}; //SRL
			{17'b00000101110001101} : descrambled_instruction = {7'b0100000, rs2, rs1, 3'b101, rd, 7'b0110011}; //SRA
			{17'b00000001110001110} : descrambled_instruction = {7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011}; //OR
			{17'b00000001110001111} : descrambled_instruction = {7'b0000000, rs2, rs1, 3'b111, rd, 7'b0110011}; //AND
			default: begin 
				//$display("invalid instruction %b", instruction);
				descrambled_instruction = '0;
			end
		endcase

		return descrambled_instruction;

	endfunction;



endmodule
