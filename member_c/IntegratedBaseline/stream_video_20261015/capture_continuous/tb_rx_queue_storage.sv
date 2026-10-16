`timescale 1ns/1ps
module tb_rx_queue_storage;
 localparam W=32,H=2;
 reg clk=0,rst_n=0,enabled=0,rx_vs=0,rx_de=0;reg[23:0]rx_rgb=0;always #3.367003367 clk=~clk;
 reg release_valid=0,release_bank=0;reg[31:0]release_generation=0;
 wire packet_valid;reg packet_ready=0;wire[319:0]packet_data;
 wire sample_valid,sample_first,sample_bank,close_valid,close_bank,close_ok;
 wire[11:0]sample_x,sample_y;wire[31:0]sample_generation,close_generation,dropped_frames,admitted_frames;
 wire[3:0]close_reason;wire fault;wire[1:0]owned_banks;
 wire rv,sv,sf,sb,cv,cb,co,ff;wire[319:0]rd;wire[11:0]sx,sy;wire[31:0]sg,cg,df,af;wire[3:0]cr;wire[1:0]ob;
 continuous_capture_rx #(.IN_W(W),.IN_H(H),.SRC_W(W),.SRC_H(H)) dut(.*);
 continuous_capture_rx_queue_reference #(.IN_W(W),.IN_H(H),.SRC_W(W),.SRC_H(H)) ref_model(
 .clk(clk),.rst_n(rst_n),.enabled(enabled),.rx_vs(rx_vs),.rx_de(rx_de),.rx_rgb(rx_rgb),.release_valid(release_valid),.release_bank(release_bank),.release_generation(release_generation),
 .packet_valid(rv),.packet_ready(packet_ready),.packet_data(rd),.sample_valid(sv),.sample_first(sf),.sample_x(sx),.sample_y(sy),.sample_bank(sb),.sample_generation(sg),
 .close_valid(cv),.close_bank(cb),.close_ok(co),.close_generation(cg),.close_reason(cr),.dropped_frames(df),.admitted_frames(af),.fault(ff),.owned_banks(ob));
 integer cycles=0,retired=0,stalled=0,full_stall=0,full_pop=0,dual_wrap=0,last_data_end=0;
 reg automatic_io=0;reg[1:0]pending_release=0;reg[31:0]pending_generation[0:1];reg[31:0]rng=32'h2468ace1;
 reg last_was_data=0;
 always @(posedge clk)begin
  cycles=cycles+1;
  if(rst_n)begin
   if(packet_valid&&!packet_ready)stalled=stalled+1;
   if(dut.count==8&&!dut.pop)full_stall=full_stall+1;
   if(dut.count==8&&dut.pop)full_pop=full_pop+1;
   if(dut.push_count==2&&dut.tail==7&&dut.pop)dual_wrap=dual_wrap+1;
   if(packet_valid&&packet_ready)begin
    retired=retired+1;
    if(packet_data[319:318]==2&&last_was_data)last_data_end=last_data_end+1;
    last_was_data=packet_data[319:318]==1;
    if(automatic_io&&packet_data[319:318]==2)begin
     pending_release[packet_data[317]]=1;pending_generation[packet_data[317]]=packet_data[316:285];
    end
   end
   #0.4;
   if({packet_valid,sample_valid,sample_first,sample_x,sample_y,sample_bank,sample_generation,close_valid,close_bank,close_ok,close_generation,close_reason,dropped_frames,admitted_frames,fault,owned_banks}!==
      {rv,sv,sf,sx,sy,sb,sg,cv,cb,co,cg,cr,df,af,ff,ob})$fatal(1,"RX observable state differs from frozen reference cycle=%0d",cycles);
   if(packet_valid&&packet_data!==rd)$fatal(1,"valid/stalled packet differs from frozen reference cycle=%0d",cycles);
   if({dut.head,dut.tail,dut.count}!=={ref_model.head,ref_model.tail,ref_model.count})$fatal(1,"ring ownership differs");
   for(integer k=0;k<8;k=k+1)if(k<dut.count)
    if(dut.queue[(dut.head+k)%8]!==ref_model.queue[(ref_model.head+k)%8])$fatal(1,"owned slot changed slot=%0d count=%0d",(dut.head+k)%8,dut.count);
  end
 end
 always @(negedge clk)if(automatic_io)begin
  rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);packet_ready=rng[0]||rng[3];release_valid=0;
  if(pending_release!=0&&rng[2])begin
   release_bank=!pending_release[0];release_generation=pending_generation[!pending_release[0]];release_valid=1;pending_release[!pending_release[0]]=0;
  end
 end
 task tick;begin @(posedge clk);#1;end endtask
 task reset_rx;begin
  @(negedge clk);automatic_io=0;rst_n=0;enabled=0;rx_vs=0;rx_de=0;release_valid=0;packet_ready=0;pending_release=0;
  repeat(3)tick();@(negedge clk);rst_n=1;repeat(3)tick();
 end endtask
 task pulse;begin @(negedge clk);rx_de=0;rx_vs=1;tick();@(negedge clk);rx_vs=0;tick();end endtask
 task pixels(input integer gen,input reg malformed);
  begin
   for(integer y=0;y<H;y=y+1)begin
    for(integer x=0;x<W-((malformed&&y==H-1)?1:0);x=x+1)begin @(negedge clk);rx_de=1;rx_rgb={8'(gen),8'(y),8'(x)};end
    @(negedge clk);rx_de=0;tick();
   end
  end
 endtask
 task credit(input reg b,input[31:0]g);begin
  @(negedge clk);release_valid=1;release_bank=b;release_generation=g;tick();@(negedge clk);release_valid=0;repeat(3)tick();
 end endtask
 task seed_dual_wrap;
  begin
   @(negedge clk);enabled=1;rx_vs=1;rx_de=0;packet_ready=1;
   dut.enabled_sync=7;ref_model.enabled_sync=7;dut.vs_d=0;ref_model.vs_d=0;
   dut.head=0;ref_model.head=0;dut.tail=7;ref_model.tail=7;dut.count=7;ref_model.count=7;
   dut.active=1;ref_model.active=1;dut.used=1;ref_model.used=1;dut.bank=0;ref_model.bank=0;
   dut.generation=5;ref_model.generation=5;dut.bank_generation[0]=5;ref_model.bank_generation[0]=5;
   for(integer k=0;k<8;k=k+1)begin dut.queue[k]=320'h123000+k;ref_model.queue[k]=320'h123000+k;end
   tick();
   if(dut.count!=8||dut.head!=1||dut.tail!=1||dut.queue[7][319:318]!=2||dut.queue[0][319:318]!=0||dut.queue[0][316:285]!=6)$fatal(1,"END+BEGIN+pop wrap ordering failed");
   @(negedge clk);rx_vs=0;packet_ready=0;repeat(40)begin @(negedge clk);rx_rgb=rx_rgb+1;tick();end
   @(negedge clk);packet_ready=1;tick();
  end
 endtask
 reg[319:0]free_value;reg[2:0]free_slot;
 initial begin
  reset_rx();@(negedge clk);rx_rgb=24'h123457;#0.1;free_value=dut.data_packet;free_slot=dut.tail;tick();
  if(dut.count!=0||packet_valid||dut.queue[free_slot]!==free_value)$fatal(1,"UNOWNED_QUEUE_STORAGE_BOUNDARY_REQUIRED free storage must not depend on enqueue validity");
  enabled=1;repeat(5)tick();pulse();pixels(1,0);pulse();pixels(2,0);pulse();
  if(dut.count!=7||owned_banks!=3)$fatal(1,"reserved controls under data overflow not exercised count=%0d",dut.count);
  repeat(80)begin @(negedge clk);rx_rgb=rx_rgb+1;tick();end
  pulse();if(dut.count!=7)$fatal(1,"blocked VS exposed free-tail speculative write");
  @(negedge clk);packet_ready=1;repeat(10)tick();credit(0,1);credit(1,2);
  if(owned_banks!=0||packet_valid)$fatal(1,"stalled terminal credits did not retire");
  reset_rx();seed_dual_wrap();reset_rx();
  enabled=1;repeat(5)tick();automatic_io=1;pulse();
  for(integer f=1;f<=40;f=f+1)begin pixels(f,f%7==0);pulse();end
  @(negedge clk);automatic_io=0;enabled=0;release_valid=0;packet_ready=1;
  // Close the newly admitted final bank without allocating another.
  repeat(5)tick();pulse();repeat(20)tick();
  reset_rx();enabled=1;repeat(5)tick();pulse();
  for(integer k=0;k<5;k=k+1)begin @(negedge clk);rx_de=1;rx_rgb=k;end
  reset_rx();if(packet_valid||owned_banks||fault)$fatal(1,"reset retained partial data or credits");
  if(full_stall==0||full_pop==0||dual_wrap==0||last_data_end==0||stalled==0)$fatal(1,"missing required queue boundary coverage");
  $display("PASS RX_QUEUE_STORAGE_EQUIVALENCE cycles=%0d retired=%0d stalls=%0d full_hold=%0d full_pop=%0d END_BEGIN_pop_wrap=%0d DATA_END=%0d partial_reset=1",cycles,retired,stalled,full_stall,full_pop,dual_wrap,last_data_end);$finish;
 end
 initial begin #200000;$fatal(1,"RX storage equivalence timeout");end
endmodule
