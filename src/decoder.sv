`timescale 1ns/1ps

module decoder import riscv_pkg::*; (
    input  logic        clk_i,
    input  logic [31:0] instr_i,
    input  logic [31:0] pc_i,
    input  logic [31:0] id_i,
    output dinstr_t     dinstr_o
);

    logic [6:0] opcode;
    logic [4:0] rd_idx, rs1_idx, rs2_idx;
    logic [2:0] funct3;
    logic [6:0] funct7;

    // --- SENİN ÖZEL (CUSTOM) BİT HARİTAN ---
    assign opcode  = instr_i[19:13];
    assign rs2_idx = instr_i[24:20];
    assign rs1_idx = instr_i[12:8];
    assign funct3  = instr_i[7:5];
    assign rd_idx  = instr_i[4:0];
    assign funct7  = instr_i[31:25];

    always_comb begin
        dinstr_o.valid     = 1'b0;
        dinstr_o.is_store  = 1'b0;
        dinstr_o.is_mem    = 1'b0;
        dinstr_o.is_jump   = 1'b0;
        dinstr_o.is_branch = 1'b0;
        dinstr_o.rd_used   = 1'b0;
        dinstr_o.rs1_used  = 1'b0;
        dinstr_o.rs2_used  = 1'b0;
        dinstr_o.imm_used  = 1'b0;
        
        dinstr_o.rd_idx    = rd_idx;
        dinstr_o.rs1_idx   = rs1_idx;
        dinstr_o.rs2_idx   = rs2_idx;
        
        dinstr_o.imm       = '0;
        dinstr_o.pc        = pc_i;
        dinstr_o.id        = id_i;
        dinstr_o.op        = UNKNOWN;

        case (opcode)
            // LUI
            7'b1110101: begin 
                dinstr_o.valid    = 1'b1; dinstr_o.rd_used  = 1'b1; dinstr_o.imm_used = 1'b1;
                dinstr_o.imm      = {instr_i[31:20], instr_i[12:5], 12'b0}; dinstr_o.op = LUI;
            end
            // AUIPC
            7'b1110100: begin 
                dinstr_o.valid    = 1'b1; dinstr_o.rd_used  = 1'b1; dinstr_o.imm_used = 1'b1;
                dinstr_o.imm      = {instr_i[31:20], instr_i[12:5], 12'b0}; dinstr_o.op = AUIPC;
            end
            // JAL 
            7'b1101111: begin 
                dinstr_o.valid    = 1'b1; dinstr_o.is_jump  = 1'b1; dinstr_o.rd_used  = 1'b1; dinstr_o.imm_used = 1'b1;
                dinstr_o.imm      = { {11{instr_i[31]}}, instr_i[31], instr_i[12:5], instr_i[20], instr_i[30:21], 1'b0 }; dinstr_o.op = JAL;
            end
            // JALR 
            7'b1100111: begin 
                dinstr_o.valid    = 1'b1; dinstr_o.is_jump  = 1'b1; dinstr_o.rd_used  = 1'b1; dinstr_o.rs1_used = 1'b1; dinstr_o.imm_used = 1'b1;
                dinstr_o.imm      = { {20{instr_i[31]}}, instr_i[31:20] }; dinstr_o.op = JALR;
            end
            // Branch
            7'b1100011: begin 
                dinstr_o.valid     = 1'b1; dinstr_o.is_branch = 1'b1; dinstr_o.rs1_used  = 1'b1; dinstr_o.rs2_used  = 1'b1; dinstr_o.imm_used  = 1'b1;
                dinstr_o.imm       = { {19{instr_i[31]}}, instr_i[31], instr_i[0], instr_i[30:25], instr_i[4:1], 1'b0 };
                case (funct3)
                    3'b100: dinstr_o.op = BEQ; 3'b101: dinstr_o.op = BNE; 3'b000: dinstr_o.op = BGEU;
                    3'b001: dinstr_o.op = BLTU; 3'b010: dinstr_o.op = BGE; 3'b011: dinstr_o.op = BLT;
                    default: dinstr_o.valid = 1'b0;
                endcase
            end
            // Load
            7'b1100000: begin 
                dinstr_o.valid    = 1'b1; dinstr_o.is_mem   = 1'b1; dinstr_o.rd_used  = 1'b1; dinstr_o.rs1_used = 1'b1; dinstr_o.imm_used = 1'b1;
                dinstr_o.imm      = { {20{instr_i[31]}}, instr_i[31:20] };
                case (funct3)
                    3'b000: dinstr_o.op = LBU; 3'b001: dinstr_o.op = LHU; 3'b100: dinstr_o.op = LB;
                    3'b101: dinstr_o.op = LH; 3'b110: dinstr_o.op = LW; default: dinstr_o.valid = 1'b0;
                endcase
            end
            // Store
            7'b1100001: begin 
                dinstr_o.valid    = 1'b1; dinstr_o.is_mem   = 1'b1; dinstr_o.is_store = 1'b1; dinstr_o.rs1_used = 1'b1; dinstr_o.rs2_used = 1'b1; dinstr_o.imm_used = 1'b1;
                dinstr_o.imm      = { {20{instr_i[31]}}, instr_i[31:25], instr_i[4:0] };
                case (funct3)
                    3'b000: dinstr_o.op = SB; 3'b001: dinstr_o.op = SH; 3'b010: dinstr_o.op = SW; default: dinstr_o.valid = 1'b0;
                endcase
            end
            // I-ALU
            7'b1100100: begin 
                dinstr_o.valid    = 1'b1; dinstr_o.rd_used  = 1'b1; dinstr_o.rs1_used = 1'b1; dinstr_o.imm_used = 1'b1;
                if (funct3 == 3'b001 || funct3 == 3'b101) dinstr_o.imm = { 27'b0, instr_i[24:20] };
                else dinstr_o.imm = { {20{instr_i[31]}}, instr_i[31:20] };
                case (funct3)
                    3'b000: dinstr_o.op = ADDI; 3'b010: dinstr_o.op = SLTI; 3'b011: dinstr_o.op = SLTIU;
                    3'b100: dinstr_o.op = ORI; 3'b110: dinstr_o.op = XORI; 3'b111: dinstr_o.op = ANDI;
                    3'b001: dinstr_o.op = SLLI;
                    3'b101: begin if (funct7 == 7'b0000000) dinstr_o.op = SRLI; else if (funct7 == 7'b0000010) dinstr_o.op = SRAI; end
                    default: dinstr_o.valid = 1'b0;
                endcase
            end
            // R-ALU
            7'b1110001: begin 
                dinstr_o.valid    = 1'b1; dinstr_o.rd_used  = 1'b1; dinstr_o.rs1_used = 1'b1; dinstr_o.rs2_used = 1'b1;
                case (funct3)
                    3'b000: begin if (funct7 == 7'b0000000) dinstr_o.op = ADD; else if (funct7 == 7'b0000010) dinstr_o.op = SUB; else dinstr_o.valid = 1'b0; end
                    3'b001: if (funct7 == 7'b0000000) dinstr_o.op = SLL;  else dinstr_o.valid = 1'b0;
                    3'b010: if (funct7 == 7'b0000000) dinstr_o.op = SLT;  else dinstr_o.valid = 1'b0;
                    3'b011: if (funct7 == 7'b0000000) dinstr_o.op = SLTU; else dinstr_o.valid = 1'b0;
                    3'b100: if (funct7 == 7'b0000000) dinstr_o.op = XOR;  else dinstr_o.valid = 1'b0;
                    3'b101: begin if (funct7 == 7'b0000000) dinstr_o.op = SRL; else if (funct7 == 7'b0000010) dinstr_o.op = SRA; else dinstr_o.valid = 1'b0; end
                    3'b110: if (funct7 == 7'b0000000) dinstr_o.op = OR;   else dinstr_o.valid = 1'b0;
                    3'b111: if (funct7 == 7'b0000000) dinstr_o.op = AND;  else dinstr_o.valid = 1'b0;
                    default: dinstr_o.valid = 1'b0; 
                endcase
            end
            default: dinstr_o.valid = 1'b0;
        endcase
    end
endmodule
