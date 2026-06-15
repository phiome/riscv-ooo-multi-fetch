`timescale 1ns/1ps

module rob import riscv_pkg::*; #(
    parameter ROB_SIZE = 16
)(
    input  logic          clk_i,
    input  logic          rstn_i,
    
    // ----------------------------------------------------
    // Allocation Interface (Rename/Dispatch Aşamasından)
    // ----------------------------------------------------
    input  logic          alloc_valid_i [2], // 1. ve 2. komut geçerli mi?
    input  dinstr_t       alloc_decode_i [2], // Komut bilgileri (ID, PC vs.)
    input  logic [5:0]    alloc_prf_rd_i [2], // Atanan Yeni PRF
    
    output logic          rob_stall_o, // ROB doluysa sistemi durdur
    
    // ----------------------------------------------------
    // Execution Writeback Interface (Execution Ünitelerinden)
    // ----------------------------------------------------
    // Hangi komutların yürütmesi bitti? (3 Ünite: A, B, C)
    input  execute_t      execute_i [3], 
    
    // ----------------------------------------------------
    // Commit Interface (Top Module ve Konata'ya)
    // ----------------------------------------------------
    output commit_t       commit_o [2],
    
    // Free List'e geri gönderilecek eski fiziksel register'lar için
    // (Şimdilik basit tutmak adına doğrudan Commit_o içinden de okunabilir, 
    // ancak Rename modülü commit_valid_i bekliyor)
    output logic          commit_valid_o [2]
);

    // ROB Entry Yapısı
    typedef struct packed {
        logic       valid;   // Entry dolu mu?
        logic       ready;   // Yürütme bitti mi?
        logic[31:0] id;      // Konata için eşsiz ID
        logic[31:0] pc;      // Konata için PC
        logic[4:0]  rd_idx;  // Mimari Register (ARF)
        logic[5:0]  prf_idx; // Fiziksel Register (PRF)
    } rob_entry_t;

    rob_entry_t rob_queue [0:ROB_SIZE-1];
    
    logic [$clog2(ROB_SIZE)-1:0] head, tail;
    logic [$clog2(ROB_SIZE):0]   count; // Kapasite takibi

    // ROB'da en az 2 boş yer yoksa stall (durma) sinyali üret
    assign rob_stall_o = (count >= (ROB_SIZE - 2));

    // ----------------------------------------------------
    // Senkron ROB Mantığı
    // ----------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            head  <= '0;
            tail  <= '0;
            count <= '0;
            for (integer i = 0; i < ROB_SIZE; i++) begin
                rob_queue[i] <= '0;
            end
            
            commit_o[0] <= '0;
            commit_o[1] <= '0;
            commit_valid_o[0] <= 1'b0;
            commit_valid_o[1] <= 1'b0;
        end else begin
            // Geçici pointer ve sayacımız
            logic [$clog2(ROB_SIZE)-1:0] next_head = head;
            logic [$clog2(ROB_SIZE)-1:0] next_tail = tail;
            logic [$clog2(ROB_SIZE):0]   next_count = count;

            // Varsayılan Commit Sinyalleri (Her çevrim sıfırlanmalı)
            commit_o[0] <= '0;
            commit_o[1] <= '0;
            commit_valid_o[0] <= 1'b0;
            commit_valid_o[1] <= 1'b0;

            // --- 1. COMMIT İŞLEMİ (In-Order Çıkış) ---
            // Başlangıçtaki komut hazır mı? (Yürütmesi bitmiş mi?)
            if (next_count > 0 && rob_queue[next_head].valid && rob_queue[next_head].ready) begin
                
                // Konata Loglama için struct'ı doldur
                commit_o[0].valid    <= 1'b1;
                commit_o[0].id       <= rob_queue[next_head].id;
                commit_o[0].pc       <= rob_queue[next_head].pc;
                commit_o[0].reg_addr <= rob_queue[next_head].rd_idx;
                
                // Rename modülüne haber ver
                commit_valid_o[0]    <= 1'b1;
                
                // ROB'dan sil
                rob_queue[next_head].valid <= 1'b0;
                next_head = next_head + 1'b1;
                next_count = next_count - 1;

                // İkinci komut da hazır mı? (Dual-Commit)
                if (next_count > 0 && rob_queue[next_head].valid && rob_queue[next_head].ready) begin
                    commit_o[1].valid    <= 1'b1;
                    commit_o[1].id       <= rob_queue[next_head].id;
                    commit_o[1].pc       <= rob_queue[next_head].pc;
                    commit_o[1].reg_addr <= rob_queue[next_head].rd_idx;
                    
                    commit_valid_o[1]    <= 1'b1;
                    
                    rob_queue[next_head].valid <= 1'b0;
                    next_head = next_head + 1'b1;
                    next_count = next_count - 1;
                end
            end

            // --- 2. EXECUTE WRITEBACK (Out-of-Order Tamamlama İşareti) ---
            // Yürütme üniteleri biten komutların ID'sini gönderir. ROB içinde bu ID'leri arayıp 'ready' yaparız.
            // (Donanım sentezinde CAM - Content Addressable Memory mantığıyla çalışır)
            for (integer i = 0; i < ROB_SIZE; i++) begin
                if (rob_queue[i].valid && !rob_queue[i].ready) begin
                    // Unit A, B veya C'den gelen ID eşleşiyor mu?
                    if ((execute_i[0].valid && execute_i[0].id == rob_queue[i].id) ||
                        (execute_i[1].valid && execute_i[1].id == rob_queue[i].id) ||
                        (execute_i[2].valid && execute_i[2].id == rob_queue[i].id)) begin
                        
                        rob_queue[i].ready <= 1'b1; // Artık Commit edilebilir!
                    end
                end
            end

            // --- 3. ALLOCATION (Sırayla Kuyruğa Ekleme) ---
            if (!rob_stall_o) begin
                if (alloc_valid_i[0]) begin
                    rob_queue[next_tail].valid   <= 1'b1;
                    rob_queue[next_tail].ready   <= 1'b0; // Henüz çalışmadı
                    rob_queue[next_tail].id      <= alloc_decode_i[0].id;
                    rob_queue[next_tail].pc      <= alloc_decode_i[0].pc;
                    rob_queue[next_tail].rd_idx  <= alloc_decode_i[0].rd_idx;
                    rob_queue[next_tail].prf_idx <= alloc_prf_rd_i[0];
                    
                    next_tail = next_tail + 1'b1;
                    next_count = next_count + 1;
                end
                
                if (alloc_valid_i[1]) begin
                    rob_queue[next_tail].valid   <= 1'b1;
                    rob_queue[next_tail].ready   <= 1'b0;
                    rob_queue[next_tail].id      <= alloc_decode_i[1].id;
                    rob_queue[next_tail].pc      <= alloc_decode_i[1].pc;
                    rob_queue[next_tail].rd_idx  <= alloc_decode_i[1].rd_idx;
                    rob_queue[next_tail].prf_idx <= alloc_prf_rd_i[1];
                    
                    next_tail = next_tail + 1'b1;
                    next_count = next_count + 1;
                end
            end

            // Pointer'ları güncelle
            head  <= next_head;
            tail  <= next_tail;
            count <= next_count;
        end
    end

endmodule

