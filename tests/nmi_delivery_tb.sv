`timescale 1ns/1ps
// Synthetic ROM-free delivery test, using the unchanged production CPU.
// Recreates a PHA/SBC/BNE/PLA delay loop observed at the first missed NMI.
module apple_nmi_delivery_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0, nmi_n = 1;
  integer divider = 0;
  integer ce_div = 14, phase = 0, native_mode = 0, nested = 0;
  wire ce = divider == 0;
  always @(posedge clk) divider <= divider == ce_div-1 ? 0 : divider+1;
  wire [23:0] addr;
  wire [7:0] dout;
  wire we, rdy, vpa, vda, mlb, vpb, i_flag;
  reg [7:0] mem [0:65535];
  wire [7:0] din = mem[addr[15:0]];
  P65C816 cpu(.CLK(clk), .RST_N(rst_n), .CE(ce), .RDY_IN(1'b1),
    .NMI_N(nmi_n), .IRQ_N(1'b1), .ABORT_N(1'b1), .D_IN(din),
    .D_OUT(dout), .A_OUT(addr), .WE(we), .RDY_OUT(rdy),
    .VPA(vpa), .VDA(vda), .MLB(mlb), .VPB(vpb), .I_FLAG(i_flag));
  integer nmi_vector_reads = 0, brk_vector_reads = 0, ticks = 0;
  integer i, cursor;
  reg triggered = 0;
  task emit(input integer value);
    begin mem[cursor] = value[7:0]; cursor = cursor + 1; end
  endtask
  always @(posedge clk) begin
    if (rst_n) begin
      ticks <= ticks+1;
      if (ce && rdy) begin
        if ((vpa || vda) && addr[23:16] != 0)
          $fatal(1,"unexpected nonzero bank %h",addr);
        if (!we) mem[addr[15:0]] = dout;
        if (!vpb && (addr == 24'h00fffa || addr == 24'h00fffb ||
                     addr == 24'h00ffea || addr == 24'h00ffeb))
          nmi_vector_reads = nmi_vector_reads+1;
        if (!vpb && (addr == 24'h00fffe || addr == 24'h00ffff ||
                     addr == 24'h00ffe6 || addr == 24'h00ffe7))
          brk_vector_reads = brk_vector_reads+1;
        if (triggered && $test$plusargs("TRACE"))
          $display("BUS ticks=%0d a=%h din=%h we=%b pc=%h state=%h last=%b sync=%b active=%b got=%b pin=%b marker=%h",
            ticks,addr,din,we,cpu.PC,cpu.STATE,cpu.LAST_CYCLE,
            cpu.NMI_SYNC,cpu.NMI_ACTIVE,cpu.GotInterrupt,nmi_n,mem['h2010]);
      end
    end
  end
  initial begin
    if ($value$plusargs("PHASE=%d",phase)) begin end
    if ($value$plusargs("NATIVE=%d",native_mode)) begin end
    if ($value$plusargs("CE_DIV=%d",ce_div)) begin end
    if ($value$plusargs("NESTED=%d",nested)) begin end
    if (ce_div < 1 || ce_div > 14 || phase < 0) $fatal(1,"invalid test arguments");
    for (i=0;i<65536;i=i+1) mem[i]='hea;
    mem['h2010]=0;
    mem['hfffc]=0; mem['hfffd]='h80;
    mem['hfffa]=0; mem['hfffb]='h90;
    mem['hffea]=0; mem['hffeb]='h90;
    mem['hfffe]=0; mem['hffff]='h91;
    mem['hffe6]=0; mem['hffe7]='h91;
    cursor='h8000;
    emit('h78); // SEI; I does not mask NMI.
    if (native_mode) begin
      emit('h18);emit('hfb); // CLC; XCE -> native.
      emit('hc2);emit('h10); // REP #$10, keep 8-bit accumulator.
      emit('ha2);emit('hf0);emit('h1f);emit('h9a); // LDX #$1ff0; TXS.
      emit('he2);emit('h10); // SEP #$10.
    end else begin
      emit('ha2);emit('hf0);emit('h9a); // LDX #$f0; TXS.
    end
    emit('ha9);emit('h80);emit('h38); // LDA #$80; SEC.
    emit('h4c);emit(0);emit('h81); // JMP $8100.
    cursor='h8100;
    emit('h48);emit('he9);emit(1);emit('hd0);emit('hfc);
    emit('h68);emit('he9);emit(1);emit('hd0);emit('hf6);
    emit('h80);emit('hfe);
    cursor='h9000;
    emit('h48); // preserve A; RTI restores status.
    emit('hee);emit('h10);emit('h20); // INC $2010, marker.
    emit('h68);emit('h40);
    cursor='h9100;emit('h80);emit('hfe); // unexpected BRK trap.
    repeat(4) @(negedge clk);
    rst_n=1;
    do @(negedge clk); while (!(ce && vpa && vda && addr==24'h008100));
    repeat(phase) @(negedge clk);
    triggered=1;nmi_n=0;
    // Same 127 system-clock duration as the integrated TWGS pulse.
    if (nested) repeat(ce_div*2) @(negedge clk);
    else repeat(127) @(negedge clk);
    nmi_n=1;
    if (nested) begin
      // Allow an observed high interval, then request a second NMI while the
      // first handler is executing, as permitted by WDC's NMIB contract.
      repeat(ce_div*2) @(negedge clk);
      do @(negedge clk); while (!(ce && vpa && vda && addr==24'h009000));
      repeat(ce_div) @(negedge clk);
      nmi_n=0;
      repeat(127) @(negedge clk);
      nmi_n=1;
    end
    repeat(ce_div*200) @(negedge clk);
    $display("RESULT native=%0d ce_div=%0d phase=%0d marker=%0d nmi_vector_reads=%0d brk_vector_reads=%0d pc=%h state=%h sync=%b active=%b got=%b",
      native_mode,ce_div,phase,mem['h2010],nmi_vector_reads,brk_vector_reads,
      cpu.PC,cpu.STATE,cpu.NMI_SYNC,cpu.NMI_ACTIVE,cpu.GotInterrupt);
    if(mem['h2010]!=(nested ? 2 : 1) || nmi_vector_reads!=(nested ? 4 : 2) || brk_vector_reads!=0)
      $fatal(1,"external held NMI edge was not serviced exactly once");
    $finish;
  end
  initial begin
    #2000000;
    $fatal(1,"test startup timeout");
  end
endmodule
