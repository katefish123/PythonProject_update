`timescale 1ns/1ps
module tb_continuous_source #(parameter NATIVE=0,FRAMES=6,PROC_CYCLES_PER_MS=54000);
localparam W=NATIVE?1920:128,H=NATIVE?1080:48;
localparam HS=NATIVE?44:4,HB=NATIVE?148:8,HF=NATIVE?88:64,VS=NATIVE?5:2,VB=NATIVE?36:4,VF=4;
localparam BASE1=28'h0800000;
reg rx_clk=0,proc_clk=0,ui_clk=0,rst_n=0,enabled=0,rx_vs=0,rx_de=0;reg[23:0]rx_rgb=0;
reg rx_run=1,proc_run=1;
always #3.367003367 if(rx_run)rx_clk=~rx_clk;else rx_clk=0;
always #(500000.0/PROC_CYCLES_PER_MS) if(proc_run)proc_clk=~proc_clk;else proc_clk=0;
always #4 ui_clk=~ui_clk;
wire frame_valid,frame_bank,frame_geometry_valid;reg frame_ready=1;
wire[31:0]frame_generation,rejected_frames,dropped_frames;wire[95:0]frame_corners;wire[3:0]last_failure_reason;wire fault;
wire[31:0]frame_capture_ms,admitted_frames;wire[511:0]reject_reason_counts;
reg release_valid=0,release_bank=0;reg[31:0]release_generation=0;
wire cmd_valid,cmd_write;wire[27:0]cmd_addr;wire[255:0]cmd_wdata;wire[31:0]cmd_wstrb;wire[2047:0]cmd_burst_data;
reg rsp_valid=0,rsp_write=1;reg stall_ui=0;integer utick=0,ptick=0;
reg pending_ui=0;reg pending_bank=0;integer ack_delay=0;wire cmd_ready=!stall_ui&&!pending_ui&&(utick%11!=0);
continuous_source_path #(.IN_W(W),.IN_H(H),.SRC_W(W),.SRC_H(H),.DATA_FIFO_ADDR_BITS(NATIVE?10:4),.FIFO_ADDR_BITS(NATIVE?9:3),.MIN_PIXELS(16),.MAX_PIXELS(4096),.MAX_SPAN(32),.PROC_CYCLES_PER_MS(PROC_CYCLES_PER_MS)) dut(.*);
integer camera_frame=0,accepted=0,commands=0,completed=0;integer allocated_kind[0:255];integer written_pixels[0:255];
integer processing_delay=0;reg processing=0,processing_bank=0,hold_release=0;reg[31:0]processing_generation=0;reg[1:0]locked=0;
reg[1:0]bank_camera[0:1];integer checks=0;reg allow_fault=0;reg suppress_processing=0;
function[23:0]pixel;input integer frame_n,x,y;integer a,shift;reg marker;begin
shift=frame_n%3;marker=0;
for(integer k=0;k<4;k=k+1)if(x>=(k==0||k==3?W/4:W*3/4)+shift-2&&x<=(k==0||k==3?W/4:W*3/4)+shift+2&&y>=(k<2?H/4:H*3/4)-2&&y<=(k<2?H/4:H*3/4)+2)marker=1;
a=y*W+x;pixel=marker?24'd0:{8'(128+(a+frame_n*7)%127),8'(128+(a/7+frame_n*11)%127),8'(128+(a/13+frame_n*17)%127)};
end endfunction
function[95:0]corners;input integer frame_n;integer s;begin
s=frame_n%3;corners={12'(W/4+s),12'(H/4),12'(W*3/4+s),12'(H/4),12'(W*3/4+s),12'(H*3/4),12'(W/4+s),12'(H*3/4)};
end endfunction
always @(posedge rx_clk)if(rst_n&&dut.capture.allocate)begin
allocated_kind[dut.capture.generation+1]=camera_frame;
if(locked[dut.capture.next_bank])$fatal(1,"RX allocated locked bank");
end
always @(posedge ui_clk)begin
rsp_valid<=0;utick<=utick+1;
if(!rst_n)begin pending_ui<=0;ack_delay<=0;end
else begin
if(pending_ui)begin
if(ack_delay==0)begin rsp_valid<=1;pending_ui<=0;completed<=completed+1;end else ack_delay<=ack_delay-1;
end
if(cmd_valid&&cmd_ready)begin: check_burst
integer b,relative,kind,gen;
if(pending_ui||!cmd_write||cmd_wstrb!==32'hffffffff||cmd_addr[5:0]!=0)$fatal(1,"invalid burst ownership/address");
b=cmd_addr>=BASE1;relative=cmd_addr-(b?BASE1:0);gen=dut.writer.generation;kind=allocated_kind[gen];
if(locked[b])$fatal(1,"write to processor owned bank");
for(integer beat=0;beat<8;beat=beat+1)for(integer lane=0;lane<8;lane=lane+1)begin
if(cmd_burst_data[(beat*8+lane)*32+:32]!=={8'd0,pixel(kind,(relative+beat*8+lane)%W,(relative+beat*8+lane)/W)})$fatal(1,"capture pixels bank=%0d gen=%0d addr=%0d",b,gen,relative+beat*8+lane);
end
written_pixels[gen]=written_pixels[gen]+64;commands<=commands+1;pending_ui<=1;pending_bank<=b;ack_delay<=3+commands%4;
end
end end
reg held_desc=0;reg[160:0]descriptor_snapshot;reg[31:0]previous_capture_ms=0;
always @(posedge proc_clk)begin
ptick<=ptick+1;release_valid<=0;
if(!rst_n)begin processing<=0;locked<=0;held_desc<=0;previous_capture_ms<=0;end
else begin
if(fault&&!allow_fault)$fatal(1,"continuous path fault RX=%b writer=%b manager=%b",dut.rx_fault,dut.writer_fault,dut.manager_fault);
if(held_desc&&(!frame_valid||{frame_bank,frame_generation,frame_corners,frame_capture_ms}!==descriptor_snapshot))$fatal(1,"descriptor changed while stalled");
held_desc<=frame_valid&&!frame_ready;descriptor_snapshot<={frame_bank,frame_generation,frame_corners,frame_capture_ms};
if(frame_valid&&frame_ready)begin
if(!frame_geometry_valid||frame_corners!==corners(allocated_kind[frame_generation]))$fatal(1,"immutable geometry mismatch gen=%0d got%h expected%h",frame_generation,frame_corners,corners(allocated_kind[frame_generation]));
if(written_pixels[frame_generation]!=W*H||(pending_ui&&pending_bank==frame_bank))$fatal(1,"early descriptor before accepted writes drain");
if(frame_capture_ms<previous_capture_ms||dut.manager.now_ms<frame_capture_ms||(NATIVE&&dut.manager.now_ms-frame_capture_ms<16))$fatal(1,"capture timestamp excludes capture time or is nonmonotonic");
previous_capture_ms<=frame_capture_ms;
if(processing&&!suppress_processing)$fatal(1,"test processor accepted two frames");
accepted<=accepted+1;locked[frame_bank]<=1;
if(!suppress_processing)begin processing<=1;processing_bank<=frame_bank;processing_generation<=frame_generation;processing_delay<=NATIVE?PROC_CYCLES_PER_MS:100;end
$display("CAPTURE_DESCRIPTOR native=%0d gen=%0d bank=%0d source_frame=%0d capture_ms=%0d time_ns=%0t",NATIVE,frame_generation,frame_bank,allocated_kind[frame_generation],frame_capture_ms,$time);
end
if(processing&&!hold_release)begin
if(processing_delay!=0)processing_delay<=processing_delay-1;
else begin release_valid<=1;release_bank<=processing_bank;release_generation<=processing_generation;locked[processing_bank]<=0;processing<=0;end
end
end end
always @(negedge proc_clk)if(!suppress_processing)frame_ready=!processing;
task raster;input integer frame_n,extra_lines,short_line;integer max_y;begin
camera_frame=frame_n;max_y=VS+VB+H+extra_lines+VF;
for(integer y=0;y<max_y;y=y+1)for(integer x=0;x<HS+HB+W+HF;x=x+1)begin
@(negedge rx_clk);rx_vs=y<VS;rx_de=x>=HS+HB&&x<HS+HB+W-((short_line&&y==VS+VB+H/2)?1:0)&&y>=VS+VB&&y<VS+VB+H+extra_lines;
rx_rgb=rx_de?pixel(frame_n,x-HS-HB,y-VS-VB):0;
end
end endtask
task close_stop;begin
@(negedge rx_clk);enabled=0;rx_de=0;repeat(5)@(negedge rx_clk);rx_vs=1;repeat(20)@(negedge rx_clk);rx_vs=0;
end endtask
task reset_path;begin
@(negedge rx_clk);rst_n=0;enabled=0;rx_vs=0;rx_de=0;stall_ui=0;
proc_run=1;rx_run=1;
repeat(8)@(negedge rx_clk);for(integer n=0;n<256;n=n+1)begin allocated_kind[n]=0;written_pixels[n]=0;end
accepted=0;commands=0;completed=0;processing=0;locked=0;allow_fault=0;hold_release=0;suppress_processing=0;held_desc=0;
rst_n=1;repeat(8)@(negedge rx_clk);enabled=1;repeat(8)@(negedge rx_clk);
end endtask
initial begin
for(integer n=0;n<256;n=n+1)begin allocated_kind[n]=0;written_pixels[n]=0;end
reset_path();
for(integer f=1;f<=FRAMES;f=f+1)raster(f,0,0);
close_stop();wait(accepted==FRAMES&&!processing);repeat(30)@(negedge proc_clk);
if(rejected_frames!=0||dropped_frames!=0||dut.capture.used!=0||admitted_frames!=FRAMES)$fatal(1,"continuous admissions/release count rejected%0d dropped%0d used%b",rejected_frames,dropped_frames,dut.capture.used);
$display("PASS consecutive continuous source native=%0d frames=%0d commands=%0d completed=%0d",NATIVE,FRAMES,commands,completed);
if(!NATIVE)begin
reset_path();raster(10,1,0);raster(11,0,0);raster(12,0,1);raster(13,-1,0);close_stop();
wait(rejected_frames==3&&accepted==1&&!processing);repeat(50)@(negedge proc_clk);
if(dut.capture.used!=0)$fatal(1,"invalid frame bank leak");
$display("PASS invalid extraheight/shortwidth/shortheight rejected only after write drain");
reset_path();stall_ui=1;raster(20,0,0);raster(21,0,0);raster(22,0,0);close_stop();
if(dropped_frames==0)$fatal(1,"bank overrun was not exercised");
stall_ui=0;wait(rejected_frames==2);repeat(100)@(negedge proc_clk);
if(dut.capture.used!=0)$fatal(1,"FIFO-full retained END bank leak");
$display("PASS FIFO-full terminal retention, overrun drop, accepted burst retirement");
reset_path();proc_run=0;raster(24,0,0);raster(25,0,0);close_stop();proc_run=1;
wait(rejected_frames==2);repeat(100)@(negedge proc_clk);
if(dut.capture.used!=0||reject_reason_counts[3*32+:32]!=2)$fatal(1,"geometry FIFO overflow terminal/reason bank leak");
$display("PASS selected marker FIFO overflow retains both terminal generations");
reset_path();
fork begin raster(26,0,0);close_stop();end
begin wait(dut.capture.sampled>100);@(negedge rx_clk);rx_run=0;repeat(500)@(negedge proc_clk);
if(frame_valid||accepted!=0||dut.capture.used==0)$fatal(1,"RX clock stop published an incomplete source");
rx_run=1;end join
wait(accepted==1&&!processing);repeat(30)@(negedge proc_clk);if(dut.capture.used!=0)$fatal(1,"RX clock restart lost bank identity");
$display("PASS RX clock stall/restart preserves partial source ownership");
reset_path();suppress_processing=1;frame_ready=1;hold_release=1;raster(30,0,0);close_stop();wait(accepted==1);
allow_fault=1;@(negedge proc_clk);release_valid=1;release_bank=frame_bank;release_generation=frame_generation+1;
@(negedge proc_clk);release_valid=0;repeat(10)@(negedge proc_clk);
if(!fault||dut.capture.used==0)$fatal(1,"stale release must be rejected");
release_valid=1;release_generation=frame_generation;@(negedge proc_clk);release_valid=0;locked=0;
repeat(30)@(negedge proc_clk);if(dut.capture.used!=0)$fatal(1,"valid matching release failed");
$display("PASS stale release rejected without source ownership corruption");
reset_path();raster(40,0,0);rst_n=0;repeat(10)@(negedge proc_clk);rst_n=1;repeat(30)@(negedge proc_clk);
if(dut.capture.used!=0||frame_valid)$fatal(1,"hard reset did not flush bank identity");
$display("PASS shared hard reset flushes queued capture and metadata");
end
$display("PASS continuous capture complete test suite native=%0d",NATIVE);$finish;
end
initial begin #(NATIVE?(FRAMES+4)*64'd16666667:64'd30000000);$fatal(1,"continuous capture timeout accepted=%0d rejected=%0d used=%b",accepted,rejected_frames,dut.capture.used);end
endmodule
