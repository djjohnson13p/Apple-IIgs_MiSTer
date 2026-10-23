`timescale 1ns/1ps
// Original synthetic opcodes only. No firmware/owned ROM input or forced CPU
// state. A passing result validates this constructed context, not real CDA.
module apple_cda_boot_hook_tb;
  reg clk=0;
  always #5 clk=~clk;
  reg rst_n=0, rdy_in=1, irq_n=1;
  integer scenario=0, ce_div=14, divider=0;
  wire ce=divider==0;
  always @(posedge clk) divider<=divider==ce_div-1 ? 0 : divider+1;
  wire [23:0] addr;
  wire [7:0] dout;
  wire we, rdy, vpa, vda, vpb, mlb, i_flag, native_fetch, toolbox_fetch;
  wire [15:0] observed_x;
  reg [7:0] mem[0:65535];
  // Immutable synthetic code is separate from bank-00 RAM. Reset/stack
  // writes to 00:0100 must never change the FE:0100 dispatcher image.
  reg [7:0] ram[0:65535];
  wire nmi_n, armed, ack, expired;
  wire [1:0] hook_state;
  wire present=scenario!=14;
  reg boot_armed=1;
  wire [7:0] din=bus_read(addr);
  function automatic [7:0] bus_read(input [23:0] address);
    begin
      // Independent synthetic implementation of the card's tight native
      // vector and four-byte JML overlay; normal ROM vector is distinct.
      if(armed && address==24'h00ffea)bus_read='h24;
      else if(armed && address==24'h00ffeb)bus_read='hfb;
      else if(armed && address>=24'h00fb24 && address<=24'h00fb27)begin
        case(address[1:0])
          0:bus_read='h5c;
          1:bus_read=scenario==8 ? 'h80 : 'h2f;
          2:bus_read='hfa;
          3:bus_read='hbc;
        endcase
      end else if(address[23:16]==0 && address[15:0]<'h8000)
        bus_read=ram[address[15:0]];
      else bus_read=mem[address[15:0]];
    end
  endfunction
  P65C816 cpu(.CLK(clk),.RST_N(rst_n),.CE(ce),.RDY_IN(rdy_in),
    .NMI_N(nmi_n),.IRQ_N(irq_n),.ABORT_N(1'b1),.D_IN(din),
    .D_OUT(dout),.A_OUT(addr),.WE(we),.RDY_OUT(rdy),
    .VPA(vpa),.VDA(vda),.MLB(mlb),.VPB(vpb),.I_FLAG(i_flag),
    .X_OUT(observed_x),.NATIVE_FETCH_ACCEPTED(native_fetch),.TOOLBOX_FETCH_ACCEPTED(toolbox_fetch));
  twgs_cda_boot_hook #(.ENABLED(1'b1),.WINDOW_CYCLES(512)) hook(
    .clk(clk),.reset(!rst_n),.present(present),.boot_armed(boot_armed),
    .cpu_cycle(rdy),.native_fetch_accepted(native_fetch),.cpu_x(observed_x),
    .toolbox_fetch_accepted(toolbox_fetch),
    .cpu_addr(addr),.cpu_din(din),.cpu_write(!we),.cpu_vpa(vpa),
    .cpu_vda(vda),.cpu_vpb(vpb),.nmi_n(nmi_n),.vector_armed(armed),
    .state(hook_state),.acknowledged(ack),.timed_out(expired));
  wire disabled_nmi, disabled_armed, disabled_ack, disabled_expired;
  wire [1:0] disabled_state;
  // Exercise the real module's default, without an ENABLED override.
  twgs_cda_boot_hook disabled(
    .clk(clk),.reset(!rst_n),.present(1'b1),.boot_armed(boot_armed),
    .cpu_cycle(rdy),.native_fetch_accepted(native_fetch),.cpu_x(observed_x),
    .toolbox_fetch_accepted(toolbox_fetch),
    .cpu_addr(addr),.cpu_din(din),.cpu_write(!we),.cpu_vpa(vpa),
    .cpu_vda(vda),.cpu_vpb(vpb),.nmi_n(disabled_nmi),.vector_armed(disabled_armed),
    .state(disabled_state),.acknowledged(disabled_ack),.timed_out(disabled_expired));
  integer cursor,i,ticks=0,accepted=0,post_cycles=0;
  integer pulses=0,low_clocks=0,nmi_vectors=0,irq_vectors=0,brk_vectors=0;
  integer trampoline_fetches=0,wrong_page_fetches=0,discarded_entries=0;
  integer entry_count=0,first_call,original_s=-1,saved_pc=-1,saved_bank=-1;
  integer handler_s=-1,expected_nmi,expected_timeout,selector,tool_address;
  integer stall_left=0;
  reg previous_nmi=1,stall_done=0,irq_started=0,irq_release=0,reset_done=0;
  reg terminal_seen=0,frame_checked=0;
  reg byte_mode=0,index_byte_mode=0;

  task emit(input integer value);
    begin mem[cursor]=value[7:0];cursor=cursor+1;end
  endtask
  task lda(input integer value);
    begin emit('ha9);emit(value);if(!byte_mode)emit(value>>8);end
  endtask
  task sta(input integer address);
    begin emit('h8d);emit(address);emit(address>>8);end
  endtask
  function automatic integer word_at(input integer address);
    word_at={ram[(address+1)&'hffff],ram[address&'hffff]};
  endfunction
  task check(input bit okay,input string message);
    if(!okay)$fatal(1,"%s case=%0d ce=%0d pc=%h:%h S=%h ticks=%0d",message,scenario,ce_div,cpu.PBR,cpu.PC,cpu.SP,ticks);
  endtask
  task call_tool(input integer result_offset);
    begin
      lda('h0105);emit('h48); // caller-owned selector/context, not API argument
      emit('ha2);emit(selector);if(!index_byte_mode)emit(selector>>8);
      if(first_call==0)first_call=cursor;
      emit('h22);emit(tool_address);emit(tool_address>>8);emit('he1);
      sta('h2012+result_offset); // actual routine accumulator/error result
      emit('h08); // capture return P without shifting caller context
      if(!byte_mode)begin emit('he2);emit('h20);end
      emit('h68);sta('h2014+result_offset);
      if(!byte_mode)begin emit('hc2);emit('h20);end
      emit('ha3);emit(1);sta('h2000+result_offset); // immediate caller LDA 1,S
      emit('h68);sta('h2002+result_offset);
      emit('h3b);sta('h2004+result_offset);
    end
  endtask

  always @(posedge clk) begin
    if(!rst_n)begin
      boot_armed<=1;accepted=0;pulses=0;low_clocks=0;previous_nmi=1;
      nmi_vectors=0;irq_vectors=0;brk_vectors=0;trampoline_fetches=0;
      wrong_page_fetches=0;discarded_entries=0;entry_count=0;
      original_s=-1;saved_pc=-1;saved_bank=-1;handler_s=-1;frame_checked=0;
      terminal_seen=0;post_cycles=0;
    end else begin
      ticks=ticks+1;
      check(disabled_nmi && !disabled_armed && !disabled_ack && !disabled_expired,"default-disabled hook changed NMI/mapping");
      if(!nmi_n)begin
        low_clocks=low_clocks+1;
        if(previous_nmi)begin
          pulses=pulses+1;
          check(hook_state==2 && !boot_armed && observed_x=='h0105,"pulse lacks handoff/selector/window");
          $display("HOOK_PULSE case=%0d ce=%0d S=%h X=%h a=%h t=%0t",scenario,ce_div,cpu.SP,observed_x,addr,$time);
        end
      end
      previous_nmi=nmi_n;
      if(rdy)begin
        accepted=accepted+1;
        check(accepted<4000,"bounded accepted-cycle timeout");
        if(vpa && vda && vpb && we && cpu.STATE==0 && !cpu.GotInterrupt && cpu.NextIR==din)begin
          check((addr[23:16]==0 && ((addr[15:0]>='h8000 && addr[15:0]<'h8100) ||
                (addr[15:0]>='hfb24 && addr[15:0]<'hfb28) || addr[15:0]=='hf100 || addr[15:0]=='hf200)) ||
                (addr[23:16]=='hbc && ((addr[15:0]>='h9000 && addr[15:0]<'h9010) ||
                (addr[15:0]>='hfa2f && addr[15:0]<'hfa90) || (addr[15:0]>='hfb80 && addr[15:0]<'hfb90))) ||
                (addr[23:16]=='hfe && ((addr[15:0]>='h0100 && addr[15:0]<'h0180) ||
                (addr[15:0]>='h0200 && addr[15:0]<'h0300))) ||
                (addr[23:16]=='he1 && addr[15:0]<8),"fetch escaped its independently bank-checked code window");
        end
        if(vpa && vda && we && addr[23:16]=='hbc)boot_armed<=0;
        if(!we)begin
          check(addr[23:16]==0 && addr[15:0]<'h8000,"synthetic stack/data write reached code/another bank");
          ram[addr[15:0]]=dout;
          if(accepted<20)$display("INITIAL_WRITE case=%0d ce=%0d n=%0d a=%h data=%h codeFE0100=%h",scenario,ce_div,accepted,addr,dout,mem['h100]);
        end
        if(!vpb)begin
          if(addr==24'h00ffea || addr==24'h00ffeb)begin
            nmi_vectors=nmi_vectors+1;
            check(armed,"native NMI vector was not covered by overlay");
            check(din==(addr[0] ? 'hfb : 'h24),"native NMI vector pair changed");
          end
          if(addr==24'h00ffee || addr==24'h00ffef)begin irq_vectors=irq_vectors+1;irq_release=1;end
          if(addr==24'h00ffe6 || addr==24'h00ffe7 || addr==24'h00fffe || addr==24'h00ffff)brk_vectors=brk_vectors+1;
        end
        if(addr>=24'h00fb24 && addr<=24'h00fb27 && vpa)check(armed,"native JML overlay expired mid-instruction");
        if(vpa && vda && we && (addr==24'he10000 || addr==24'he10004))begin
          if(scenario==18)check(!cpu.EF && cpu.MF && !cpu.XF && !toolbox_fetch,"M8 negative did not exercise the width guard");
          if(scenario==19)check(!cpu.EF && !cpu.MF && cpu.XF && !toolbox_fetch,"X8 negative did not exercise the width guard");
          if(cpu.GotInterrupt)begin discarded_entries=discarded_entries+1;check(!native_fetch,"discarded physical entry became accepted");end
          if(native_fetch)begin
            entry_count=entry_count+1;
            if(original_s<0 && hook_state==1 && selector=='h0105 && din=='h5c && addr==24'he10000 && toolbox_fetch)original_s=cpu.SP;
          end
        end
        if(native_fetch && addr==24'hbcfa2f)begin
          trampoline_fetches=trampoline_fetches+1;
          handler_s=cpu.SP;
          saved_pc=word_at((handler_s+2)&'hffff);
          saved_bank=ram[(handler_s+4)&'hffff];
          check(original_s>=0 && handler_s==((original_s-4)&'hffff),"native interrupt did not push exactly four bytes");
          check(saved_pc=='h0100 && saved_bank=='hfe,"entry JML did not save dispatcher target PC/bank");
          frame_checked=1;
          $display("NATIVE_FRAME case=%0d ce=%0d S=%h PBR=%h PC=%h",scenario,ce_div,handler_s[15:0],saved_bank[7:0],saved_pc[15:0]);
        end
        if(native_fetch && addr==24'hbcfa80)begin
          wrong_page_fetches=wrong_page_fetches+1;
          check(!ack,"other FA-page fetch falsely acknowledged");
        end
        if(native_fetch && scenario==12 && !irq_started && addr==24'hfe0000+first_call && din=='h22)irq_started=1;
        if(ram['h200a]==1)begin terminal_seen=1;post_cycles=post_cycles+1;end
        if($test$plusargs("TRACE") && (armed || trampoline_fetches || wrong_page_fetches) && accepted<300)
          $display("BUS case=%0d ce=%0d n=%0d a=%h in=%h out=%h we=%b vpa=%b vda=%b vpb=%b S=%h X=%h IR=%h nextIR=%h state=%h got=%b fetch=%b hook=%0d ack=%b timeout=%b pin=%b",scenario,ce_div,accepted,addr,din,dout,we,vpa,vda,vpb,cpu.SP,observed_x,cpu.IR,cpu.NextIR,cpu.STATE,cpu.GotInterrupt,native_fetch,hook_state,ack,expired,nmi_n);
      end
    end
  end

  always @(negedge clk)begin
    if(!rst_n)begin rdy_in=1;stall_left=0;stall_done=0;irq_n=1;irq_started=0;irq_release=0;end
    else begin
      if(irq_release)irq_n=1;
      else if(irq_started)irq_n=0;
      if(stall_left>0)begin
        stall_left=stall_left-1;
        if(stall_left==0)rdy_in=1;
      end else if(!stall_done &&
        ((scenario==6 && cpu.NMI_SYNC) ||
         (scenario==7 && !nmi_n) ||
         (scenario==9 && addr==24'h00ffea && !vpb) ||
         (scenario==11 && addr==24'he10000 && vpa && vda) ||
         (scenario==13 && addr==24'h00fb25 && vpa)))begin
        stall_done=1;rdy_in=0;stall_left=(scenario==9 || scenario==13) ? 700 : 180;
        if(scenario==11)check(hook_state==1 && nmi_n,"stalled physical Tool entry triggered early");
        $display("STALL case=%0d ce=%0d a=%h clocks=%0d",scenario,ce_div,addr,stall_left);
      end
    end
  end

  initial begin
    if($value$plusargs("CASE=%d",scenario))begin end
    if($value$plusargs("CE_DIV=%d",ce_div))begin end
    byte_mode=scenario==4 || scenario==18;
    index_byte_mode=scenario==4 || scenario==19;
    check(scenario>=0 && scenario<=19 && (ce_div==1 || ce_div==14),"invalid case");
    expected_nmi=!(scenario==2 || scenario==3 || scenario==4 || scenario==5 || scenario==7 || scenario==14 || scenario==15 || scenario==18 || scenario==19);
    expected_timeout=scenario==7 || scenario==8;
    selector=scenario==3 ? 'h0205 : 'h0105;
    tool_address=scenario==2 ? 4 : 0;
    first_call=0;
    for(i=0;i<65536;i=i+1)begin mem[i]='hea;ram[i]=0;end
    mem['hfffc]=0;mem['hfffd]='h80;
    mem['hffea]=0;mem['hffeb]='hf2;mem['hf200]='h40;
    mem['hffee]=0;mem['hffef]='hf1;mem['hf100]='h40;
    cursor='h8000;
    if(scenario!=4)begin emit('h18);emit('hfb);emit('hc2);emit('h30);end
    if(scenario==12)emit('h58); // permit the deliberate competing IRQ
    emit('ha2);emit('hdc);if(scenario!=4)emit(1);emit('h9a);
    if(scenario==18)begin emit('he2);emit('h20);end
    if(scenario==19)begin emit('he2);emit('h10);end
    emit('ha2);emit(selector);if(!index_byte_mode)emit(selector>>8);
    emit('h5c);emit(0);emit('h90);emit('hbc);
    cursor='h9000;
    if(scenario==16)begin emit('h22);emit(0);emit(0);emit('he1);end
    if(scenario!=5)begin emit('haf);emit('hfc);emit('hff);emit(0);end
    emit('h5c);emit(0);emit(2);emit('hfe);
    cursor=tool_address;
    if(scenario==15)emit('hea);
    emit('h5c);emit(0);emit(1);emit('hfe);
    cursor='h0100;
    if(scenario==1)begin
      // ROM1-like private no-argument dispatcher copies: preserve the current
      // three-byte far frame with STA abs,Y, including byte-mode low copy.
      emit('h3b);emit('ha8);emit('ha3);emit(2);emit('h99);emit(2);emit(0);
      emit('he2);emit('h20);emit('ha3);emit(1);emit('h99);emit(1);emit(0);
      emit('hc2);emit('h20);
    end
    if(scenario==17)begin
      // Constructed missing-tool adapter: create and discard a private RTL
      // frame, skip its postprocessing, then return A=0911/C=1 to the caller.
      // This checks the public failure contract, not actual ROM dispatcher code.
      emit('hee);emit(6);emit('h20);emit('h4b);emit('hf4);emit('h7f);emit(1);
      emit('h3b);emit('h18);emit('h69);emit(3);emit(0);emit('h1b);
      lda('h0911);emit('h38);emit('h6b);
    end else begin
      emit('h48);lda(0);emit('h68);emit('hee);emit(6);emit('h20);
      lda('hbeef);emit('h18);emit('h6b);
    end
    cursor='h0200;call_tool(0);call_tool('h20);lda(1);sta('h200a);emit('h80);emit('hfe);
    cursor='hfa80;emit('h40); // separate wrong FA-page handler, outside splice
    cursor='hfa2f;
    // Synthetic instruction-level model of the native frame splice. It uses
    // ordinary CPU opcodes, never direct testbench writes to the CPU/frame.
    emit('hc2);emit('h20);emit('hea);emit('h8b);emit('h48);emit('h48);
    emit('ha3);emit(6);emit('h83);emit(3);emit('ha3);emit(8);emit('h83);emit(5);
    lda('hbcfb);emit('h83);emit(8);lda('hfb7f);emit('h83);emit(7);
    emit('h68);emit('h40);
    cursor='hfb80;
    emit('h08);emit('hc2);emit('h30);emit('h48);emit('hda);emit('h5a);
    emit('hee);emit(8);emit('h20);emit('h7a);emit('hfa);emit('h68);emit('h28);emit('h6b);
    check(mem['h100]==(scenario==1 ? 'h3b : scenario==17 ? 'hee : 'h48),"synthetic dispatcher image initialization differs");
    $display("PROGRAM case=%0d ce=%0d selector=%h tool=E1:%h caller=FE:%h window_cpu_cycles=512 pulse_master_clocks=127",scenario,ce_div,selector[15:0],tool_address[15:0],first_call[15:0]);
    repeat(4)@(negedge clk);rst_n=1;
    if(scenario==10)begin
      wait(!nmi_n);repeat(3)@(negedge clk);rst_n=0;reset_done=1;
      for(i='h2000;i<='h2036;i=i+1)ram[i]=0;
      repeat(4)@(negedge clk);rst_n=1;
    end
    do @(negedge clk);while(!terminal_seen || post_cycles<600);
    check(brk_vectors==0,"unexpected BRK/COP vector");
    for(i=0;i<2;i=i+1)begin
      check(word_at('h2000+i*'h20)==(byte_mode ? 5 : 'h0105) && word_at('h2002+i*'h20)==(byte_mode ? 5 : 'h0105),"individual caller stack selector/context changed");
      check(word_at('h2004+i*'h20)==(byte_mode ? 'hdc : 'h01dc),"individual caller final S changed");
      check(word_at('h2012+i*'h20)==(scenario==17 ? 'h0911 : byte_mode ? 'hef : 'hbeef) && ram['h2014+i*'h20][0]==(scenario==17),"individual routine accumulator/carry return state changed");
    end
    check(cpu.SP=='h01dc,"terminal S changed");
    check(ram['h2006]==(scenario==16 ? 3 : 2),"synthetic no-argument tool count changed");
    check(pulses==(expected_nmi || scenario==7 ? 1 : 0),"unexpected NMI pulse count/retry");
    check(low_clocks==(pulses ? 127 : 0),"external NMI pulse was not exactly127 master clocks");
    check(nmi_vectors==(expected_nmi ? 2 : 0),"native NMI vector count changed");
    check(trampoline_fetches==(expected_nmi && scenario!=8 ? 1 : 0),"exact accepted trampoline count changed");
    check(ram['h2008]==(expected_nmi && scenario!=8 ? 1 : 0),"synthetic detour did not execute exactly once");
    check(ack==(expected_nmi && scenario!=8) && expired==expected_timeout,"hook acknowledgment/timeout profile changed");
    if(scenario==8)check(wrong_page_fetches==1 && !ack,"whole FA page falsely acknowledged");
    if(expected_nmi && scenario!=8)check(frame_checked,"native saved dispatcher frame was not checked");
    if(scenario==12)check(irq_vectors==2 && discarded_entries==1,"IRQ-discarded entry was not exercised");
    if(scenario==6 || scenario==7 || scenario==9 || scenario==11 || scenario==13)check(stall_done,"requested stall was not exercised");
    if(scenario==10)check(reset_done,"reset cancellation was not exercised");
    if(scenario==2 || scenario==18 || scenario==19)check(entry_count==2,"negative entry eligibility path was not exercised twice");
    $display("PROFILE case=%0d ce=%0d pulses=%0d low=%0d nmi_vectors=%0d irq_vectors=%0d discarded=%0d trampoline=%0d wrongpage=%0d detour=%0d selector=%h cleanup=%h finalS=%h returnA=%h returnC=%b secondSelector=%h secondCleanup=%h secondS=%h secondReturnA=%h secondReturnC=%b ack=%b timeout=%b",scenario,ce_div,pulses,low_clocks,nmi_vectors,irq_vectors,discarded_entries,trampoline_fetches,wrong_page_fetches,ram['h2008],word_at('h2000),word_at('h2002),cpu.SP,word_at('h2012),ram['h2014][0],word_at('h2020),word_at('h2022),word_at('h2024),word_at('h2032),ram['h2034][0],ack,expired);
    $display("PASS synthetic experimental hook context (not real-ROM/CDA/hardware safety proof)");
    $finish;
  end
  initial begin #2000000;$fatal(1,"bounded master-clock timeout");end
endmodule
