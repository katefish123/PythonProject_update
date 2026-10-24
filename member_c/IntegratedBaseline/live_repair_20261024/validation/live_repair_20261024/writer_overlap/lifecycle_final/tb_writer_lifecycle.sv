`timescale 1ns/1ps
module tb_writer_lifecycle;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,pv=0,cr=1,tr=0,allow_ack=0,force_ack=0;
 reg[319:0]pd=0;wire pr,cv,cw,rv,tv,fault;wire[27:0]ca;
 wire[255:0]wd;wire[31:0]ws;wire[2047:0]bd;wire[37:0]td;
 reg busy=0;integer remain=0,commands=0,acks=0,native_beats=0,cyc=0;
 integer same_edge=0,bad_two_owned=0,terminal_stalls=0,i,eg,ea,eb;
 assign rv=busy&&remain==0&&(allow_ack||force_ack);
 continuous_capture_writer #(.SRC_W(192),.SRC_H(1)) dut(
 .clk(clk),.rst_n(rst_n),.packet_valid(pv),.packet_ready(pr),.packet_data(pd),
 .cmd_valid(cv),.cmd_ready(cr),.cmd_write(cw),.cmd_addr(ca),.cmd_wdata(wd),.cmd_wstrb(ws),.cmd_burst_data(bd),
 .rsp_valid(rv),.rsp_write(1'b1),.terminal_valid(tv),.terminal_ready(tr),.terminal_data(td),.fault(fault));
 function automatic[31:0]pixel(input integer g,n);pixel=(g<<16)^n;endfunction
 function automatic[319:0]pkt(input integer kind,b,g,n);
 reg[319:0]v;integer j;
 begin v=0;v[319:318]=kind;v[317]=b;v[316:285]=g;v[284:261]=n*8;v[260]=1;
 for(j=0;j<8;j=j+1)v[j*32+:32]=pixel(g,n*8+j);
 pkt=v;end endfunction
 task automatic send(input[319:0]v);
 begin @(negedge clk);pd=v;pv=1;do @(posedge clk);while(!pr);@(negedge clk);pv=0;end endtask
 task automatic terminal(input integer b,g,good,reason);
 reg[37:0]held;
 begin
 wait(tv);@(negedge clk);held=td;
 if(td!=={b[0],g[31:0],good[0],reason[3:0]})$fatal(1,"LIFECYCLE_TERMINAL_METADATA");
 if(busy||acks!=commands||native_beats!=acks*8)$fatal(1,"LIFECYCLE_EARLY_TERMINAL");
 repeat(5)begin @(negedge clk);if(!tv||td!==held)$fatal(1,"LIFECYCLE_TERMINAL_UNSTABLE");end
 tr=1;@(negedge clk);tr=0;
 end endtask
 reg stalled=0;reg[2363:0]held_command;
 always @(posedge clk)begin
 if(!rst_n)begin busy<=0;remain<=0;commands<=0;acks<=0;native_beats<=0;cyc<=0;stalled<=0;end
 else begin
 cyc<=cyc+1;
 if(stalled&&(!cv||{ca,wd,ws,bd}!==held_command))$fatal(1,"LIFECYCLE_STALLED_COMMAND");
 stalled<=cv&&!cr;held_command<={ca,wd,ws,bd};
 if(tv&&!tr)terminal_stalls<=terminal_stalls+1;
 if(dut.consume&&dut.state==1&&dut.kind==3&&dut.occupied==3&&dut.inflight)bad_two_owned<=bad_two_owned+1;
 if(dut.consume&&dut.state==1&&dut.kind==1&&!dut.frame_bad&&dut.fill==7&&dut.retire)same_edge<=same_edge+1;
 if(busy)begin
 if(remain>0)begin remain<=remain-1;if(remain<=8)native_beats<=native_beats+1;end
 if(rv)begin busy<=0;acks<=acks+1;end
 end
 if(cv&&cr)begin
 if(busy&&!rv)$fatal(1,"LIFECYCLE_MULTIPLE_INFLIGHT");
 if(commands<2)begin eg=100;ea=commands*64;eb=0;end
 else if(commands==2)begin eg=101;ea=0;eb=1;end
 else begin eg=102;ea=(commands-3)*64;eb=0;end
 if(ca!==(eb?28'h0800000:28'd0)+ea||!cw||ws!==32'hffffffff||wd!==bd[255:0])$fatal(1,"LIFECYCLE_COMMAND_ADDRESS");
 for(i=0;i<64;i=i+1)if(bd[i*32+:32]!==pixel(eg,ea+i))$fatal(1,"LIFECYCLE_COMMAND_PIXELS");
 commands<=commands+1;busy<=1;remain<=10;
 end
 if(cyc>3000)$fatal(1,"LIFECYCLE_TIMEOUT");
 end end
 integer n;
 initial begin
 repeat(6)@(negedge clk);rst_n=1;
 // Malformed control while both full slots are owned; END cannot pass them.
 send(pkt(0,0,100,0));for(n=0;n<16;n=n+1)send(pkt(1,0,100,n));
 send(pkt(3,0,100,0));send(pkt(2,0,100,0));
 repeat(4)begin @(negedge clk);if(tv)$fatal(1,"END_PASSED_TWO_OWNED_WRITES");end
 allow_ack=1;terminal(0,100,0,14);
 if(bad_two_owned==0)$fatal(1,"TWO_OWNED_ERROR_NOT_COVERED");
 // One full block followed by a rejected partial block leaves odd slot parity.
 send(pkt(0,1,101,0));for(n=0;n<11;n=n+1)send(pkt(1,1,101,n));
 send(pkt(1,1,201,11));send(pkt(2,1,101,0));terminal(1,101,0,14);
 // No common reset: next bank/generation starts at the preserved queue parity.
 allow_ack=0;send(pkt(0,0,102,0));for(n=0;n<15;n=n+1)send(pkt(1,0,102,n));
 wait(busy&&remain==0);send(pkt(1,0,102,15));force_ack=1;
 @(negedge clk);force_ack=0;allow_ack=1;
 for(n=16;n<24;n=n+1)send(pkt(1,0,102,n));send(pkt(2,0,102,0));terminal(0,102,1,0);
 if(!fault||commands!=6||acks!=6||same_edge==0||terminal_stalls==0)$fatal(1,"LIFECYCLE_COVERAGE");
 $display("PASS lifecycle commands=%0d acks=%0d native_beats=%0d enqueue_retire_same_edge=%0d bad_two_owned=%0d terminal_stalls=%0d sticky_fault=%b",commands,acks,native_beats,same_edge,bad_two_owned,terminal_stalls,fault);
 $finish;
 end
endmodule
