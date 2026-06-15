`timescale 1ns/1ps

module exec_alu import riscv_pkg::*; (
    input  logic          clk_i,
    input  logic          rstn_i,
    
    input  logic          issue_valid_i,
    input  dinstr_t       issue_decode_i,
    input  logic [31:0]   rs1_data_i,
    input  logic [31:0]   rs2_data_i,
    input  logic [5:0]    prf_rd_i,     
    
    // Writeback outputs
    output logic          wb_valid_o,
    output logic [5:0]    wb_prf_rd_o,
    output logic [31:0]   wb_data_o,
    
    output execute_t      execute_o
);

    logic [31:0] op1, op2, result;

    always_comb begin
        if (issue_decode_i.op == AUIPC) op1 = issue_decode_i.pc;
        else if (issue_decode_i.op == LUI) op1 = 32'b0;
        else op1 = rs1_data_i;

        if (issue_decode_i.imm_used) op2 = issue_decode_i.imm;
        else op2 = rs2_data_i;

        // ALU op.s
        result = 32'b0;
        case (issue_decode_i.op)
            ADD, ADDI, LUI, AUIPC: result = op1 + op2;
            SUB:   result = op1 - op2;
            SLL, SLLI: result = op1 << op2[4:0];
            SRL, SRLI: result = op1 >> op2[4:0];
            SRA, SRAI: result = $signed(op1) >>> op2[4:0];
            OR, ORI:   result = op1 | op2;
            AND, ANDI: result = op1 & op2;
            XOR, XORI: result = op1 ^ op2;
            SLT, SLTI: result = ($signed(op1) < $signed(op2)) ? 32'b1 : 32'b0;
            SLTU, SLTIU: result = (op1 < op2) ? 32'b1 : 32'b0;
            default: result = 32'b0;
        endcase

        wb_valid_o  = issue_valid_i;
        wb_prf_rd_o = prf_rd_i;
        wb_data_o   = result;
        
        execute_o.valid = issue_valid_i;
        execute_o.id    = issue_decode_i.id;
    end

endmodule
