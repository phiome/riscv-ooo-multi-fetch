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
    
    output logic [31:0]   mem_raddr_o, 
    input  logic [31:0]   mem_rdata_i, 
    
    output logic [31:0]   mem_waddr_o, 
    output logic [31:0]   mem_wdata_o, 
    output logic          mem_we_o,    
    
    output logic [31:0]   lsu_log_addr_o,
    output logic [31:0]   lsu_log_data_o,
    output logic          lsu_log_we_o
);

    logic [31:0] combo_addr;
    assign combo_addr  = rs1_data_i + issue_decode_i.imm;
    assign mem_raddr_o = combo_addr;

    // 1 cycle buffer
    logic        delay_valid;
    dinstr_t     delay_dec;
    logic [5:0]  delay_prf_rd;
    logic [31:0] delay_addr, delay_wdata_raw, delay_rdata;

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            delay_valid <= 1'b0;
        end else begin
            delay_valid     <= issue_valid_i;
            delay_dec       <= issue_decode_i;
            delay_prf_rd    <= prf_rd_i;
            delay_addr      <= combo_addr;
            delay_wdata_raw <= rs2_data_i;
            delay_rdata     <= mem_rdata_i; 
        end
    end

    //  masking for latch errors
    logic [31:0] shifted_rdata;
    logic [31:0] load_data;
    logic [31:0] masked_wdata;

    always_comb begin
        shifted_rdata = 32'b0;
        load_data     = 32'b0;
        masked_wdata  = delay_wdata_raw;

        // LOAD mask
        if (delay_dec.is_mem && !delay_dec.is_store) begin
            shifted_rdata = delay_rdata >> (8 * delay_addr[1:0]);
            case (delay_dec.op)
                LB:  load_data = { {24{shifted_rdata[7]}}, shifted_rdata[7:0] };
                LH:  load_data = { {16{shifted_rdata[15]}}, shifted_rdata[15:0] };
                LW:  load_data = delay_rdata;
                LBU: load_data = { 24'b0, shifted_rdata[7:0] };
                LHU: load_data = { 16'b0, shifted_rdata[15:0] };
                default: load_data = delay_rdata;
            endcase
        end

        // STORE masking
        if (delay_dec.is_mem && delay_dec.is_store) begin
            if (delay_dec.op == SB) begin
                if (delay_addr[1:0] == 2'b00) masked_wdata = {delay_rdata[31:8], delay_wdata_raw[7:0]};
                else if (delay_addr[1:0] == 2'b01) masked_wdata = {delay_rdata[31:16], delay_wdata_raw[7:0], delay_rdata[7:0]};
                else if (delay_addr[1:0] == 2'b10) masked_wdata = {delay_rdata[31:24], delay_wdata_raw[7:0], delay_rdata[15:0]};
                else masked_wdata = {delay_wdata_raw[7:0], delay_rdata[23:0]};
            end else if (delay_dec.op == SH) begin
                if (delay_addr[1] == 1'b0) masked_wdata = {delay_rdata[31:16], delay_wdata_raw[15:0]};
                else masked_wdata = {delay_wdata_raw[15:0], delay_rdata[15:0]};
            end
        end

        wb_valid_o  = delay_valid;
        wb_prf_rd_o = delay_prf_rd;
        wb_data_o   = load_data;

        execute_o.valid = delay_valid;
        execute_o.id    = delay_dec.id;

        mem_waddr_o = delay_addr;
        mem_wdata_o = masked_wdata;
        mem_we_o    = delay_valid && delay_dec.is_store;

        lsu_log_addr_o = delay_addr;
        lsu_log_data_o = delay_wdata_raw; 
        lsu_log_we_o   = delay_valid && delay_dec.is_store;
    end
endmodule
