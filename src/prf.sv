`timescale 1ns/1ps

module prf import riscv_pkg::*; #(
    parameter PRF_SIZE = 64
)(
    input  logic        clk_i,
    input  logic        rstn_i,

    // --- 6 OKUMA PORTU (Asenkron / Combinational) ---
    // Unit 0 (ALU+Branch)
    input  logic [5:0]  rd_addr_0_1, output logic [31:0] rd_data_0_1,
    input  logic [5:0]  rd_addr_0_2, output logic [31:0] rd_data_0_2,
    
    // Unit 1 (ALU)
    input  logic [5:0]  rd_addr_1_1, output logic [31:0] rd_data_1_1,
    input  logic [5:0]  rd_addr_1_2, output logic [31:0] rd_data_1_2,
    
    // Unit 2 (LSU)
    input  logic [5:0]  rd_addr_2_1, output logic [31:0] rd_data_2_1,
    input  logic [5:0]  rd_addr_2_2, output logic [31:0] rd_data_2_2,

    // --- 3 YAZMA PORTU (Senkron / Writeback - CDB) ---
    input  logic        wb_en_0, input logic [5:0] wb_addr_0, input logic [31:0] wb_data_0,
    input  logic        wb_en_1, input logic [5:0] wb_addr_1, input logic [31:0] wb_data_1,
    input  logic        wb_en_2, input logic [5:0] wb_addr_2, input logic [31:0] wb_data_2
);

    logic [31:0] registers [0:PRF_SIZE-1];

    // Okuma İşlemleri (R0/P0 her zaman 0 döner)
    assign rd_data_0_1 = (rd_addr_0_1 == 0) ? 32'b0 : registers[rd_addr_0_1];
    assign rd_data_0_2 = (rd_addr_0_2 == 0) ? 32'b0 : registers[rd_addr_0_2];
    
    assign rd_data_1_1 = (rd_addr_1_1 == 0) ? 32'b0 : registers[rd_addr_1_1];
    assign rd_data_1_2 = (rd_addr_1_2 == 0) ? 32'b0 : registers[rd_addr_1_2];
    
    assign rd_data_2_1 = (rd_addr_2_1 == 0) ? 32'b0 : registers[rd_addr_2_1];
    assign rd_data_2_2 = (rd_addr_2_2 == 0) ? 32'b0 : registers[rd_addr_2_2];

    // Yazma İşlemleri
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            for (int i = 0; i < PRF_SIZE; i++) registers[i] <= 32'b0;
        end else begin
            if (wb_en_0 && wb_addr_0 != 0) registers[wb_addr_0] <= wb_data_0;
            if (wb_en_1 && wb_addr_1 != 0) registers[wb_addr_1] <= wb_data_1;
            if (wb_en_2 && wb_addr_2 != 0) registers[wb_addr_2] <= wb_data_2;
        end
    end

endmodule
