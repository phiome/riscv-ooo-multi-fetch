module scrambler#(parameter MEMFILE="test.hex")();

	localparam RamSize = 4096;

	logic [31:0] instruction_memory [RamSize];
	logic [31:0] scrambled_instruction_memory [RamSize];
	int line_size;
	initial begin
		$readmemh(MEMFILE, instruction_memory);

		for(line_size=0;line_size<RamSize;line_size++) begin
			if(instruction_memory[line_size]=='0) break;
			scrambled_instruction_memory[line_size] = scramble_instruction(instruction_memory[line_size]);
			//$display("line_size:%0d %h -> %h", line_size, instruction_memory[line_size], scrambled_instruction_memory[line_size]);
			if(scrambled_instruction_memory[line_size]=='0) break;
			$display("%h", scrambled_instruction_memory[line_size]);
		end
		//$writememh("scrambled_heap_sort.hex" scrambled_instruction_memory);
	end


	function automatic logic[31:0] scramble_instruction(logic[31:0] instruction);
		logic[31:0] scrambled_instruction='0;

		logic [6:0] opcode = {instruction[6:0]};
		logic [6:0] funct7 = {instruction[31:25]};
		logic [2:0] funct3 = {instruction[14:12]};
		logic [11:0] imm_I = {instruction[31:20]};
		logic [11:0] imm_S = {instruction[31:25], instruction[11:7]};
		logic [12:1] imm_B = {instruction[31], instruction[7], instruction[30:25], instruction[11:8]}; //imm B doesn't have 0'th bit and scrambled
		logic [31:12] imm_U = {instruction[31:12]}; //imm U uses upper bits
		logic [20:1] imm_J = {instruction[31], instruction[19:12], instruction[20], instruction[30:21]}; //imm J doesn't have 0'th bit and scrambled

		logic [24:20] rs1 = {instruction[19:15]};
		logic [19:15] rs2 = {instruction[24:20]};
		logic [11:7] rd = {instruction[11:7]};

		casez({funct7, funct3, opcode})
			{17'b??????????0110111}: scrambled_instruction = {imm_U[31:20], 7'b1110101, imm_U[19:12], rd}; //LUI
			{17'b??????????0010111}: scrambled_instruction = {imm_U[31:20], 7'b1110100, imm_U[19:12], rd}; //AUIPC
			{17'b??????????1101111}: scrambled_instruction = {{imm_J[20], imm_J[10:1], imm_J[11]}, 7'b1101111, imm_J[19:12], rd}; //JAL
			{17'b???????0001100111}: scrambled_instruction = {imm_I, 7'b1100111, rs1, 3'b000, rd}; //JALR
			{17'b???????0001100011}: scrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, 7'b1100011, rs1, 3'b100, {imm_B[4:1], imm_B[11]}}; //BEQ
			{17'b???????0011100011}: scrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, 7'b1100011, rs1, 3'b101, {imm_B[4:1], imm_B[11]}}; //BNE
			{17'b???????1111100011}: scrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, 7'b1100011, rs1, 3'b000, {imm_B[4:1], imm_B[11]}}; //BGEU
			{17'b???????1101100011}: scrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, 7'b1100011, rs1, 3'b001, {imm_B[4:1], imm_B[11]}}; //BLTU
			{17'b???????1011100011}: scrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, 7'b1100011, rs1, 3'b010, {imm_B[4:1], imm_B[11]}}; //BGE
			{17'b???????1001100011}: scrambled_instruction = {{imm_B[12], imm_B[10:5]}, rs2, 7'b1100011, rs1, 3'b011, {imm_B[4:1], imm_B[11]}}; //BLT
			{17'b???????1000000011}: scrambled_instruction = {imm_I, 7'b1100000, rs1, 3'b000, rd}; //LBU
			{17'b???????1010000011}: scrambled_instruction = {imm_I, 7'b1100000, rs1, 3'b001, rd}; //LHU
			{17'b???????0000000011}: scrambled_instruction = {imm_I, 7'b1100000, rs1, 3'b100, rd}; //LB
			{17'b???????0010000011}: scrambled_instruction = {imm_I, 7'b1100000, rs1, 3'b101, rd}; //LH
			{17'b???????0100000011}: scrambled_instruction = {imm_I, 7'b1100000, rs1, 3'b110, rd}; //LW
			{17'b???????0000100011}: scrambled_instruction = {imm_S[11:5], rs2, 7'b1100001, rs1, 3'b000, imm_S[4:0]}; //SB
			{17'b???????0010100011}: scrambled_instruction = {imm_S[11:5], rs2, 7'b1100001, rs1, 3'b001, imm_S[4:0]}; //SH
			{17'b???????0100100011}: scrambled_instruction = {imm_S[11:5], rs2, 7'b1100001, rs1, 3'b010, imm_S[4:0]}; //SW
			{17'b???????0000010011}: scrambled_instruction = {imm_I, 7'b1100100, rs1, 3'b000, rd}; //ADDI
			{17'b???????0100010011}: scrambled_instruction = {imm_I, 7'b1100100, rs1, 3'b010, rd}; //SLTI
			{17'b???????0110010011}: scrambled_instruction = {imm_I, 7'b1100100, rs1, 3'b011, rd}; //SLTIU
			{17'b???????1100010011}: scrambled_instruction = {imm_I, 7'b1100100, rs1, 3'b100, rd}; //ORI
			{17'b???????1000010011}: scrambled_instruction = {imm_I, 7'b1100100, rs1, 3'b110, rd}; //XORI
			{17'b???????1110010011}: scrambled_instruction = {imm_I, 7'b1100100, rs1, 3'b111, rd}; //ANDI
			{17'b00000000010010011}: scrambled_instruction = {7'b0000000, rs2, 7'b1100100, rs1, 3'b001, rd}; //SLLI
			{17'b00000001010010011}: scrambled_instruction = {7'b0000000, rs2, 7'b1100100, rs1, 3'b101, rd}; //SRLI
			{17'b01000001010010011}: scrambled_instruction = {7'b0000010, rs2, 7'b1100100, rs1, 3'b101, rd}; //SRAI
			{17'b00000000000110011}: scrambled_instruction = {7'b0000000, rs2, 7'b1110001, rs1, 3'b000, rd}; //ADD
			{17'b01000000000110011}: scrambled_instruction = {7'b0000010, rs2, 7'b1110001, rs1, 3'b000, rd}; //SUB
			{17'b00000000010110011}: scrambled_instruction = {7'b0000000, rs2, 7'b1110001, rs1, 3'b001, rd}; //SLL
			{17'b00000000100110011}: scrambled_instruction = {7'b0000000, rs2, 7'b1110001, rs1, 3'b010, rd}; //SLT
			{17'b00000000110110011}: scrambled_instruction = {7'b0000000, rs2, 7'b1110001, rs1, 3'b011, rd}; //SLTU
			{17'b00000001000110011}: scrambled_instruction = {7'b0000000, rs2, 7'b1110001, rs1, 3'b100, rd}; //XOR
			{17'b00000001010110011}: scrambled_instruction = {7'b0000000, rs2, 7'b1110001, rs1, 3'b101, rd}; //SRL
			{17'b01000001010110011}: scrambled_instruction = {7'b0000010, rs2, 7'b1110001, rs1, 3'b101, rd}; //SRA
			{17'b00000001100110011}: scrambled_instruction = {7'b0000000, rs2, 7'b1110001, rs1, 3'b110, rd}; //OR
			{17'b00000001110110011}: scrambled_instruction = {7'b0000000, rs2, 7'b1110001, rs1, 3'b111, rd}; //AND
			default: begin 
				//$display("invalid instruction %b", instruction);
				scrambled_instruction = '0;
			end
		endcase

		return scrambled_instruction;

	endfunction;



endmodule