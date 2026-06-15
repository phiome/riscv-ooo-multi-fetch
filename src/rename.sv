`timescale 1ns/1ps

module rename import riscv_pkg::*; #(
    parameter PRF_SIZE = 64, // Fiziksel register sayısı (32 Mimari + 32 Ekstra)
    parameter ROB_SIZE = 16  // ROB kapasitesi
)(
    input  logic          clk_i,
    input  logic          rstn_i,
    
    // Decode Aşamasından Gelenler
    input  dinstr_t       decode_i [2],
    
    // Reservation Station (Issue Queue) & ROB'a Gidenler
    output logic          rename_valid_o [2], // Komut başarıyla isimlendirildi mi?
    output logic [5:0]    rename_prf_rs1_o [2], // 1. Kaynak için PRF adresi (6-bit: 0-63)
    output logic [5:0]    rename_prf_rs2_o [2], // 2. Kaynak için PRF adresi
    output logic [5:0]    rename_prf_rd_o  [2], // Hedef için atanan YENİ PRF adresi
    
    // Commit (ROB) Aşamasından Gelenler (Free List'e geri dönüş)
    input  logic          commit_valid_i [2],
    input  logic [5:0]    commit_freed_prf_i [2], // Commit edilen komutun eski PRF'si boşa çıkar
    
    // Pipeline Kontrolü
    output logic          rename_stall_o // Free list boşsa Fetch/Decode'u durdur
);

    // ----------------------------------------------------
    // Yapılar: RAT (Register Alias Table) ve Free List
    // ----------------------------------------------------
    // RAT: 32 Mimari Register'ın (ARF) hangi Fiziksel Register'da (PRF) olduğunu tutar.
    logic [5:0] rat [0:31];
    
    // Free List: Dairesel kuyruk (Circular FIFO)
    logic [5:0] free_list [0:PRF_SIZE-1];
    logic [5:0] free_head, free_tail;
    logic [6:0] free_count; // Kaç tane boş register var? (Max 64 olabilir, o yüzden 7-bit)

    // Eğer en az 2 boş fiziksel register yoksa sistemi durdur
    assign rename_stall_o = (free_count < 2);

    // ----------------------------------------------------
    // 1. Kombinasyonel Mantık (Rename İşlemi)
    // ----------------------------------------------------
    always_comb begin
        // Varsayılan değerler
        rename_valid_o[0] = 1'b0;
        rename_valid_o[1] = 1'b0;
        
        rename_prf_rs1_o[0] = '0;
        rename_prf_rs2_o[0] = '0;
        rename_prf_rd_o[0]  = '0;
        
        rename_prf_rs1_o[1] = '0;
        rename_prf_rs2_o[1] = '0;
        rename_prf_rd_o[1]  = '0;

        if (!rename_stall_o) begin
            // --- KOMUT 1 (Eski olan komut) ---
            if (decode_i[0].valid) begin
                rename_valid_o[0] = 1'b1;
                
                // Kaynakları Oku (R0 her zaman 0'dır, rename edilmez)
                rename_prf_rs1_o[0] = (decode_i[0].rs1_idx == 0) ? '0 : rat[decode_i[0].rs1_idx];
                rename_prf_rs2_o[0] = (decode_i[0].rs2_idx == 0) ? '0 : rat[decode_i[0].rs2_idx];
                
                // Hedef Oku (Eğer hedefe yazıyorsa)
                if (decode_i[0].rd_used && decode_i[0].rd_idx != 0) begin
                    rename_prf_rd_o[0] = free_list[free_head]; // İlk boş register'ı al
                end
            end

            // --- KOMUT 2 (Yeni olan komut) ---
            if (decode_i[1].valid) begin
                rename_valid_o[1] = 1'b1;
                
                // KAYNAK 1 İÇİN INTRA-GROUP BAĞIMLILIK KONTROLÜ
                // Eğer Komut 2, Komut 1'in yazdığı register'ı okuyorsa (RAW hazard):
                if (decode_i[1].rs1_used && decode_i[1].rs1_idx != 0 && 
                    decode_i[0].valid && decode_i[0].rd_used && 
                    decode_i[1].rs1_idx == decode_i[0].rd_idx) begin
                    
                    rename_prf_rs1_o[1] = free_list[free_head]; // Komut 1'in yeni atandığı PRF'yi oku!
                    
                end else begin
                    rename_prf_rs1_o[1] = (decode_i[1].rs1_idx == 0) ? '0 : rat[decode_i[1].rs1_idx];
                end

                // KAYNAK 2 İÇİN INTRA-GROUP BAĞIMLILIK KONTROLÜ
                if (decode_i[1].rs2_used && decode_i[1].rs2_idx != 0 && 
                    decode_i[0].valid && decode_i[0].rd_used && 
                    decode_i[1].rs2_idx == decode_i[0].rd_idx) begin
                    
                    rename_prf_rs2_o[1] = free_list[free_head];
                    
                end else begin
                    rename_prf_rs2_o[1] = (decode_i[1].rs2_idx == 0) ? '0 : rat[decode_i[1].rs2_idx];
                end

                // Hedef Oku (Eğer hedefe yazıyorsa)
                if (decode_i[1].rd_used && decode_i[1].rd_idx != 0) begin
                    // Eğer Komut 1 de hedefe yazdıysa, sıradaki İKİNCİ boş register'ı al
                    if (decode_i[0].valid && decode_i[0].rd_used && decode_i[0].rd_idx != 0) begin
                         // Modulo aritmetiği (dairesel kuyruk için)
                         rename_prf_rd_o[1] = free_list[(free_head + 1) % PRF_SIZE]; 
                    end else begin
                         rename_prf_rd_o[1] = free_list[free_head]; // Sadece Komut 2 hedefe yazıyorsa
                    end
                end
            end
        end
    end

    // ----------------------------------------------------
    // 2. Senkron Güncelleme (RAT ve Free List Durumu)
    // ----------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            // Reset Durumu
            free_head  <= '0;
            
            // Başlangıçta ilk 32 PRF, ilk 32 ARF ile eşleşiktir.
            for (integer i = 0; i < 32; i++) begin
                rat[i] <= i[5:0];
            end
            
            // Geriye kalan 32 PRF boştadır ve Free List'e konur.
            for (integer i = 32; i < PRF_SIZE; i++) begin
                free_list[i-32] <= i[5:0];
            end
            
            free_tail  <= 32; // Kuyruğun sonu
            free_count <= 32; // 32 boş register var
            
        end else begin
            // Geçici değişkenler
            logic [6:0] new_free_count = free_count;
            logic [5:0] new_free_head  = free_head;
            logic [5:0] new_free_tail  = free_tail;

            // --- 1. COMMIT İŞLEMİ (Register'ları Boşa Çıkarma) ---
            // Eski, üzerine yazılmış olan PRF'ler Commit aşamasında serbest bırakılır.
            if (commit_valid_i[0]) begin
                free_list[new_free_tail] <= commit_freed_prf_i[0];
                new_free_tail = new_free_tail + 1'b1;
                new_free_count = new_free_count + 1;
            end
            if (commit_valid_i[1]) begin
                free_list[new_free_tail] <= commit_freed_prf_i[1];
                new_free_tail = new_free_tail + 1'b1;
                new_free_count = new_free_count + 1;
            end

            // --- 2. RENAME İŞLEMİ (Register Tahsisi) ---
            if (!rename_stall_o) begin
                if (decode_i[0].valid && decode_i[0].rd_used && decode_i[0].rd_idx != 0) begin
                    rat[decode_i[0].rd_idx] <= free_list[new_free_head]; // RAT'ı güncelle
                    new_free_head = new_free_head + 1'b1;
                    new_free_count = new_free_count - 1;
                end
                
                if (decode_i[1].valid && decode_i[1].rd_used && decode_i[1].rd_idx != 0) begin
                    rat[decode_i[1].rd_idx] <= free_list[new_free_head]; // RAT'ı güncelle
                    // Eğer Komut 1 ve Komut 2 aynı register'a yazıyorsa (WAW hazard),
                    // RAT sadece Komut 2'nin atamasını (en son değeri) tutar. Bu doğrudur.
                    new_free_head = new_free_head + 1'b1;
                    new_free_count = new_free_count - 1;
                end
            end
            
            // Pointer ve Count değerlerini kalıcı hale getir
            free_head  <= new_free_head;
            free_tail  <= new_free_tail;
            free_count <= new_free_count;
        end
    end

endmodule
