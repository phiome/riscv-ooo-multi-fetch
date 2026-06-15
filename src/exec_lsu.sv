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
    
    output logic [31:0]   mem_addr_o,
    output logic [31:0]   mem_wdata_o,
    output logic          mem_we_o,    
    input  logic [31:0]   mem_rdata_i,
    
    output logic [31:0]   lsu_log_addr_o,
    output logic [31:0]   lsu_log_data_o,
    output logic          lsu_log_we_o
);

    logic        delay_valid, delay_we;
    dinstr_t     delay_dec;
    logic [5:0]  delay_prf_rd;
    logic [31:0] delay_addr, delay_wdata, delay_rdata;

    always_comb begin
        mem_addr_o  = rs1_data_i + issue_decode_i.imm;
        mem_we_o    = issue_valid_i && issue_decode_i.is_store;
        
        mem_wdata_o = rs2_data_i; 
        if (issue_decode_i.op == SB) begin
            if (mem_addr_o[1:0] == 2'b00) mem_wdata_o = {mem_rdata_i[31:8], rs2_data_i[7:0]};
            else if (mem_addr_o[1:0] == 2'b01) mem_wdata_o = {mem_rdata_i[31:16], rs2_data_i[7:0], mem_rdata_i[7:0]};
            else if (mem_addr_o[1:0] == 2'b10) mem_wdata_o = {mem_rdata_i[31:24], rs2_data_i[7:0], mem_rdata_i[15:0]};
            else mem_wdata_o = {rs2_data_i[7:0], mem_rdata_i[23:0]};
        end else if (issue_decode_i.op == SH) begin
            if (mem_addr_o[1] == 1'b0) mem_wdata_o = {mem_rdata_i[31:16], rs2_data_i[15:0]};
            else mem_wdata_o = {rs2_data_i[15:0], mem_rdata_i[15:0]};
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            delay_valid <= 1'b0; delay_we <= 1'b0;
        end else begin
            delay_valid  <= issue_valid_i;
            delay_dec    <= issue_decode_i;
            delay_prf_rd <= prf_rd_i;
            delay_addr   <= mem_addr_o;
            delay_wdata  <= rs2_data_i; // LOG için orijinal store değeri
            delay_we     <= mem_we_o;
            delay_rdata  <= mem_rdata_i; // Bellek okumasını stabilize et
        end
    end

    logic [31:0] load_data;
    always_comb begin
        load_data = 32'b0;
        if (delay_dec.is_mem && !delay_dec.is_store) begin
            logic [31:0] shifted_data = delay_rdata >> (8 * delay_addr[1:0]);
            case (delay_dec.op)
                LB:  load_data = { {24{shifted_data[7]}}, shifted_data[7:0] };
                LH:  load_data = { {16{shifted_data[15]}}, shifted_data[15:0] };
                LW:  load_data = delay_rdata;
                LBU: load_data = { 24'b0, shifted_data[7:0] };
                LHU: load_data = { 16'b0, shifted_data[15:0] };
                default: load_data = delay_rdata;
            endcase
        end

        wb_valid_o  = delay_valid; wb_prf_rd_o = delay_prf_rd; wb_data_o   = load_data;
        execute_o.valid = delay_valid; execute_o.id    = delay_dec.id;
        
        lsu_log_addr_o = delay_addr; lsu_log_data_o = delay_wdata; lsu_log_we_o = delay_we;
    end
endmodule
