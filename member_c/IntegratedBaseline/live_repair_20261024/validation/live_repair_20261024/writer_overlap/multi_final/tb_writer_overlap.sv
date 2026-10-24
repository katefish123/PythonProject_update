`timescale 1ns/1ps
module tb_writer_overlap;
 localparam W=1024,H=8,PACKETS=W*H/8,BLOCKS=W*H/64,QDEPTH=16;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0;wire pv,pr,cv,cw;wire[319:0]pd;wire[27:0]ca;
 wire[255:0]wd;wire[31:0]ws;wire[2047:0]bd;
 reg cr=0;wire rv;reg rw=1;wire tv;reg tr=0;wire[37:0]td;wire fault;
 reg[319:0]q[0:QDEPTH-1];integer head=0,tail=0,count=0,peak=0,produced=0;
 integer cyc=0,delay=20,period=3,control=0,bad=0,commands=0,acks=0,native_beats=0,remain=0;
 integer frames=1,terminals=0,do_reset=0,reset_done=0;
 integer stalls=0,tstalls=0,overlap_input=0,final_wait=0;
 reg busy=0,old_cv=0,old_tv=0;reg[2363:0]old_command;reg[37:0]old_terminal;
 assign pv=count!=0;assign pd=q[head];assign rv=busy&&remain==0;
 continuous_capture_writer #(.SRC_W(W),.SRC_H(H)) dut(
 .clk(clk),.rst_n(rst_n),.packet_valid(pv),.packet_ready(pr),.packet_data(pd),
 .cmd_valid(cv),.cmd_ready(cr),.cmd_write(cw),.cmd_addr(ca),.cmd_wdata(wd),.cmd_wstrb(ws),.cmd_burst_data(bd),
 .rsp_valid(rv),.rsp_write(rw),.terminal_valid(tv),.terminal_ready(tr),.terminal_data(td),.fault(fault));
 function automatic[31:0]pixel(input integer n);pixel=32'h01700000^n;endfunction
 function automatic[319:0]packet(input integer n);
 integer i,f,k;reg[319:0]v;
 begin
 f=n/(PACKETS+2);k=n%(PACKETS+2);
 v=0;v[317]=!(f%2);v[316:285]=7+f;
 if(k==0)v[319:318]=0;
 else if(k==PACKETS+1)begin v[319:318]=2;v[260]=bad!=2;v[259:256]=bad==2?13:0;end
 else begin
 v[319:318]=1;v[284:261]=(k-1)*8;
 if(bad==1&&k==PACKETS)v[316:285]=8+f;
 for(i=0;i<8;i=i+1)v[i*32+:32]=pixel(f*W*H+(k-1)*8+i);
 end
 packet=v;
 end endfunction
 always @(negedge clk)begin
 cr=!control||(cyc%11<5);
 tr=cyc%13==0;
 end
 integer next_count,i;
 always @(posedge clk)begin
 if(!rst_n)begin head<=0;tail<=0;count<=0;peak<=0;produced<=0;cyc<=0;commands<=0;acks<=0;native_beats<=0;busy<=0;remain<=0;old_cv<=0;old_tv<=0;terminals<=0;end
 else begin
 cyc<=cyc+1;
 next_count=count;
 if(pv&&pr)begin head<=(head+1)%QDEPTH;next_count=next_count-1;if(busy)overlap_input<=overlap_input+1;end
 if(produced<frames*(PACKETS+2)&&cyc%period==0)begin
 if(next_count==QDEPTH)$fatal(1,"BOUNDED_QUEUE_OVERFLOW delay=%0d cyc=%0d produced=%0d commands=%0d acks=%0d peak=%0d",delay,cyc,produced,commands,acks,peak);
 q[tail]<=packet(produced);tail<=(tail+1)%QDEPTH;produced<=produced+1;next_count=next_count+1;
 end
 count<=next_count;if(next_count>peak)peak<=next_count;
 if(old_cv&&{ca,wd,ws,bd}!==old_command)$fatal(1,"STALLED_COMMAND_CHANGED");
 if(old_cv&&!cv)$fatal(1,"STALLED_COMMAND_WITHDRAWN");
 old_cv<=cv&&!cr;old_command<={ca,wd,ws,bd};
 if(old_tv&&(!tv||td!==old_terminal))$fatal(1,"STALLED_TERMINAL_CHANGED");
 old_tv<=tv&&!tr;old_terminal<=td;
 if(cv&&!cr)stalls<=stalls+1;
 if(tv&&!tr)tstalls<=tstalls+1;
 if(busy)begin
 if(remain>0)begin remain<=remain-1;if(remain<=8)native_beats<=native_beats+1;end
 else begin busy<=0;acks<=acks+1;end
 end
 if(cv&&cr)begin
 if(busy&&!rv)$fatal(1,"MULTIPLE_INFLIGHT");
 if(!cw||ws!==32'hffffffff||wd!==bd[255:0]||ca!==((commands/BLOCKS)%2?28'd0:28'h0800000)+(commands%BLOCKS)*64)$fatal(1,"COMMAND_METADATA_ORDER");
 for(i=0;i<64;i=i+1)if(bd[i*32+:32]!==pixel(commands*64+i))$fatal(1,"BURST_PIXEL_ORDER block=%0d pixel=%0d",commands,i);
 commands<=commands+1;busy<=1;remain<=delay;
 end
 if(produced==frames*(PACKETS+2)&&busy)final_wait<=final_wait+1;
 if(tv)begin
 if(busy||acks!=commands||native_beats!=acks*8)$fatal(1,"TERMINAL_BEFORE_FINAL_NATIVE_ACK");
 if(td[37]!==!(terminals%2)||td[36:5]!==32'd7+terminals)$fatal(1,"TERMINAL_OWNERSHIP");
 if(bad==0&&(commands!=(terminals+1)*BLOCKS||!td[4]||td[3:0]!=0||fault))$fatal(1,"GOOD_FRAME_REJECTED");
 if(bad!=0&&td[4])$fatal(1,"BAD_FRAME_PUBLISHED");
 if(bad==1&&(!fault||td[3:0]!=14))$fatal(1,"BAD_GENERATION_NOT_REJECTED");
 if(bad==2&&td[3:0]!=13)$fatal(1,"OVERFLOW_REASON_LOST");
 if(tr)begin
 terminals<=terminals+1;
 if(terminals==frames-1)begin
 // A bad final DATA does not create a final native burst; that case instead
 // proves the partial assembly is discarded and the prior owned writes drain.
 if(bad!=1&&final_wait==0)$fatal(1,"FINAL_ACK_DELAY_NOT_COVERED");
 if(control&&(stalls==0||tstalls==0))$fatal(1,"BACKPRESSURE_NOT_COVERED");
 $display("PASS writer bounded16 delay=%0d period=%0d bad=%0d frames=%0d reset=%0d commands=%0d acks=%0d native_beats=%0d peak=%0d stalls=%0d terminal_stalls=%0d overlap_input=%0d final_wait=%0d cycles=%0d",delay,period,bad,frames,reset_done,commands,acks,native_beats,peak,stalls,tstalls,overlap_input,final_wait,cyc);
 $finish;
 end end end
 if(cyc>30000)$fatal(1,"TIMEOUT");
 end end
 initial begin
 if($value$plusargs("DELAY=%d",delay))begin end
 if($value$plusargs("PERIOD=%d",period))begin end
 if($value$plusargs("CONTROL=%d",control))begin end
 if($value$plusargs("BAD=%d",bad))begin end
 if($value$plusargs("FRAMES=%d",frames))begin end
 if($value$plusargs("RESET=%d",do_reset))begin end
 if(delay<8)$fatal(1,"ACK_MODEL_MUST_RETIRE_ALL_8_NATIVE_BEATS");
 repeat(6)@(negedge clk);rst_n=1;
 if(do_reset)begin
 wait(commands==10&&busy&&remain>8);
 @(negedge clk);rst_n=0;reset_done=1;
 repeat(6)@(negedge clk);rst_n=1;
 end
 end
endmodule
