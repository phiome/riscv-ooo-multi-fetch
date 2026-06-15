`timescale 1ns/1ps

module rob import riscv_pkg::*; #(
    parameter ROB_SIZE = 16
)(
    input  logic          clk_i,
    input  logic          rstn_i,
    
    input  logic          alloc_valid_i [2],
    input  dinstr_t       alloc_decode_i [2],
    input  logic [5:0]    alloc_prf_rd_i [2],
    input  logic [5:0]    alloc_old_prf_i [2], // EKLENDİ
    input  logic [31:0]   alloc_instr_i [2], 
    
    output logic          rob_stall_o,
    output logic [31:0]   rob_head_id_o,
    
    input  execute_t      execute_i [3], 
    input  logic [31:0]   wb_data_i [3],     
    input  logic [31:0]   lsu_log_addr_i,
    input  logic [31:0]   lsu_log_data_i,
    input  logic          lsu_log_we_i,
    
    output commit_t       commit_o [2],
    output logic          commit_valid_o [2],
    output logic [5:0]    commit_freed_prf_o [2] // EKLENDİ: Boşa çıkan PRF'ler
);

    typedef struct packed {
        logic       valid;
        logic       ready;
        logic[31:0] id;
        logic[31:0] pc;
        logic[4:0]  rd_idx;
        logic[5:0]  prf_idx;
        logic[5:0]  old_prf; // EKLENDİ
        logic[31:0] instr;  
        logic[31:0] result; 
        logic[31:0] mem_addr;
        logic[31:0] mem_data;
        logic       mem_wrt;
    } rob_entry_t;

    rob_entry_t rob_queue [0:ROB_SIZE-1];
    logic [$clog2(ROB_SIZE)-1:0] head, tail;
    logic [$clog2(ROB_SIZE):0]   count;

    assign rob_stall_o = (count >= (ROB_SIZE - 2));
    assign rob_head_id_o = rob_queue[head].id;

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            head  <= '0; tail <= '0; count <= '0;
            for (integer i = 0; i < ROB_SIZE; i++) rob_queue[i] <= '0;
            commit_o[0] <= '0; commit_o[1] <= '0;
            commit_valid_o[0] <= 1'b0; commit_valid_o[1] <= 1'b0;
            commit_freed_prf_o[0] <= '0; commit_freed_prf_o[1] <= '0;
        end else begin
            logic [$clog2(ROB_SIZE)-1:0] next_head = head;
            logic [$clog2(ROB_SIZE)-1:0] next_tail = tail;
            logic [$clog2(ROB_SIZE):0]   next_count = count;

            commit_o[0] <= '0; commit_o[1] <= '0;
            commit_valid_o[0] <= 1'b0; commit_valid_o[1] <= 1'b0;
            commit_freed_prf_o[0] <= '0; commit_freed_prf_o[1] <= '0;

            // 1. COMMIT (Geri Dönüşüm Burada Tetiklenir)
            if (next_count > 0 && rob_queue[next_head].valid && rob_queue[next_head].ready) begin
                commit_o[0].valid    <= 1'b1;
                commit_o[0].id       <= rob_queue[next_head].id;
                commit_o[0].pc       <= rob_queue[next_head].pc;
                commit_o[0].instr    <= rob_queue[next_head].instr; 
                commit_o[0].reg_addr <= rob_queue[next_head].rd_idx;
                commit_o[0].reg_data <= rob_queue[next_head].result; 
                commit_o[0].mem_addr <= rob_queue[next_head].mem_addr;
                commit_o[0].mem_data <= rob_queue[next_head].mem_data;
                commit_o[0].mem_wrt  <= rob_queue[next_head].mem_wrt;
                
                commit_valid_o[0]     <= 1'b1;
                commit_freed_prf_o[0] <= rob_queue[next_head].old_prf; // Rename'e gönder
                
                rob_queue[next_head].valid <= 1'b0;
                next_head = next_head + 1'b1;
                next_count = next_count - 1'b1;

                if (next_count > 0 && rob_queue[next_head].valid && rob_queue[next_head].ready) begin
                    commit_o[1].valid    <= 1'b1;
                    commit_o[1].id       <= rob_queue[next_head].id;
                    commit_o[1].pc       <= rob_queue[next_head].pc;
                    commit_o[1].instr    <= rob_queue[next_head].instr;
                    commit_o[1].reg_addr <= rob_queue[next_head].rd_idx;
                    commit_o[1].reg_data <= rob_queue[next_head].result;
                    commit_o[1].mem_addr <= rob_queue[next_head].mem_addr;
                    commit_o[1].mem_data <= rob_queue[next_head].mem_data;
                    commit_o[1].mem_wrt  <= rob_queue[next_head].mem_wrt;
                    
                    commit_valid_o[1]     <= 1'b1;
                    commit_freed_prf_o[1] <= rob_queue[next_head].old_prf; // Rename'e gönder
                    
                    rob_queue[next_head].valid <= 1'b0;
                    next_head = next_head + 1'b1;
                    next_count = next_count - 1'b1;
                end
            end

            // 2. EXECUTE WRITEBACK
            for (integer i = 0; i < ROB_SIZE; i++) begin
                if (rob_queue[i].valid && !rob_queue[i].ready) begin
                    if (execute_i[0].valid && execute_i[0].id == rob_queue[i].id) begin
                        rob_queue[i].ready  <= 1'b1; rob_queue[i].result <= wb_data_i[0]; 
                    end else if (execute_i[1].valid && execute_i[1].id == rob_queue[i].id) begin
                        rob_queue[i].ready  <= 1'b1; rob_queue[i].result <= wb_data_i[1];
                    end else if (execute_i[2].valid && execute_i[2].id == rob_queue[i].id) begin
                        rob_queue[i].ready    <= 1'b1; rob_queue[i].result <= wb_data_i[2];
                        rob_queue[i].mem_addr <= lsu_log_addr_i;
                        rob_queue[i].mem_data <= lsu_log_data_i;
                        rob_queue[i].mem_wrt  <= lsu_log_we_i;
                    end
                end
            end

            // 3. ALLOCATION
            if (!rob_stall_o) begin
                if (alloc_valid_i[0]) begin
                    rob_queue[next_tail].valid   <= 1'b1; rob_queue[next_tail].ready <= 1'b0;
                    rob_queue[next_tail].id      <= alloc_decode_i[0].id;
                    rob_queue[next_tail].pc      <= alloc_decode_i[0].pc;
                    rob_queue[next_tail].rd_idx  <= alloc_decode_i[0].rd_idx;
                    rob_queue[next_tail].prf_idx <= alloc_prf_rd_i[0];
                    rob_queue[next_tail].old_prf <= alloc_old_prf_i[0]; // Kaydet
                    rob_queue[next_tail].instr   <= alloc_instr_i[0]; 
                    rob_queue[next_tail].mem_wrt <= 1'b0;
                    next_tail = next_tail + 1'b1; next_count = next_count + 1'b1;
                end
                if (alloc_valid_i[1]) begin
                    rob_queue[next_tail].valid   <= 1'b1; rob_queue[next_tail].ready <= 1'b0;
                    rob_queue[next_tail].id      <= alloc_decode_i[1].id;
                    rob_queue[next_tail].pc      <= alloc_decode_i[1].pc;
                    rob_queue[next_tail].rd_idx  <= alloc_decode_i[1].rd_idx;
                    rob_queue[next_tail].prf_idx <= alloc_prf_rd_i[1];
                    rob_queue[next_tail].old_prf <= alloc_old_prf_i[1]; // Kaydet
                    rob_queue[next_tail].instr   <= alloc_instr_i[1]; 
                    rob_queue[next_tail].mem_wrt <= 1'b0;
                    next_tail = next_tail + 1'b1; next_count = next_count + 1'b1;
                end
            end
            head <= next_head; tail <= next_tail; count <= next_count;
        end
    end
endmodule
