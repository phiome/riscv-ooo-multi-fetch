`timescale 1 ns / 1 ps

module konata
    import riscv_pkg::*;
(
    input logic clk_i,
    input logic rstn_i,
    input dinstr_t   decode_instr_i  [2],
    input execute_t  execute_instr_i [3],
    input commit_t   commit_instr_i  [2]
);

    `define konata_write(args) $fwrite(file, $sformatf args );

    logic [31:0] last_decode_id;
    logic [31:0] last_commit_id;

    integer file;
    initial begin
        file = $fopen("konata.log", "w");
        if (file != 0) begin
            $display("konata.log opened successfully");
            `konata_write(("Kanata\t0004\n"));
            `konata_write(("C=\t0\n"));
        end else begin
            $display("konata.log could not open");
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            last_decode_id <= '0;
            last_commit_id <= '0;
        end else begin
            decode_stage();
            execute_stage();
            commit_stage();
            `konata_write(("C\t1\n"));
        end
    end

    task decode_stage();
        for (int i = 0; i < 2; i++) begin
            if (decode_instr_i[i].valid) begin
                if(decode_instr_i[i].id < last_decode_id && decode_instr_i[i].id != '0) begin
                    $fatal(1, "decode id (%0d) should be greater than previous id (%0d)", decode_instr_i[i].id, last_decode_id);
                end else if (decode_instr_i[i].id > last_decode_id) begin
                    `konata_write(("I\t%0d\t%0d\t0\n", decode_instr_i[i].id, decode_instr_i[i].id));
                    `konata_write(("S\t%0d\t0\tISS\n", decode_instr_i[i].id));
                    `konata_write(("L\t%0d\t0\t%s", decode_instr_i[i].id, decode_instr_i[i].op.name()));
                    if(decode_instr_i[i].rd_used) `konata_write((" rd:%0d", decode_instr_i[i].rd_idx));
                    if(decode_instr_i[i].rs1_used) `konata_write((" rs1:%0d", decode_instr_i[i].rs1_idx));
                    if(decode_instr_i[i].rs2_used) `konata_write((" rs2:%0d", decode_instr_i[i].rs2_idx));
                    `konata_write(("\n"));
                    last_decode_id <= decode_instr_i[i].id;
                end
            end
        end
    endtask

    task execute_stage();
        for (int i = 0; i < 3; i++) begin
            if (execute_instr_i[i].valid) begin
                `konata_write(("E\t%0d\t0\tISS\n", execute_instr_i[i].id));
                `konata_write(("S\t%0d\t0\tCOM\n", execute_instr_i[i].id));
            end
        end
    endtask

    task commit_stage();
        for (int i = 0; i < 2; i++) begin
            if (commit_instr_i[i].valid) begin
                if(commit_instr_i[i].id < last_commit_id && commit_instr_i[i].id != '0) begin
                    $fatal(1, "decode id (%0d) should be greater than previous id (%0d)", commit_instr_i[i].id, last_commit_id);
                end else if (commit_instr_i[i].id > last_commit_id) begin
                    `konata_write(("E\t%0d\t0\tCOM\n", commit_instr_i[i].id));
                    `konata_write(("R\t%0d\t0\t0\n", commit_instr_i[i].id));
                    last_commit_id <= commit_instr_i[i].id;
                end
            end
        end
    endtask

endmodule
