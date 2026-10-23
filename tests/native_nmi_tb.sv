`timescale 1ns/1ps
// Standalone production-CPU test. All instruction bytes below are synthetic.
module native_nmi_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;
  reg nmi_n = 1;
  wire [23:0] addr;
  wire [7:0] dout;
  wire we, rdy, vpa, vda, mlb, vpb, i_flag;
  reg [7:0] mem [0:16777215];
  wire [7:0] din = mem[addr];
  P65C816 cpu(.CLK(clk), .RST_N(rst_n), .CE(1'b1), .RDY_IN(1'b1),
    .NMI_N(nmi_n), .IRQ_N(1'b1), .ABORT_N(1'b1), .D_IN(din),
    .D_OUT(dout), .A_OUT(addr), .WE(we), .RDY_OUT(rdy),
    .VPA(vpa), .VDA(vda), .MLB(mlb), .VPB(vpb), .I_FLAG(i_flag));

  integer cycles = 0;
  integer handler_seen = 0;
  integer returned = 0;
  integer detour_seen = 0;
  integer mode = 0;
  integer initial_sp = 16'h1ff0;
  integer initial_m = 0;
  integer frame_sp;
  integer return_pc;
  integer return_p;
  integer cursor;
  integer i;
  reg armed = 0;
  reg trigger = 0;

  task byte_at(input integer address, input integer value);
    mem[address] = value[7:0];
  endtask
  task emit(input integer value);
    begin mem[cursor] = value[7:0]; cursor = cursor + 1; end
  endtask
  task lda16(input integer value);
    begin emit('ha9); emit(value); emit(value >> 8); end
  endtask
  task assert_equal(input integer actual, input integer expected, input string what);
    if (actual !== expected)
      $fatal(1, "%s: got %h, expected %h (cycle %0d PC=%h:%h SP=%h)",
        what, actual, expected, cycles, cpu.PBR, cpu.PC, cpu.SP);
  endtask

  always @(posedge clk) begin
    if (rst_n) begin
      cycles = cycles + 1;
      if ($test$plusargs("TRACE") && cycles < 150)
        $display("BUS %0d addr=%h din=%h dout=%h we=%b vpa=%b vda=%b PC=%h:%h IR=%h state=%h SP=%h P=%h NMI=%b", cycles, addr, din, dout, we, vpa, vda, cpu.PBR, cpu.PC, cpu.IR, cpu.STATE, cpu.SP, cpu.P, nmi_n);
      if (!we && rdy) begin
        mem[addr] = dout;
        if (addr == 24'h001000 && !armed) trigger = 1;
      end
      if (vpa && vda && addr == 24'hbc9000 && handler_seen == 0) begin
        handler_seen = 1;
        frame_sp = cpu.SP;
        assert_equal(frame_sp, (initial_sp - 4) & 'hffff, "native interrupt frame size");
        assert_equal(mem[(frame_sp + 4) & 'hffff], 'h12, "native interrupt PBR");
        return_pc = {mem[(frame_sp + 3) & 'hffff], mem[(frame_sp + 2) & 'hffff]};
        return_p = mem[(frame_sp + 1) & 'hffff];
        assert_equal(return_pc, 'h8004, "native interrupt PC byte order");
        assert_equal(return_p, initial_m ? 'h25 : 'h05, "native interrupt status byte");
        if (mode == 1) mem['h120000 | return_pc] = 'h6b;
        assert_equal((return_p >> 5) & 1, initial_m, "native interrupt preserves M");
        assert_equal(cpu.EF, 0, "native interrupt remains native");
        $display("FRAME M=%0d S=%h P=%h PC=12:%h", initial_m, frame_sp[15:0], return_p[7:0], return_pc[15:0]);
      end
      if (handler_seen && vpa && vda && addr[23:16] == 'h12 && !returned) begin
        returned = 1;
        assert_equal(addr[15:0], return_pc, "RTI resumes interrupted PC after frame splice");
        assert_equal(cpu.SP, (initial_sp - 3) & 'hffff, "RTI leaves long return on stack");
        assert_equal(mem[(cpu.SP + 1) & 'hffff], 'hff, "injected RTL low byte");
        assert_equal(mem[(cpu.SP + 2) & 'hffff], 'h90, "injected RTL high byte");
        assert_equal(mem[(cpu.SP + 3) & 'hffff], 'hbc, "injected RTL bank");
        assert_equal(cpu.A, initial_m ? 'h0034 : 'h1234, "16-bit PLA restores A");
        assert_equal(cpu.P[7:0], return_p, "RTI restores status byte");
      end
      if (vpa && vda && addr == 24'hbc9100) begin
        detour_seen = 1;
        assert_equal(cpu.SP, initial_sp, "RTL consumes injected long return");
      end
      if (cycles > 2000) $fatal(1, "timeout");
    end
  end

  always @(negedge clk) begin
    if (trigger) begin nmi_n = 0; trigger = 0; armed = 1; end
    else nmi_n = 1;
  end

  initial begin
    if ($value$plusargs("SP=%h", initial_sp)) begin end
    if ($value$plusargs("M=%d", initial_m)) begin end
    if ($value$plusargs("MODE=%d", mode)) begin end
    for (i = 0; i < 16777216; i = i + 1) mem[i] = 'hea;
    mem['hfffc] = 0; mem['hfffd] = 'h80;
    mem['hffea] = 0; mem['hffeb] = 'h90;
    cursor = 'h8000;
    emit('h18); emit('hfb);              // CLC; XCE (native)
    emit('hc2); emit('h30);              // REP #$30 (A/X 16-bit)
    emit('ha2); emit(initial_sp); emit(initial_sp >> 8); emit('h9a); // LDX; TXS
    lda16(initial_m ? 'h0034 : 'h1234);
    if (initial_m) begin emit('he2); emit('h20); end
    emit('h5c); emit(0); emit('h80); emit('h12); // JML $128000
    cursor = 'h128000;
    emit('h8f); emit(0); emit('h10); emit(0);    // STA $001000: signal NMI
    emit('h80); emit('hfe);                     // BRA self
    cursor = 'h9000;
    emit('h5c); emit(0); emit('h90); emit('hbc); // JML $BC9000
    cursor = 'hbc9000;
    emit('hc2); emit('h20); emit('hea);    // REP #$20; NOP
    emit('h8b); emit('h48); emit('h48);    // PHB; PHA; PHA
    emit('ha3); emit(6); emit('h83); emit(3); // LDA 6,S; STA 3,S
    emit('ha3); emit(8); emit('h83); emit(5); // LDA 8,S; STA 5,S
    lda16('hbc90); emit('h83); emit(8);    // saved RTL bank/high pair
    lda16('h90ff); emit('h83); emit(7);    // RTL adds 1 -> $BC9100
    emit('h68); emit('h40);               // PLA; RTI
    cursor = 'hbc9100; emit('h80); emit('hfe);
    repeat (4) @(negedge clk);
    rst_n = 1;
    wait(returned);
    if (mode == 1) wait(detour_seen);
    repeat (5) @(negedge clk);
    $display("PASS native NMI frame splice M=%0d SP=%h mode=%0d", initial_m, initial_sp[15:0], mode);
    $finish;
  end
endmodule
