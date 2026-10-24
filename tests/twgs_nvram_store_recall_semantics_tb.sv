`timescale 1ns/1ps

// Actual unchanged twgs_nvram, public ports only. No hierarchical RAM access.
// Serial strobes follow the accepted startup-status-mirror bench; READ follows
// the pinned 1.8S firmware's seven command bits + direction switch + forced 1.
// Separate derivative of the frozen baseline bench. CASE=semantics exercises
// the immediate-copy model contract, not physical EEPROM latency or power loss.
module twgs_nvram_store_recall_semantics_tb;
  reg clk = 0;
  always #35 clk = ~clk;
  reg reset = 1;
  reg host_gfx_en = 1, host_snd_en = 1;
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
    .host_gfx_en(host_gfx_en), .host_snd_en(host_snd_en),
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

  function automatic [15:0] image_word(input integer image, input integer address);
    image_word = original_word(address) ^ (image * 16'h0f0f);
  endfunction
  task automatic write_image(input integer image);
    integer address;
    begin
      for (address = 0; address < 16; address = address + 1)
        nv_write(address[3:0], image_word(image, address));
    end
  endtask
  task automatic require_image(input integer image);
    integer address;
    begin
      for (address = 0; address < 16; address = address + 1)
        require_word(address[3:0], image_word(image, address));
    end
  endtask
  task automatic load_image(input integer image);
    integer address;
    reg [15:0] value;
    begin
      for (address = 0; address < 16; address = address + 1) begin
        value = image_word(image, address);
        backup_load_byte(2*address, value[7:0]);
        backup_load_byte(2*address+1, value[15:8]);
      end
    end
  endtask
  task automatic require_backup_word(input [3:0] address, input [15:0] value);
    begin
      @(negedge clk); bk_addr = {address, 1'b0}; #1;
      if (bk_q !== value[7:0]) $fatal(1, "SEMANTICS_BACKUP_LOW_FAIL word=%0d", address);
      @(negedge clk); bk_addr = {address, 1'b1}; #1;
      if (bk_q !== value[15:8]) $fatal(1, "SEMANTICS_BACKUP_HIGH_FAIL word=%0d", address);
    end
  endtask
  task automatic host_flags(input bit graphics, input bit sound);
    begin
      @(negedge clk); host_gfx_en = graphics; host_snd_en = sound;
      repeat (3) @(negedge clk);
    end
  endtask
  task automatic recall_with_backup_and_host_edge;
    reg [7:0] command;
    integer bit_index;
    begin
      command = 8'h85;
      nv_control(8'h80);
      for (bit_index = 7; bit_index >= 1; bit_index = bit_index - 1)
        nv_bit(command[bit_index]);
      // Final RCL command bit, a host edge and SD byte arrive on one edge.
      // Existing priority is serial transfer, then host bit, then SD byte.
      @(negedge clk);
      data_we = 1; data_wr_data = 8'h80; data_stb = 1;
      host_gfx_en = 0; host_snd_en = 0;
      bk_addr = 5'd4; bk_data = 8'ha5; bk_wr = 1;
      @(negedge clk); data_stb = 0; bk_wr = 0;
      repeat (14) @(negedge clk);
      nv_control(8'h00);
    end
  endtask

  initial begin #50000000; $fatal(1, "WATCHDOG_FAIL case=%s", case_name); end

  initial begin
    if (!$value$plusargs("CASE=%s", case_name) || case_name != "semantics")
      $fatal(1, "USAGE_FAIL require +CASE=semantics");
    guest_reset();
    load_image(0); require_image(0);
    nv_command(8'h85); // Intentional recall, then legal enabled working writes.
    nv_command(8'h84); write_image(1); require_image(1);
    nv_command(8'h80); nv_command(8'h81); // Disabled STORE must not change saved.
    nv_command(8'h85); require_image(0);
    $display("SEMANTICS_STORE_WRITE_PROTECTION_PASS words=16");

    nv_command(8'h84); write_image(1); nv_command(8'h81);
    nv_write(4'd5, image_word(2, 5)); // STORE must have cleared write enable.
    require_image(1);
    nv_command(8'h85); require_image(1);
    $display("SEMANTICS_STORE_CLEARS_WRITE_ENABLE_PASS");

    nv_command(8'h84); write_image(2); nv_command(8'h81);
    nv_command(8'h84); write_image(3); require_image(3);
    nv_command(8'h80); nv_command(8'h85); require_image(2);
    $display("SEMANTICS_REPEATED_STORE_REPLACES_IMAGE_PASS words=16");

    nv_command(8'h84); write_image(3); guest_reset(); require_image(3);
    nv_write(4'd5, image_word(4, 5)); require_image(3);
    nv_command(8'h85); require_image(2);
    $display("SEMANTICS_RESET_RETAINS_DISTINCT_WORKING_AND_SAVED_PASS words=16");

    load_image(4); nv_command(8'h85); require_image(4);
    nv_command(8'h84); write_image(5); nv_command(8'h80);
    nv_command(8'h85); require_image(4);
    guest_reset(); nv_command(8'h85); require_image(4);
    $display("SEMANTICS_SD_LOAD_BOTH_IMAGES_IMMEDIATE_RECALL_PASS bytes=32");

    nv_command(8'h84); nv_write(4'd9, image_word(5, 9)); nv_command(8'h80);
    require_word(4'd9, image_word(5, 9));
    require_backup_word(4'd9, image_word(5, 9)); // Public export remains LIVE RAM.
    nv_command(8'h85); require_image(4);
    require_backup_word(4'd9, image_word(4, 9));
    $display("SEMANTICS_LIVE_BACKUP_READ_COMPATIBILITY_PASS");

    backup_load_byte(5'd4, 8'h0c); backup_load_byte(5'd5, 8'h9a);
    host_flags(0, 0); require_word(4'd2, 16'h9a00);
    require_backup_word(4'd2, 16'h9a00);
    nv_command(8'h85); require_word(4'd2, 16'h9a0c);
    host_flags(1, 1); host_flags(0, 0); require_word(4'd2, 16'h9a00);
    nv_command(8'h84); nv_command(8'h81);
    host_flags(1, 1); require_word(4'd2, 16'h9a0c);
    nv_command(8'h85); require_word(4'd2, 16'h9a00);
    if (gfx_en !== 1'b0 || snd_en !== 1'b0) $fatal(1, "SEMANTICS_HOST_OUTPUT_FAIL");
    $display("SEMANTICS_HOST_EDGES_WORKING_ONLY_UNTIL_STORE_PASS");

    recall_with_backup_and_host_edge(); require_word(4'd2, 16'h9aa5);
    if (gfx_en !== 1'b1 || snd_en !== 1'b0) $fatal(1, "SEMANTICS_PRIORITY_HOST_OUTPUT_FAIL");
    nv_command(8'h85); require_word(4'd2, 16'h9aa5);
    require_backup_word(4'd2, 16'h9aa5);
    $display("SEMANTICS_SD_BYTE_WINS_RECALL_AND_HOST_EDGE_PASS");
    $display("NVRAM_SEMANTICS_PASS groups=8");
    $finish;
  end
endmodule
