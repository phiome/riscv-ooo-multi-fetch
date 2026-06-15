`timescale 1 ns / 1 ps
module tb 
    import riscv_pkg::*;
();
  logic clk;
  logic rstn;

  logic [XLEN-1:0] addr;
  logic [XLEN-1:0] data;
  logic [XLEN-1:0] instr  [2];

  dinstr_t decode_instr [2];
  execute_t execute_instr [3];
  commit_t commit_instr_ [2];
  commit_t commit_instr  [2];

  
  generate 
    for(genvar i=0; i<2; i++) begin : descrambler_gen
      descrambler i_descrambler(
        .instruction_i(commit_instr_[i].instr),
        .instruction_o(instr[i])
      );

      always_comb begin
        commit_instr[i] = commit_instr_[i];
        commit_instr[i].instr = instr[i];
      end
    end
  endgenerate 

  riscv_ooo i_core_model (
      .clk_i      (clk),
      .rstn_i     (rstn),
      .addr_i     (addr),
      .data_o     (data),
      .decode_o   (decode_instr),
      .execute_o  (execute_instr),
      .commit_o   (commit_instr_)
  );


  `ifndef RUN_WITHOUT_KONATA
    konata i_konata(
      .clk_i(clk),
      .rstn_i(rstn),
      .decode_instr_i(decode_instr),
      .execute_instr_i(execute_instr),
      .commit_instr_i(commit_instr)
    );
  `endif



  integer file_pointer;
  initial begin
    file_pointer = $fopen("model.log", "w");
    #4;
    forever begin
      foreach (commit_instr[i]) begin
        if (commit_instr[i].valid) begin
          if (commit_instr[i].reg_addr == 0) begin
            $fwrite(file_pointer, "0x%8h (0x%8h)", commit_instr[i].pc, commit_instr[i].instr);
          end else begin
            if (commit_instr[i].reg_addr > 9) begin
              $fwrite(file_pointer, "0x%8h (0x%8h) x%0d 0x%8h", commit_instr[i].pc, commit_instr[i].instr, commit_instr[i].reg_addr, commit_instr[i].reg_data);
            end else begin
              $fwrite(file_pointer, "0x%8h (0x%8h) x%0d  0x%8h", commit_instr[i].pc, commit_instr[i].instr, commit_instr[i].reg_addr, commit_instr[i].reg_data);
            end
          end
          if (commit_instr[i].mem_wrt == 1) begin
            $fwrite(file_pointer, " mem 0x%8h 0x%8h", commit_instr[i].mem_addr, commit_instr[i].mem_data);
          end
          $fwrite(file_pointer, "\n");
        end
      end
      if(commit_instr[0].valid || commit_instr[1].valid) #2;
      else #1;
    end
  end

  initial begin
    forever begin
      clk = 0;
      #1;
      clk = 1;
      #1;
    end
  end
  
  initial begin
    rstn = 0;
    #4;
    rstn = 1;
    #20000;
    for (int i = 0; i < 10; i++) begin
      addr = i;
      $display("data @ mem[0x%8h] = %8h", addr, data);
    end
    $finish;
  end


  initial begin
    $dumpfile("dump.vcd");
    $dumpvars();
  end

endmodule
