`timescale 1ns/1ps

// Actual unchanged twgs_nvram, public ports only. No hierarchical RAM access.
// Serial strobes follow the accepted startup-status-mirror bench; READ follows
// the pinned 1.8S firmware's seven command bits + direction switch + forced 1.
// CASE=controls must pass. CASE=selected/all are ordinary failing regressions:
// a no-op STORE/RECALL implementation must NOT receive a test PASS.
module twgs_nvram_store_recall_tb;
  reg clk = 0;
  always #35 clk = ~clk;
  reg reset = 1;
  reg ctrl_wr_stb = 0, data_stb = 0, data_we = 1, bk_wr = 0;
  reg [7:0] ctrl_wr_data = 0, data_wr_data = 0, bk_data = 0;
  reg [4:0] bk_addr = 0;
  wire [7:0] data_dout, bk_q;
  wire gfx_en, snd_en;
  string case_name;
  reg [15:0] got, expected;
  integer i, mismatches;

  twgs_nvram dut (
    .clk(clk), .reset(reset),
    .ctrl_wr_stb(ctrl_wr_stb), .ctrl_wr_data(ctrl_wr_data),
    .data_stb(data_stb), .data_we(data_we), .data_wr_data(data_wr_data),
    .data_dout(data_dout),
    .bk_addr(bk_addr), .bk_wr(bk_wr), .bk_data(bk_data), .bk_q(bk_q),
    .host_gfx_en(1'b1), .host_snd_en(1'b1),
    .gfx_en(gfx_en), .snd_en(snd_en)
  );

  function automatic [15:0] original_word(input integer index);
    original_word = 16'ha5c3 ^ (index * 16'h1331);
  endfunction
  function automatic [15:0] mutated_word(input integer index);
    mutated_word = original_word(index) ^ 16'h5aa5;
  endfunction

  task automatic nv_control(input [7:0] value);
    begin
      @(negedge clk); ctrl_wr_data = value; ctrl_wr_stb = 1;
      @(negedge clk); ctrl_wr_stb = 0;
      repeat (14) @(negedge clk);
    end
  endtask
  task automatic nv_bit(input bit value);
    begin
      @(negedge clk); data_we = 1; data_wr_data = {value, 7'd0}; data_stb = 1;
      @(negedge clk); data_stb = 0;
      repeat (14) @(negedge clk);
    end
  endtask
  task automatic nv_byte(input [7:0] value);
    integer bit_index;
    begin
      for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1)
        nv_bit(value[bit_index]);
    end
  endtask
  task automatic nv_command(input [7:0] value);
    begin nv_control(8'h80); nv_byte(value); nv_control(8'h00); end
  endtask
  task automatic nv_write(input [3:0] address, input [15:0] value);
    begin
      nv_control(8'h80);
      nv_byte(8'h83 | {1'b0, address, 3'b000});
      nv_byte(value[7:0]); nv_byte(value[15:8]);
      nv_control(8'h00);
    end
  endtask
  task automatic nv_read_byte(output [7:0] value);
    integer bit_index;
    begin
      for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
        @(negedge clk);
        data_we = 0; data_wr_data = 0;
        // Sample the currently presented bit before its access advances DO.
        #1; value[bit_index] = data_dout[7]; data_stb = 1;
        @(negedge clk); data_stb = 0;
        repeat (14) @(negedge clk);
      end
    end
  endtask
  task automatic nv_read(input [3:0] address, output [15:0] value);
    reg [7:0] command, low_byte, high_byte;
    integer bit_index;
    begin
      command = 8'h86 | {1'b0, address, 3'b000};
      nv_control(8'h80);
      for (bit_index = 7; bit_index >= 1; bit_index = bit_index - 1)
        nv_bit(command[bit_index]);
      nv_control(8'h81); nv_bit(1'b1); // Actual card command ends in 111.
      nv_read_byte(low_byte); nv_read_byte(high_byte);
      nv_control(8'h00);
      value = {high_byte, low_byte};
    end
  endtask
  task automatic guest_reset;
    begin
      @(negedge clk);
      ctrl_wr_stb = 0; data_stb = 0; bk_wr = 0; reset = 1;
      repeat (3) @(negedge clk);
      reset = 0;
      repeat (3) @(negedge clk);
    end
  endtask
  task automatic require_word(input [3:0] address, input [15:0] value);
    reg [15:0] actual;
    begin
      nv_read(address, actual);
      if (actual !== value)
        $fatal(1, "CONTROL_FAIL case=%s word=%0d got=%04x expected=%04x",
               case_name, address, actual, value);
    end
  endtask
  task automatic backup_load_byte(input [4:0] address, input [7:0] value);
    begin
      @(negedge clk); bk_addr = address; bk_data = value; bk_wr = 1;
      @(negedge clk); bk_wr = 0;
    end
  endtask
  task automatic seed_serial_original;
    integer address;
    begin
      // X2444 requires an intentional recall before write/store enable.
      nv_command(8'h85); #3000;
      nv_command(8'h84);
      for (address = 0; address < 16; address = address + 1)
        nv_write(address[3:0], original_word(address));
      for (address = 0; address < 16; address = address + 1)
        require_word(address[3:0], original_word(address));
      $display("CONTROL_SERIAL_ORIGINAL_PASS case=%s words=16", case_name);
    end
  endtask

  // Simulation watchdog is independent of any expected failing assertion.
  initial begin #50000000; $fatal(1, "WATCHDOG_FAIL case=%s", case_name); end

  initial begin
    if (!$value$plusargs("CASE=%s", case_name))
      $fatal(1, "USAGE_FAIL require +CASE=controls|selected|all");
    if (case_name != "controls" && case_name != "selected" && case_name != "all")
      $fatal(1, "USAGE_FAIL unknown case=%s", case_name);
    guest_reset();

    if (case_name == "controls") begin
      for (i = 0; i < 16; i = i + 1) require_word(i[3:0], 16'h0000);
      $display("CONTROL_INITIAL_ZERO_PASS words=16");
      nv_command(8'h85); #3000;
      nv_write(4'd0, 16'h1234); require_word(4'd0, 16'h0000);
      $display("CONTROL_RESET_WRITE_DISABLED_PASS");
      seed_serial_original();
      nv_command(8'h80);
      nv_write(4'd5, 16'h1234); require_word(4'd5, original_word(5));
      $display("CONTROL_WRDI_PASS");
      nv_command(8'h84);
      nv_control(8'h80); nv_byte(8'hab); nv_byte(8'h12); // Partial word5 WRITE.
      guest_reset();
      for (i = 0; i < 16; i = i + 1) require_word(i[3:0], original_word(i));
      nv_write(4'd5, 16'h5678); require_word(4'd5, original_word(5));
      $display("CONTROL_GUEST_RESET_PRESERVES_RAM_AND_ABORTS_SERIAL_PASS words=16");
      // Model the existing SD-load public port, not serial STORE/RECALL.
      for (i = 0; i < 16; i = i + 1) begin
        expected = mutated_word(i);
        backup_load_byte((2*i), expected[7:0]);
        backup_load_byte((2*i+1), expected[15:8]);
      end
      for (i = 0; i < 16; i = i + 1) begin
        expected = mutated_word(i);
        require_word(i[3:0], expected);
        @(negedge clk); bk_addr = 2*i; #1;
        if (bk_q !== expected[7:0]) $fatal(1, "CONTROL_BACKUP_LOW_FAIL word=%0d", i);
        @(negedge clk); bk_addr = 2*i+1; #1;
        if (bk_q !== expected[15:8]) $fatal(1, "CONTROL_BACKUP_HIGH_FAIL word=%0d", i);
      end
      guest_reset();
      for (i = 0; i < 16; i = i + 1) require_word(i[3:0], mutated_word(i));
      $display("CONTROL_BACKUP_LOAD_BYTE_ORDER_AND_RESET_PASS bytes=32");
      $display("NVRAM_CONTROLS_PASS groups=6");
      $finish;
    end else begin
      seed_serial_original();
      nv_command(8'h81); // STO: RAM -> EEPROM, with previous RECALL + WREN.
      #10001000;        // More than X2444 maximum 10ms store time.
      nv_command(8'h80);
      nv_command(8'h84); // Never assume STORE preserves the write-enable latch.
      if (case_name == "selected") nv_write(4'd5, mutated_word(5));
      else for (i = 0; i < 16; i = i + 1) nv_write(i[3:0], mutated_word(i));
      nv_command(8'h80);
      for (i = 0; i < 16; i = i + 1) begin
        expected = (case_name == "all" || i == 5) ? mutated_word(i) : original_word(i);
        require_word(i[3:0], expected);
      end
      $display("CONTROL_VOLATILE_MUTATION_PASS case=%s", case_name);
      nv_command(8'h85); // RCL is legal while write-disabled.
      #3000;
      mismatches = 0;
      for (i = 0; i < 16; i = i + 1) begin
        nv_read(i[3:0], got);
        if (got !== original_word(i)) begin
          mismatches = mismatches + 1;
          $display("RECALL_MISMATCH case=%s word=%0d got=%04x expected=%04x",
                   case_name, i, got, original_word(i));
        end
      end
      if (mismatches != 0)
        $fatal(1, "STORE_RECALL_FAIL case=%s mismatches=%0d", case_name, mismatches);
      $display("STORE_RECALL_PASS case=%s words=16", case_name);
      $finish;
    end
  end
endmodule
