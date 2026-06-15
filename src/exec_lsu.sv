`timescale 1ns/1ps

module exec_lsu import riscv_pkg::*; (
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
    
    // Bellek Sinyalleri (Top modüldeki dmem'e bağlanacak)
    output logic [31:0]   mem_addr_o,
    output logic [31:0]   mem_wdata_o,
    output logic          mem_we_o,    // Write Enable
    input  logic [31:0]   mem_rdata_i  // Bellekten okunan veri
);

    // 1 Cycle Gecikme İçin Pipeline Registerları
    logic        delay_valid;
    dinstr_t     delay_dec;
    logic [5:0]  delay_prf_rd;
    logic [31:0] delay_addr;
    logic [31:0] delay_wdata;

    // --- Aşama 1: Adres Hesaplama (Execute) ---
    always_comb begin
        // Load ve Store için adres her zaman: RS1 + IMM
        mem_addr_o  = rs1_data_i + issue_decode_i.imm;
        mem_wdata_o = rs2_data_i; // Store ise yazılacak veri
        mem_we_o    = issue_valid_i && issue_decode_i.is_store;
    end

    // Gecikme (Latency) Flip-Flopu
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            delay_valid <= 1'b0;
        end else begin
            // Eğer yeni bir komut geldiyse, onu pipeline'a al
            delay_valid  <= issue_valid_i;
            delay_dec    <= issue_decode_i;
            delay_prf_rd <= prf_rd_i;
            delay_addr   <= mem_addr_o;
        end
    end

    // --- Aşama 2: Writeback & Memory Read (1 Cycle Sonra) ---
    logic [31:0] load_data;
    
    always_comb begin
        load_data = 32'b0;
        
        // Okunan veriyi maskeleme (Byte/Halfword işlemleri)
        if (delay_dec.is_mem && !delay_dec.is_store) begin
            case (delay_dec.op)
                LB:  load_data = { {24{mem_rdata_i[7]}}, mem_rdata_i[7:0] };
                LH:  load_data = { {16{mem_rdata_i[15]}}, mem_rdata_i[15:0] };
                LW:  load_data = mem_rdata_i;
                LBU: load_data = { 24'b0, mem_rdata_i[7:0] };
                LHU: load_data = { 16'b0, mem_rdata_i[15:0] };
                default: load_data = mem_rdata_i;
            endcase
        end

        // Geciktirilmiş Çıkışları Ata
        wb_valid_o  = delay_valid;
        wb_prf_rd_o = delay_prf_rd;
        wb_data_o   = load_data;
        
        execute_o.valid = delay_valid;
        execute_o.id    = delay_dec.id;
    end

endmodule

