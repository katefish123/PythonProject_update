`timescale 1ns/1ps
module tb_manager_raw;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,raw_requested=1,av=0,tv=0,mv=0,fr=0,rel=0,relb=0,rr=0;
 reg[32:0]ad=0;reg[37:0]td=0;reg[129:0]md=0;reg[31:0]relg=0;
 wire ar,tr,mr,fv,fb,fg,rv,fault;wire[31:0]gen,ms,rejected;wire[95:0]corners;
 wire[32:0]rd;wire[511:0]counts;wire[3:0]reason;
 continuous_capture_manager #(.PROC_CYCLES_PER_MS(10)) dut(
 .clk(clk),.rst_n(rst_n),
`ifndef RED_BASELINE
 .raw_requested(raw_requested),
`endif
 .allocation_valid(av),.allocation_ready(ar),.allocation_data(ad),
 .terminal_valid(tv),.terminal_ready(tr),.terminal_data(td),
 .metadata_valid(mv),.metadata_ready(mr),.metadata_data(md),
 .frame_valid(fv),.frame_ready(fr),.frame_bank(fb),.frame_generation(gen),.frame_corners(corners),.frame_geometry_valid(fg),.frame_capture_ms(ms),.reject_reason_counts(counts),
 .release_valid(rel),.release_bank(relb),.release_generation(relg),
 .return_valid(rv),.return_ready(rr),.return_data(rd),.rejected_frames(rejected),.last_failure_reason(reason),.fault(fault));
 task step;begin @(posedge clk);#1;end endtask
 task allocate(input bit b,input int g);begin @(negedge clk);av=1;ad={b,32'(g)};step();@(negedge clk);av=0;end endtask
 task terminal(input bit b,input int g,input bit ok,input logic[3:0]why);begin
 @(negedge clk);tv=1;td={b,32'(g),ok,why};while(!tr)step();step();@(negedge clk);tv=0;end endtask
 task metadata(input bit b,input int g,input bit ok,input logic[95:0]c);begin
 @(negedge clk);mv=1;md={b,32'(g),ok,c};while(!mr)step();step();@(negedge clk);mv=0;end endtask
 task accept;begin @(negedge clk);fr=1;step();@(negedge clk);fr=0;end endtask
 task release_bank(input bit b,input int g);begin @(negedge clk);rel=1;relb=b;relg=g;step();@(negedge clk);rel=0;end endtask
 initial begin
 repeat(4)step();rst_n=1;step();
 allocate(0,1);terminal(0,1,1,0);repeat(5)step();
 if(!fv||gen!=1||fg)$fatal(1,"RAW_MUST_PUBLISH_WITHOUT_GEOMETRY");
 // Late geometry must not mutate an already offered descriptor.
 metadata(0,1,1,96'h123456);repeat(3)step();
 if(!fv||fg||corners!=0||fault)$fatal(1,"DESCRIPTOR_CHANGED_WHILE_STALLED");
 accept();repeat(8)step();if(rv)$fatal(1,"RAW_RELEASED_BEFORE_DISPLAY_LEASE_END");
 allocate(1,2);terminal(1,2,1,0);repeat(5)step();accept();
 release_bank(0,1);if(!rv||rd!={1'b0,32'd1})$fatal(1,"RETURN_WRONG_LEASE");
 @(negedge clk);rr=1;step();@(negedge clk);rr=0;
 // Stale metadata after credit return is safe and does not attach to reuse.
 metadata(0,1,0,96'habcdef);raw_requested=0;
 allocate(0,3);terminal(0,3,1,0);repeat(5)step();
 if(fv)$fatal(1,"CORRECTED_DID_NOT_WAIT_FOR_GEOMETRY");
 metadata(0,3,1,96'h112233445566);repeat(5)step();
 if(!fv||!fg||corners!=96'h112233445566||gen!=3)$fatal(1,"CORRECTED_GEOMETRY_JOIN");
 accept();release_bank(1,2);@(negedge clk);rr=1;step();@(negedge clk);rr=0;
 raw_requested=1;allocate(1,4);terminal(1,4,0,13);repeat(5)step();
 if(fv||!rv||rejected!=1||reason!=13||counts[13*32+:32]!=1||fault)$fatal(1,"BAD_RAW_WRITER_NOT_REJECTED");
 $display("PASS MANAGER_RAW no-marker RAW, immutable descriptor, delayed metadata, lease release, CORRECTED join, writer rejection");$finish;
 end
 initial begin #100000;$fatal(1,"TIMEOUT");end
endmodule
