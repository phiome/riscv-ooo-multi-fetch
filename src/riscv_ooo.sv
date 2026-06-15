`timescale 1 ns / 1 ps

module riscv_ooo import riscv_pkg::*; #(
    parameter DMemInitFile = "dmem.mem",
    parameter IMemInitFile = "imem.mem"
) (
    input  logic            clk_i,
    input  logic            rstn_i,
    input  logic [XLEN-1:0] addr_i,
    output logic [XLEN-1:0] data_o,
    
    output dinstr_t         decode_o  [2], 
    output execute_t        execute_o [3], 
    output commit_t         commit_o  [2]  
);

    logic [31:0] instr_mem [0:2047];
    logic [31:0] data_mem  [0:2047];

    initial begin
        $readmemh(IMemInitFile, instr_mem, 0, 2047);
        $readmemh(DMemInitFile, data_mem,  0, 2047);
    end

    assign data_o = data_mem[addr_i[12:2]]; 

    // --- STALL KONTROLLERİ ---
    logic fetch_stall, rename_stall, rob_stall, iq_stall, branch_in_flight;
    assign fetch_stall = rename_stall | rob_stall | iq_stall | branch_in_flight;

    logic        branch_resolved, branch_taken;
    logic [31:0] branch_target, fallthrough_pc;

    logic [31:0] pc_q, instr_id_counter;
    logic [31:0] fetched_pc_1, fetched_pc_2;
    logic [31:0] fetched_instr_1, fetched_instr_2;
    
    assign fetched_pc_1 = pc_q;
    assign fetched_pc_2 = pc_q + 4;
    assign fetched_instr_1 = instr_mem[fetched_pc_1[12:2]];
    assign fetched_instr_2 = instr_mem[fetched_pc_2[12:2]];

    dinstr_t dec_1, dec_2;
    decoder dec_inst_1 (.clk_i(clk_i), .instr_i(fetched_instr_1), .pc_i(fetched_pc_1), .id_i(instr_id_counter),   .dinstr_o(dec_1));
    decoder dec_inst_2 (.clk_i(clk_i), .instr_i(fetched_instr_2), .pc_i(fetched_pc_2), .id_i(instr_id_counter+1), .dinstr_o(dec_2));

    // --- FETCH AŞAMASI (Güvenli Branch Bekletme) ---
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            branch_in_flight <= 1'b0;
            fallthrough_pc   <= '0;
        end else begin
            if (branch_resolved) begin
                branch_in_flight <= 1'b0;
            end else if (!fetch_stall) begin
                if (dec_1.valid && (dec_1.is_branch || dec_1.is_jump)) begin
                    branch_in_flight <= 1'b1;
                    fallthrough_pc   <= fetched_pc_2; 
                end else if (dec_2.valid && (dec_2.is_branch || dec_2.is_jump)) begin
                    branch_in_flight <= 1'b1;
                    fallthrough_pc   <= pc_q + 8;
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            pc_q <= '0;
            instr_id_counter <= 1; 
        end else begin
            if (branch_resolved) begin
                pc_q <= branch_taken ? branch_target : fallthrough_pc;
            end else if (!fetch_stall) begin
                if (dec_1.valid && (dec_1.is_branch || dec_1.is_jump)) begin
                    pc_q <= pc_q; // Bekle
                    instr_id_counter <= instr_id_counter + 1; 
                end else begin
                    pc_q <= pc_q + 8;
                    instr_id_counter <= instr_id_counter + 2;
                end
            end
        end
    end

    always_comb begin
        decode_o[0] = '0; decode_o[1] = '0;
        if (!fetch_stall) begin
            if (dec_1.valid) begin
                decode_o[0] = dec_1;
                // dec_1 Branch ise, dec_2 çöpe atılır (Spekülasyon engellendi)
                if (!(dec_1.is_branch || dec_1.is_jump) && dec_2.valid) decode_o[1] = dec_2;
            end
        end
    end

    // --- RENAME ---
    logic       ren_valid [2];
    logic [5:0] ren_rs1 [2], ren_rs2 [2], ren_rd [2];
    logic       com_valid [2]; logic [5:0] com_freed [2]; 

    rename rename_inst (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .decode_i          (decode_o), 
        .rename_valid_o    (ren_valid),
        .rename_prf_rs1_o  (ren_rs1), .rename_prf_rs2_o  (ren_rs2), .rename_prf_rd_o   (ren_rd),
        .commit_valid_i    (com_valid), .commit_freed_prf_i(com_freed),
        .rename_stall_o    (rename_stall)
    );

    // --- ROB ---
    execute_t exec_res [3]; 
    assign exec_res[0] = execute_o[0]; assign exec_res[1] = execute_o[1]; assign exec_res[2] = execute_o[2];

    logic [31:0] alloc_instr [2];
    assign alloc_instr[0] = fetched_instr_1; assign alloc_instr[1] = fetched_instr_2;
    logic [31:0] wb_data [3]; 
    
    logic [31:0] lsu_log_addr, lsu_log_data;
    logic        lsu_log_we;
    logic [31:0] rob_head_id;

    rob rob_inst (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .alloc_valid_i (ren_valid), .alloc_decode_i(decode_o), .alloc_prf_rd_i(ren_rd), .alloc_instr_i(alloc_instr),
        .rob_stall_o   (rob_stall), .rob_head_id_o(rob_head_id),
        .execute_i     (exec_res),  .wb_data_i    (wb_data),
        .lsu_log_addr_i(lsu_log_addr), .lsu_log_data_i(lsu_log_data), .lsu_log_we_i(lsu_log_we),
        .commit_o      (commit_o),  .commit_valid_o(com_valid)
    );
    assign com_freed[0] = '0; assign com_freed[1] = '0; 

    // --- ISSUE QUEUE ---
    logic       wb_valid [3];
    logic [5:0] wb_prf_rd [3];
    logic iss_v_0, iss_v_1, iss_v_2;
    dinstr_t iss_dec_0, iss_dec_1, iss_dec_2;
    logic [5:0] iss_rs1_0, iss_rs2_0, iss_rd_0, iss_rs1_1, iss_rs2_1, iss_rd_1, iss_rs1_2, iss_rs2_2, iss_rd_2;

    issue_queue iq_inst (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .alloc_valid_i  (ren_valid), .alloc_decode_i (decode_o),
        .alloc_prf_rs1_i(ren_rs1), .alloc_prf_rs2_i(ren_rs2), .alloc_prf_rd_i(ren_rd),
        .iq_stall_o     (iq_stall), .rob_head_id_i  (rob_head_id),
        .wb_valid_i     (wb_valid), .wb_prf_rd_i    (wb_prf_rd),
        .issue_valid_0_o(iss_v_0), .issue_decode_0_o(iss_dec_0), .issue_prf_rs1_0_o(iss_rs1_0), .issue_prf_rs2_0_o(iss_rs2_0), .issue_prf_rd_0_o(iss_rd_0),
        .issue_valid_1_o(iss_v_1), .issue_decode_1_o(iss_dec_1), .issue_prf_rs1_1_o(iss_rs1_1), .issue_prf_rs2_1_o(iss_rs2_1), .issue_prf_rd_1_o(iss_rd_1),
        .issue_valid_2_o(iss_v_2), .issue_decode_2_o(iss_dec_2), .issue_prf_rs1_2_o(iss_rs1_2), .issue_prf_rs2_2_o(iss_rs2_2), .issue_prf_rd_2_o(iss_rd_2)
    );

    // --- PRF ---
    logic [31:0] r_data_0_1, r_data_0_2, r_data_1_1, r_data_1_2, r_data_2_1, r_data_2_2;
    prf prf_inst (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .rd_addr_0_1(iss_rs1_0), .rd_data_0_1(r_data_0_1), .rd_addr_0_2(iss_rs2_0), .rd_data_0_2(r_data_0_2),
        .rd_addr_1_1(iss_rs1_1), .rd_data_1_1(r_data_1_1), .rd_addr_1_2(iss_rs2_1), .rd_data_1_2(r_data_1_2),
        .rd_addr_2_1(iss_rs1_2), .rd_data_2_1(r_data_2_1), .rd_addr_2_2(iss_rs2_2), .rd_data_2_2(r_data_2_2),
        .wb_en_0(wb_valid[0]), .wb_addr_0(wb_prf_rd[0]), .wb_data_0(wb_data[0]),
        .wb_en_1(wb_valid[1]), .wb_addr_1(wb_prf_rd[1]), .wb_data_1(wb_data[1]),
        .wb_en_2(wb_valid[2]), .wb_addr_2(wb_prf_rd[2]), .wb_data_2(wb_data[2])
    );

    // --- EXECUTION ÜNİTELERİ ---
    exec_alu_branch unit0 (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .issue_valid_i(iss_v_0), .issue_decode_i(iss_dec_0), .rs1_data_i(r_data_0_1), .rs2_data_i(r_data_0_2), .prf_rd_i(iss_rd_0),
        .wb_valid_o(wb_valid[0]), .wb_prf_rd_o(wb_prf_rd[0]), .wb_data_o(wb_data[0]), .execute_o(execute_o[0]),
        .branch_resolved_o(branch_resolved), .branch_taken_o(branch_taken), .branch_target_o(branch_target)
    );

    exec_alu unit1 (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .issue_valid_i(iss_v_1), .issue_decode_i(iss_dec_1), .rs1_data_i(r_data_1_1), .rs2_data_i(r_data_1_2), .prf_rd_i(iss_rd_1),
        .wb_valid_o(wb_valid[1]), .wb_prf_rd_o(wb_prf_rd[1]), .wb_data_o(wb_data[1]), .execute_o(execute_o[1])
    );

    logic [31:0] lsu_addr, lsu_wdata; logic lsu_we;
    exec_lsu unit2 (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .issue_valid_i(iss_v_2), .issue_decode_i(iss_dec_2), .rs1_data_i(r_data_2_1), .rs2_data_i(r_data_2_2), .prf_rd_i(iss_rd_2),
        .wb_valid_o(wb_valid[2]), .wb_prf_rd_o(wb_prf_rd[2]), .wb_data_o(wb_data[2]), .execute_o(execute_o[2]),
        .mem_addr_o(lsu_addr), .mem_wdata_o(lsu_wdata), .mem_we_o(lsu_we), .mem_rdata_i(data_mem[lsu_addr[12:2]]),
        .lsu_log_addr_o(lsu_log_addr), .lsu_log_data_o(lsu_log_data), .lsu_log_we_o(lsu_log_we)
    );

    always_ff @(posedge clk_i) begin
        if (lsu_we) data_mem[lsu_addr[12:2]] <= lsu_wdata;
    end

endmodule
