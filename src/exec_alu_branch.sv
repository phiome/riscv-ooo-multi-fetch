`timescale 1ns/1ps

module exec_alu_branch import riscv_pkg::*; (
    input  logic          clk_i,
    input  logic          rstn_i,
    
    input  logic          issue_valid_i,
    input  dinstr_t       issue_decode_i,
    input  logic [31:0]   rs1_data_i,
    input  logic [31:0]   rs2_data_i,
    input  logic [5:0]    prf_rd_i,
    
    output logic          wb_valid_o,
    output logic [5:0]    wb_prf_rd_o,
    output logic [31:0]   wb_data_o,
    
    output execute_t      execute_o,
    
    // Branch/Jump outputs
    output logic          branch_resolved_o,
    output logic          branch_taken_o,
    output logic [31:0]   branch_target_o
);

    logic [31:0] op1, op2, alu_result;
    logic is_taken;
    logic [31:0] target_pc;

    always_comb begin
        // alu
        if (issue_decode_i.op == AUIPC || issue_decode_i.is_jump || issue_decode_i.is_branch) 
            op1 = issue_decode_i.pc;
        else if (issue_decode_i.op == LUI) 
            op1 = 32'b0;
        else 
            op1 = rs1_data_i;

        if (issue_decode_i.imm_used) op2 = issue_decode_i.imm;
        else op2 = rs2_data_i;

        alu_result = 32'b0;
        is_taken   = 1'b0;
        target_pc  = 32'b0;

        case (issue_decode_i.op)
            // Standart ALU
            ADD, ADDI, LUI, AUIPC: alu_result = op1 + op2;
            SUB:   alu_result = op1 - op2;
            SLL, SLLI: alu_result = op1 << op2[4:0];
            SRL, SRLI: alu_result = op1 >> op2[4:0];
            SRA, SRAI: alu_result = $signed(op1) >>> op2[4:0];
            OR, ORI:   alu_result = op1 | op2;
            AND, ANDI: alu_result = op1 & op2;
            XOR, XORI: alu_result = op1 ^ op2;
            SLT, SLTI: alu_result = ($signed(op1) < $signed(op2)) ? 32'b1 : 32'b0;
            SLTU, SLTIU: alu_result = (op1 < op2) ? 32'b1 : 32'b0;
            
            // Jumps
            JAL, JALR: begin
                alu_result = issue_decode_i.pc + 4; 
                is_taken = 1'b1;
                target_pc = (issue_decode_i.op == JALR) ? (rs1_data_i + issue_decode_i.imm) : (issue_decode_i.pc + issue_decode_i.imm);
                target_pc[0] = 1'b0; 
            end
            
            // Branches
            BEQ:  is_taken = (rs1_data_i == rs2_data_i);
            BNE:  is_taken = (rs1_data_i != rs2_data_i);
            BLT:  is_taken = ($signed(rs1_data_i) < $signed(rs2_data_i));
            BGE:  is_taken = ($signed(rs1_data_i) >= $signed(rs2_data_i));
            BLTU: is_taken = (rs1_data_i < rs2_data_i);
            BGEU: is_taken = (rs1_data_i >= rs2_data_i);
            default: ;
        endcase

        if (issue_decode_i.is_branch) begin
            target_pc = issue_decode_i.pc + issue_decode_i.imm;
        end

        wb_valid_o  = issue_valid_i;
        wb_prf_rd_o = prf_rd_i;
        wb_data_o   = alu_result;
        
        execute_o.valid = issue_valid_i;
        execute_o.id    = issue_decode_i.id;
        
        branch_resolved_o = issue_valid_i && (issue_decode_i.is_branch || issue_decode_i.is_jump);
        branch_taken_o    = is_taken;
        branch_target_o   = target_pc;
    end
endmodule
