`timescale 1ns/1ps

module rename import riscv_pkg::*; #(
    parameter PRF_SIZE = 64
)(
    input  logic            clk_i,
    input  logic            rstn_i,
    
    input  dinstr_t         decode_i [2],
    
    output logic            rename_valid_o [2], 
    output logic [5:0]      rename_prf_rs1_o [2], 
    output logic [5:0]      rename_prf_rs2_o [2], 
    output logic [5:0]      rename_prf_rd_o  [2], 
    output logic [5:0]      rename_old_prf_o [2],
    
    input  logic            commit_valid_i [2],
    input  logic [5:0]      commit_freed_prf_i [2], 
    
    output logic            rename_stall_o 
);

    // Yerel parametre: PRF_SIZE için gereken bit sayısı
    localparam ADDR_WIDTH = $clog2(PRF_SIZE);

    logic [5:0] rat [0:31];
    logic [5:0] free_list [0:PRF_SIZE-1];
    logic [ADDR_WIDTH-1:0] free_head, free_tail;
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
                    rename_old_prf_o[0] = rat[decode_i[0].rd_idx];
                end
            end

            // --- KOMUT 2 ---
            if (decode_i[1].valid) begin
                rename_valid_o[1] = 1'b1;
                
                if (decode_i[1].rs1_used && decode_i[1].rs1_idx != 0 && decode_i[0].valid && decode_i[0].rd_used && decode_i[1].rs1_idx == decode_i[0].rd_idx)
                    rename_prf_rs1_o[1] = free_list[free_head];
                else
                    rename_prf_rs1_o[1] = (decode_i[1].rs1_idx == 0) ? '0 : rat[decode_i[1].rs1_idx];

                if (decode_i[1].rs2_used && decode_i[1].rs2_idx != 0 && decode_i[0].valid && decode_i[0].rd_used && decode_i[1].rs2_idx == decode_i[0].rd_idx)
                    rename_prf_rs2_o[1] = free_list[free_head];
                else
                    rename_prf_rs2_o[1] = (decode_i[1].rs2_idx == 0) ? '0 : rat[decode_i[1].rs2_idx];

                if (decode_i[1].rd_used && decode_i[1].rd_idx != 0) begin
                    if (decode_i[0].valid && decode_i[0].rd_used && decode_i[0].rd_idx != 0) begin
                         rename_prf_rd_o[1] = free_list[(free_head + 1) % PRF_SIZE];
                         rename_old_prf_o[1] = (decode_i[1].rd_idx == decode_i[0].rd_idx) ? free_list[free_head] : rat[decode_i[1].rd_idx];
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
            free_head <= '0; free_tail <= 32; free_count <= 32;
            for (integer i = 0; i < 32; i++) rat[i] <= i[5:0];
            for (integer i = 32; i < PRF_SIZE; i++) free_list[i-32] <= i[5:0];
        end else begin
            logic [ADDR_WIDTH-1:0] next_head = free_head;
            logic [ADDR_WIDTH-1:0] next_tail = free_tail;
            logic [6:0] next_count = free_count;

            if (commit_valid_i[0]) begin
                free_list[next_tail] <= commit_freed_prf_i[0];
                next_tail = ($bits(next_tail))'((next_tail + 1) % PRF_SIZE);
                next_count++;
            end
            if (commit_valid_i[1]) begin
                free_list[next_tail] <= commit_freed_prf_i[1];
                next_tail = ($bits(next_tail))'((next_tail + 1) % PRF_SIZE);
                next_count++;
            end

            if (!rename_stall_o) begin
                if (decode_i[0].valid && decode_i[0].rd_used && decode_i[0].rd_idx != 0) begin
                    rat[decode_i[0].rd_idx] <= free_list[next_head];
                    next_head = ($bits(next_head))'((next_head + 1) % PRF_SIZE);
                    next_count--;
                end
                if (decode_i[1].valid && decode_i[1].rd_used && decode_i[1].rd_idx != 0) begin
                    rat[decode_i[1].rd_idx] <= free_list[next_head];
                    next_head = ($bits(next_head))'((next_head + 1) % PRF_SIZE);
                    next_count--;
                end
            end
            free_head <= next_head; free_tail <= next_tail; free_count <= next_count;
        end
    end
endmodule
