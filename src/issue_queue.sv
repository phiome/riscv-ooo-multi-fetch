`timescale 1ns/1ps

module issue_queue import riscv_pkg::*; #(
    parameter IQ_SIZE = 16
)(
    input  logic          clk_i,
    input  logic          rstn_i,
    
    input  logic          alloc_valid_i [2],
    input  dinstr_t       alloc_decode_i [2],
    input  logic [5:0]    alloc_prf_rs1_i [2],
    input  logic [5:0]    alloc_prf_rs2_i [2],
    input  logic [5:0]    alloc_prf_rd_i [2],
    
    output logic          iq_stall_o,
    
    input  logic          wb_valid_i [3], 
    input  logic [5:0]    wb_prf_rd_i [3],
    
    output logic          issue_valid_0_o,
    output dinstr_t       issue_decode_0_o,
    output logic [5:0]    issue_prf_rs1_0_o, issue_prf_rs2_0_o, issue_prf_rd_0_o,
    
    output logic          issue_valid_1_o,
    output dinstr_t       issue_decode_1_o,
    output logic [5:0]    issue_prf_rs1_1_o, issue_prf_rs2_1_o, issue_prf_rd_1_o,
    
    output logic          issue_valid_2_o,
    output dinstr_t       issue_decode_2_o,
    output logic [5:0]    issue_prf_rs1_2_o, issue_prf_rs2_2_o, issue_prf_rd_2_o
);

    typedef struct packed {
        logic       valid;
        dinstr_t    dec;
        logic [5:0] prf_rs1;
        logic [5:0] prf_rs2;
        logic [5:0] prf_rd;
        logic       rs1_ready; 
        logic       rs2_ready; 
    } iq_entry_t;

    iq_entry_t iq [0:IQ_SIZE-1];
    logic prf_ready_table [0:63];
    logic [$clog2(IQ_SIZE):0] count;
    assign iq_stall_o = (count >= (IQ_SIZE - 2));

    logic [IQ_SIZE-1:0] ready_for_alu_br, ready_for_alu, ready_for_lsu;
    logic [$clog2(IQ_SIZE)-1:0] sel_0, sel_1, sel_2;
    logic found_0, found_1, found_2;

    always_comb begin
        for (int i = 0; i < IQ_SIZE; i++) begin
            logic is_ready = iq[i].valid && iq[i].rs1_ready && iq[i].rs2_ready;
            ready_for_alu_br[i] = is_ready && (iq[i].dec.is_branch || iq[i].dec.is_jump || (!iq[i].dec.is_mem && !iq[i].dec.is_branch)); 
            ready_for_alu[i]    = is_ready && (!iq[i].dec.is_mem && !iq[i].dec.is_branch && !iq[i].dec.is_jump);
            ready_for_lsu[i]    = is_ready && iq[i].dec.is_mem;
        end

        found_0 = 1'b0; sel_0 = '0;
        found_1 = 1'b0; sel_1 = '0;
        found_2 = 1'b0; sel_2 = '0;

        for (int i = 0; i < IQ_SIZE; i++) begin
            if (ready_for_alu_br[i] && !found_0) begin found_0 = 1'b1; sel_0 = i[$clog2(IQ_SIZE)-1:0]; end
        end
        for (int i = 0; i < IQ_SIZE; i++) begin
            if (ready_for_alu[i] && (!found_0 || sel_0 != i[3:0]) && !found_1) begin found_1 = 1'b1; sel_1 = i[$clog2(IQ_SIZE)-1:0]; end
        end
        for (int i = 0; i < IQ_SIZE; i++) begin
            if (ready_for_lsu[i] && !found_2) begin found_2 = 1'b1; sel_2 = i[$clog2(IQ_SIZE)-1:0]; end
        end
        
        issue_valid_0_o = found_0; issue_decode_0_o = found_0 ? iq[sel_0].dec : '0;
        issue_prf_rs1_0_o = found_0 ? iq[sel_0].prf_rs1 : '0; issue_prf_rs2_0_o = found_0 ? iq[sel_0].prf_rs2 : '0; issue_prf_rd_0_o = found_0 ? iq[sel_0].prf_rd : '0;
        
        issue_valid_1_o = found_1; issue_decode_1_o = found_1 ? iq[sel_1].dec : '0;
        issue_prf_rs1_1_o = found_1 ? iq[sel_1].prf_rs1 : '0; issue_prf_rs2_1_o = found_1 ? iq[sel_1].prf_rs2 : '0; issue_prf_rd_1_o = found_1 ? iq[sel_1].prf_rd : '0;
        
        issue_valid_2_o = found_2; issue_decode_2_o = found_2 ? iq[sel_2].dec : '0;
        issue_prf_rs1_2_o = found_2 ? iq[sel_2].prf_rs1 : '0; issue_prf_rs2_2_o = found_2 ? iq[sel_2].prf_rs2 : '0; issue_prf_rd_2_o = found_2 ? iq[sel_2].prf_rd : '0;
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            count <= '0;
            for (int i = 0; i < IQ_SIZE; i++) iq[i].valid <= 1'b0;
            for (int i = 0; i < 64; i++) prf_ready_table[i] <= 1'b1;
        end else begin
            logic [$clog2(IQ_SIZE):0] next_count = count;
            logic [IQ_SIZE-1:0] allocated_mask = '0;

            // 1. WAKEUP 
            for (int w = 0; w < 3; w++) begin
                if (wb_valid_i[w] && wb_prf_rd_i[w] != 0) begin
                    prf_ready_table[wb_prf_rd_i[w]] <= 1'b1; 
                    for (int i = 0; i < IQ_SIZE; i++) begin
                        if (iq[i].valid) begin
                            if (iq[i].prf_rs1 == wb_prf_rd_i[w]) iq[i].rs1_ready <= 1'b1;
                            if (iq[i].prf_rs2 == wb_prf_rd_i[w]) iq[i].rs2_ready <= 1'b1;
                        end
                    end
                end
            end

            // 2. CLEAR 
            if (found_0) begin iq[sel_0].valid <= 1'b0; next_count = next_count - 1'b1; end
            if (found_1) begin iq[sel_1].valid <= 1'b0; next_count = next_count - 1'b1; end
            if (found_2) begin iq[sel_2].valid <= 1'b0; next_count = next_count - 1'b1; end

// 3. ALLOCATE
            if (!iq_stall_o) begin
                for (int a = 0; a < 2; a++) begin
                    if (alloc_valid_i[a]) begin
                        // ÇÖZÜM: Değişkenleri bloğun en başında tanımlıyoruz!
                        logic rs1_rdy;
                        logic rs2_rdy;

                        if (alloc_decode_i[a].rd_used && alloc_decode_i[a].rd_idx != 0) begin
                            prf_ready_table[alloc_prf_rd_i[a]] <= 1'b0;
                        end
                        
                        // CDB Bypass Mantığı (Sadece değer ataması yapıyoruz)
                        rs1_rdy = (!alloc_decode_i[a].rs1_used || alloc_decode_i[a].rs1_idx == 0 || prf_ready_table[alloc_prf_rs1_i[a]]);
                        rs2_rdy = (!alloc_decode_i[a].rs2_used || alloc_decode_i[a].rs2_idx == 0 || prf_ready_table[alloc_prf_rs2_i[a]]);
                        
                        for (int w = 0; w < 3; w++) begin
                            if (wb_valid_i[w] && wb_prf_rd_i[w] != 0) begin
                                if (alloc_prf_rs1_i[a] == wb_prf_rd_i[w]) rs1_rdy = 1'b1;
                                if (alloc_prf_rs2_i[a] == wb_prf_rd_i[w]) rs2_rdy = 1'b1;
                            end
                        end

                        for (int i = 0; i < IQ_SIZE; i++) begin
                            if (!iq[i].valid && !allocated_mask[i] && (!found_0 || sel_0 != i[3:0]) && (!found_1 || sel_1 != i[3:0]) && (!found_2 || sel_2 != i[3:0])) begin
                                allocated_mask[i] = 1'b1;
                                iq[i].valid     <= 1'b1; iq[i].dec <= alloc_decode_i[a];
                                iq[i].prf_rs1   <= alloc_prf_rs1_i[a]; iq[i].prf_rs2 <= alloc_prf_rs2_i[a]; iq[i].prf_rd <= alloc_prf_rd_i[a];
                                iq[i].rs1_ready <= rs1_rdy;
                                iq[i].rs2_ready <= rs2_rdy;
                                next_count = next_count + 1'b1;
                                break;
                            end
                        end
                    end
                end
            end
                        for (int i = 0; i < IQ_SIZE; i++) begin
                            if (!iq[i].valid && !allocated_mask[i] && (!found_0 || sel_0 != i[3:0]) && (!found_1 || sel_1 != i[3:0]) && (!found_2 || sel_2 != i[3:0])) begin
                                allocated_mask[i] = 1'b1;
                                iq[i].valid     <= 1'b1; iq[i].dec <= alloc_decode_i[a];
                                iq[i].prf_rs1   <= alloc_prf_rs1_i[a]; iq[i].prf_rs2 <= alloc_prf_rs2_i[a]; iq[i].prf_rd <= alloc_prf_rd_i[a];
                                iq[i].rs1_ready <= rs1_rdy;
                                iq[i].rs2_ready <= rs2_rdy;
                                next_count = next_count + 1'b1;
                                break;
                            end
                        end
                    end
                end
            end
            count <= next_count;
        end
    end
endmodule
