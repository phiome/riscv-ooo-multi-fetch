`timescale 1ns/1ps

module rename import riscv_pkg::*; #(
    parameter PRF_SIZE = 64
)(
    input  logic          clk_i,
    input  logic          rstn_i,
    
    input  dinstr_t       decode_i [2],
    
    output logic          rename_valid_o [2], 
    output logic [5:0]    rename_prf_rs1_o [2], 
    output logic [5:0]    rename_prf_rs2_o [2], 
    output logic [5:0]    rename_prf_rd_o  [2], 
    output logic [5:0]    rename_old_prf_o [2], // EKLENDİ: Üzerine yazılan eski PRF
    
    input  logic          commit_valid_i [2],
    input  logic [5:0]    commit_freed_prf_i [2], 
    
    output logic          rename_stall_o 
);

    logic [5:0] rat [0:31];
    logic [5:0] free_list [0:PRF_SIZE-1];
    logic [5:0] free_head, free_tail;
    logic [6:0] free_count; 

    assign rename_stall_o = (free_count < 2);

    always_comb begin
        rename_valid_o[0] = 1'b0; rename_valid_o[1] = 1'b0;
        rename_prf_rs1_o[0] = '0; rename_prf_rs2_o[0] = '0; rename_prf_rd_o[0] = '0; rename_old_prf_o[0] = '0;
        rename_prf_rs1_o[1] = '0; rename_prf_rs2_o[1] = '0; rename_prf_rd_o[1] = '0; rename_old_prf_o[1] = '0;

        if (!rename_stall_o) begin
            // --- KOMUT 1 ---
            if (decode_i[0].valid) begin
                rename_valid_o[0] = 1'b1;
                rename_prf_rs1_o[0] = (decode_i[0].rs1_idx == 0) ? '0 : rat[decode_i[0].rs1_idx];
                rename_prf_rs2_o[0] = (decode_i[0].rs2_idx == 0) ? '0 : rat[decode_i[0].rs2_idx];
                if (decode_i[0].rd_used && decode_i[0].rd_idx != 0) begin
                    rename_prf_rd_o[0]  = free_list[free_head];
                    rename_old_prf_o[0] = rat[decode_i[0].rd_idx]; // Eski eşleşmeyi kaydet
                end
            end

            // --- KOMUT 2 ---
            if (decode_i[1].valid) begin
                rename_valid_o[1] = 1'b1;
                
                if (decode_i[1].rs1_used && decode_i[1].rs1_idx != 0 && decode_i[0].valid && decode_i[0].rd_used && decode_i[1].rs1_idx == decode_i[0].rd_idx) begin
                    rename_prf_rs1_o[1] = free_list[free_head];
                end else begin
                    rename_prf_rs1_o[1] = (decode_i[1].rs1_idx == 0) ? '0 : rat[decode_i[1].rs1_idx];
                end

                if (decode_i[1].rs2_used && decode_i[1].rs2_idx != 0 && decode_i[0].valid && decode_i[0].rd_used && decode_i[1].rs2_idx == decode_i[0].rd_idx) begin
                    rename_prf_rs2_o[1] = free_list[free_head];
                end else begin
                    rename_prf_rs2_o[1] = (decode_i[1].rs2_idx == 0) ? '0 : rat[decode_i[1].rs2_idx];
                end

                if (decode_i[1].rd_used && decode_i[1].rd_idx != 0) begin
                    if (decode_i[0].valid && decode_i[0].rd_used && decode_i[0].rd_idx != 0) begin
                         rename_prf_rd_o[1] = free_list[(free_head + 1) % PRF_SIZE];
                         if (decode_i[1].rd_idx == decode_i[0].rd_idx)
                             rename_old_prf_o[1] = free_list[free_head];
                         else
                             rename_old_prf_o[1] = rat[decode_i[1].rd_idx];
                    end else begin
                         rename_prf_rd_o[1]  = free_list[free_head];
                         rename_old_prf_o[1] = rat[decode_i[1].rd_idx];
                    end
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            free_head  <= '0;
            for (integer i = 0; i < 32; i++) rat[i] <= i[5:0];
            for (integer i = 32; i < PRF_SIZE; i++) free_list[i-32] <= i[5:0];
            free_tail  <= 32; free_count <= 32;
        end else begin
            logic [6:0] new_free_count = free_count;
            logic [5:0] new_free_head  = free_head;
            logic [5:0] new_free_tail  = free_tail;

            if (commit_valid_i[0]) begin
                free_list[new_free_tail] <= commit_freed_prf_i[0];
                new_free_tail = (new_free_tail + 1) % PRF_SIZE;
                new_free_count = new_free_count + 1;
            end
            if (commit_valid_i[1]) begin
                free_list[new_free_tail] <= commit_freed_prf_i[1];
                new_free_tail = (new_free_tail + 1) % PRF_SIZE;
                new_free_count = new_free_count + 1;
            end

            if (!rename_stall_o) begin
                if (decode_i[0].valid && decode_i[0].rd_used && decode_i[0].rd_idx != 0) begin
                    rat[decode_i[0].rd_idx] <= free_list[new_free_head];
                    new_free_head = (new_free_head + 1) % PRF_SIZE;
                    new_free_count = new_free_count - 1;
                end
                if (decode_i[1].valid && decode_i[1].rd_used && decode_i[1].rd_idx != 0) begin
                    rat[decode_i[1].rd_idx] <= free_list[new_free_head];
                    new_free_head = (new_free_head + 1) % PRF_SIZE;
                    new_free_count = new_free_count - 1;
                end
            end
            free_head  <= new_free_head; free_tail  <= new_free_tail; free_count <= new_free_count;
        end
    end
endmodule
