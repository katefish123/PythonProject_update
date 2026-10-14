`timescale 1ns/1ps
module tb_coord_queue_control;
 localparam SW=16, SH=12, OW=24, OH=16, DEPTH=16, PIXELS=OW*OH;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,start=0,nearest=0,mem_ready=1,write_ready=1;
 wire busy,done,error,mem_valid,write_valid,geometry_valid;
 wire [23:0] mem_addr,write_addr,write_rgb;
 reg mem_rsp_valid=0; reg [23:0] mem_rgb=0;
 wire [31:0] cycles,completed_pixels;
 frame_processor #(.SRC_W(SW),.SRC_H(SH),.OUT_W(OW),.OUT_H(OH),
   .FIXED_IDENTITY(1),.TIMEOUT_CYCLES(128),.COORD_QUEUE_BITS(4)) dut(
   .clk(clk),.rst_n(rst_n),.start(start),.nearest(nearest),.busy(busy),.done(done),.error(error),
   .mem_valid(mem_valid),.mem_ready(mem_ready),.mem_addr(mem_addr),.mem_rsp_valid(mem_rsp_valid),.mem_rgb(mem_rgb),
   .write_valid(write_valid),.write_ready(write_ready),.write_addr(write_addr),.write_rgb(write_rgb),
   .cycles(cycles),.completed_pixels(completed_pixels),.geometry_valid(geometry_valid));

 reg pending=0,freeze_response=0,freeze_writer=0; integer response_delay=0,cycle_no=0;
 reg [23:0] pending_addr=0,held_write_addr=0,held_write_rgb=0;
 reg held_write=0;
 integer accepted_reads=0,response_count=0,read_outstanding=0,range_reads=0;
 integer writer_count=0,frame_writes=0,black_writes=0,reset_count=0,completed_frames=0;
 integer current_write_stall=0,max_write_stall=0;
 integer peak_queue=0,peak_reserved=0;
 reg [23:0] frame_memory[0:SW*SH-1];
 reg [23:0] observed[0:PIXELS-1];
 integer variant=0,vi,vx,vy,expected,frame_id=0;
 reg test_passed=0;
 // Periodic short writer stalls exercise the credit return path without
 // approaching the 128-cycle transaction watchdog.
 always @(negedge clk) write_ready <= !freeze_writer&&(cycle_no%31 < 21);

 function [23:0] pattern(input integer v,input integer a);
   begin pattern={8'((v*53+a*7+19)&255),8'((v*31+a*13+71)&255),8'((v*17+a*29+113)&255)}; end
 endfunction

 always @(posedge clk) begin
   cycle_no=cycle_no+1;
   mem_rsp_valid<=0;
   if(!rst_n) begin pending<=0;response_delay<=0;read_outstanding=0;mem_rsp_valid<=0;held_write=0;end
   else begin
     if(pending && !freeze_response) begin
       if(mem_addr!==pending_addr) $fatal(1,"source address changed while response outstanding");
       if(response_delay>0) response_delay<=response_delay-1;
       else begin mem_rsp_valid<=1;mem_rgb<=frame_memory[pending_addr]; pending<=0; response_count=response_count+1;read_outstanding=0;end
     end
     if(mem_valid&&mem_ready) begin
       if(pending || read_outstanding!=0) $fatal(1,"overlapping source reads");
       if(mem_addr>=SW*SH) $fatal(1,"out-of-range source access address=%0d",mem_addr);
       accepted_reads=accepted_reads+1;range_reads=range_reads+1;
       read_outstanding=1;pending<=1;pending_addr<=mem_addr;response_delay<=1+(cycle_no%4);
     end
   end
   if(rst_n) begin
     if(held_write && (!write_valid || write_addr!==held_write_addr || write_rgb!==held_write_rgb))
       $fatal(1,"pixel address/data did not remain stable under writer backpressure");
     held_write=write_valid&&!write_ready;
     if(held_write)begin held_write_addr=write_addr;held_write_rgb=write_rgb;end
     // coord_reserved counts every coordinate from B admission through writer
     // acceptance; coord_count is a subset of those reserved credits.
     if(dut.coord_count>DEPTH || dut.coord_reserved>DEPTH || dut.coord_count>dut.coord_reserved)
       $fatal(1,"coordinate credit overflow queue=%0d reserved=%0d",dut.coord_count,dut.coord_reserved);
     if(dut.rgb_count>DEPTH||dut.rgb_count>dut.coord_reserved)$fatal(1,"RGB FIFO/credit overflow");
     if(dut.coord_count>peak_queue)peak_queue=dut.coord_count;
     if(dut.coord_reserved>peak_reserved)peak_reserved=dut.coord_reserved;
     if(busy && dut.state>=5 && dut.state<=11 && dut.coord_reserved !== dut.coordinates_issued-dut.completed_pixels)
       $fatal(1,"credit conservation mismatch issued=%0d completed=%0d reserved=%0d",dut.coordinates_issued,dut.completed_pixels,dut.coord_reserved);
     if(write_valid&&write_ready) begin
       if(write_addr!==frame_writes) $fatal(1,"write order/address got=%0d expected=%0d",write_addr,frame_writes);
       if(write_rgb!==observed[frame_writes]) $fatal(1,"pixel mismatch frame=%0d idx=%0d got=%h expected=%h",frame_id,frame_writes,write_rgb,observed[frame_writes]);
       if(write_rgb==24'd0)black_writes=black_writes+1;
       frame_writes=frame_writes+1;writer_count=writer_count+1;
     end
     if(write_valid&&!write_ready) begin
       current_write_stall=current_write_stall+1;
       if(current_write_stall>max_write_stall)max_write_stall=current_write_stall;
     end else current_write_stall=0;
     if(done) begin
       if(frame_writes!=PIXELS || completed_pixels!=PIXELS) $fatal(1,"frame totals writes=%0d completed=%0d",frame_writes,completed_pixels);
       completed_frames=completed_frames+1;
     end
     if(error) $fatal(1,"unexpected frame_processor error");
   end
 end

 task build_expected(input integer v);
   integer x,y,a; begin
     variant=v;
     for(a=0;a<SW*SH;a=a+1) frame_memory[a]=pattern(v,a);
     for(y=0;y<OH;y=y+1) for(x=0;x<OW;x=x+1) begin
       if(x<SW&&y<SH) observed[y*OW+x]=pattern(v,y*SW+x);
       else observed[y*OW+x]=24'd0;
     end
   end
 endtask

 task launch_frame(input integer v,input integer nn);
   begin
     build_expected(v); nearest=nn;frame_writes=0;frame_id=v;
     @(negedge clk);start=1;@(negedge clk);start=0;
     wait(done); @(negedge clk);
     if(frame_writes!=PIXELS) $fatal(1,"missing frame writes");
     repeat(5) @(negedge clk);
   end
 endtask

 task shared_reset;
   begin @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;reset_count=reset_count+1;repeat(4)@(negedge clk);end
 endtask

 integer saved_reads,saved_blacks;
 initial begin
   repeat(5) @(negedge clk);rst_n=1;
   launch_frame(1,0); // bilinear exact-integer mapping and OOB black
   if(accepted_reads!=768) $fatal(1,"bilinear expected 4 reads for each of 192 in-bounds pixels, got %0d",accepted_reads);
   saved_blacks=black_writes;
   launch_frame(2,1); // nearest exact mapping
   if(accepted_reads!=960) $fatal(1,"nearest source read total mismatch %0d",accepted_reads);
   if(black_writes-saved_blacks!=192) $fatal(1,"expected 192 OOB black writes");

   // Reset with coordinates resident in the lookahead FIFO / B pipeline.
   build_expected(3);nearest=0;frame_writes=0;frame_id=3;
   @(negedge clk);start=1;@(negedge clk);start=0;
   wait(dut.coord_reserved>=3 && dut.coord_count>=2); shared_reset();
   launch_frame(4,1);

   // Reset while the single source request is outstanding; restart on a new frame pattern.
   build_expected(5);nearest=0;frame_writes=0;frame_id=5;
   @(negedge clk);start=1;@(negedge clk);start=0;
   wait(pending); saved_reads=accepted_reads; shared_reset();
   if(response_count>=saved_reads) $fatal(1,"test did not reset during an outstanding source request");
   launch_frame(6,0);

   // Hold an accepted source response past the watchdog while future coordinates return.
   build_expected(7);nearest=0;frame_writes=0;frame_id=7;freeze_response=1;
   @(negedge clk);start=1;@(negedge clk);start=0;
   wait(pending && dut.coord_count>=4);
   wait(error);
   if(!dut.fault || dut.coord_count!=0 || dut.coord_reserved!=0) $fatal(1,"timeout did not flush/fault coordinate state");
   if(!pending) $fatal(1,"source request unexpectedly completed before timeout");
   freeze_response=0;shared_reset();
   launch_frame(8,1);
   // Fill the independent RGB FIFO under blocked writes, then reset. A new
   // frame pattern must contain no delayed RGB data from the abandoned frame.
   build_expected(9);nearest=0;frame_writes=0;frame_id=9;freeze_writer=1;
   @(negedge clk);start=1;@(negedge clk);start=0;
   wait(dut.rgb_count>=4&&dut.coord_reserved==DEPTH);
   if(!write_valid)$fatal(1,"blocked FIFO scenario did not hold a real output");
   shared_reset();freeze_writer=0;launch_frame(10,0);
   if(completed_frames!=6 || frame_writes!=PIXELS || writer_count<6*PIXELS)
     $fatal(1,"successful frame aggregate frames=%0d writes=%0d",completed_frames,writer_count);
   if(max_write_stall==0 || max_write_stall>=128) $fatal(1,"writer stall bound was not exercised safely: %0d",max_write_stall);
   if(range_reads!=accepted_reads || read_outstanding!=0 || pending) $fatal(1,"source response accounting leaked");
   $display("CONTROL_PASS frames=%0d pixels=%0d reads=%0d black=%0d resets=%0d max_writer_stall=%0d peak_queue=%0d peak_reserved=%0d timeout_queue=flushed",completed_frames,writer_count,accepted_reads,black_writes,reset_count,max_write_stall,peak_queue,peak_reserved);
   test_passed=1;#10;$finish;
 end
 initial begin #1000000;$fatal(1,"global simulation timeout");end
endmodule
