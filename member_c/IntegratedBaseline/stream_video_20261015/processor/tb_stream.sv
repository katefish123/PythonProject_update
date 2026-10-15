`timescale 1ns/1ps
module tb_stream;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,start=0,abort=0,nearest=0,input_geometry_valid=1;
reg [95:0] input_corners={12'd2,12'd2,12'd13,12'd2,12'd13,12'd9,12'd2,12'd9};
wire busy,done,error,geometry_valid; wire[3:0] failure_reason;
wire[31:0] cycles,completed_pixels,q_generation;
wire q_valid,q_inside,q_nearest; reg q_ready=1;
wire[23:0] q_addr00,q_addr10,q_addr01,q_addr11,q_tag;wire[7:0] q_fx,q_fy;
reg r_valid=0,r_inside=0;wire r_ready;reg[23:0]r_p00=0,r_p10=0,r_p01=0,r_p11=0,r_tag=0;reg[7:0]r_fx=0,r_fy=0;reg[31:0]r_generation=0;
wire write_valid;reg write_ready=1;wire[23:0]write_addr,write_rgb;
`ifdef SOLVER
localparam FIX=0;
`else
localparam FIX=1;
`endif
frame_processor_stream #(.SRC_W(16),.SRC_H(12),.OUT_W(16),.OUT_H(24),.ACTIVE_W(13),.ACTIVE_X(1),.FIXED_IDENTITY(FIX),.TIMEOUT_CYCLES(100000)) dut(.*);
reg [168:0] pending[0:2047];integer qr=0,qw=0,tick=0,received=0,frames=0,expected=0;integer delay_until=0;reg inject_old=0;reg[31:0]old_generation=0; reg corrupt_response=0,halt_requests=0;integer target_errors=0;integer expected_failure=0;integer errors_seen=0;integer stale_seen=0;integer run_length=0,max_run=0;reg[23:0]golden[0:8191];
function[23:0]pixel;input[23:0]a;begin pixel={8'(a%239+1),8'(a%197+2),8'(a%181+3)};end endfunction
function[23:0]blend;input inside_v;input[23:0]a,b,c,d;input[7:0]fx,fy;integer k,v;reg[23:0]pa,pb,pc,pd;begin
pa=pixel(a);pb=pixel(b);pc=pixel(c);pd=pixel(d);blend=0;
for(k=0;k<3;k=k+1)begin
v=(pa[k*8+:8]*(256-fx)+pb[k*8+:8]*fx)*(256-fy)+(pc[k*8+:8]*(256-fx)+pd[k*8+:8]*fx)*fy;
blend[k*8+:8]=inside_v?(v>>16):0;
end end endfunction
always @(posedge clk) begin
 tick<=tick+1;
 q_ready <= !halt_requests&&tick%11!=0;
 write_ready <= tick%199>92;
 if(q_valid&&q_ready)begin
 golden[q_generation*384+q_tag[23:12]*16+q_tag[11:0]]<=blend(q_inside,q_addr00,q_addr10,q_addr01,q_addr11,q_fx,q_fy);
 if(q_nearest&&(q_fx!=0||q_fy!=0||q_addr00!=q_addr10||q_addr00!=q_addr01||q_addr00!=q_addr11))$fatal(1,"nearest metadata invalid");
if(!FIX&&q_tag==24'h000001&&q_addr00!=34)$fatal(1,"top left solved coordinate incorrect");
 pending[qw]<={q_generation,q_inside,q_tag,q_addr00,q_addr10,q_addr01,q_addr11,q_fx,q_fy};qw<=qw+1;
 end
 if(r_valid&&r_ready)begin r_valid<=0;if(r_generation!=q_generation)stale_seen<=stale_seen+1;end
 if((!r_valid||r_ready)&&qr<qw&&tick>delay_until&&tick%13!=0)begin
 {r_generation,r_inside,r_tag,r_p00,r_p10,r_p01,r_p11,r_fx,r_fy}<=pending[qr];
 r_p00<=pixel(pending[qr][111:88]);r_p10<=pixel(pending[qr][87:64]);r_p01<=pixel(pending[qr][63:40]);r_p11<=pixel(pending[qr][39:16]);
 if(corrupt_response)begin r_tag<=pending[qr][135:112]^24'd1;corrupt_response<=0;end
 r_valid<=1;qr<=qr+1;
 end
 if(write_valid&&write_ready)begin
 run_length<=run_length+1;if(run_length+1>max_run)max_run<=run_length+1;
 if(write_rgb!==golden[q_generation*384+expected])$fatal(1,"software bilinear mismatch at %0d",expected);
 if(write_addr!==expected)$fatal(1,"address expected %0d got %0d",expected,write_addr);
 if((expected%16<1||expected%16>=14)&&write_rgb!==0)$fatal(1,"padding nonblack %0d %h",expected,write_rgb);
 if(FIX&&expected%16>=1&&expected%16<14&&write_rgb!==((expected/16<12)?pixel((expected/16)*16+(expected%16)-1):0))$fatal(1,"identity pixel %0d got %h",expected,write_rgb);
 expected<=expected+1;
 end
 if(!(write_valid&&write_ready))run_length<=0;
if(error)begin if(failure_reason!=expected_failure)$fatal(1,"unexpected error %0d",failure_reason);errors_seen<=errors_seen+1;end
 if(done)begin
 if(expected!=384||completed_pixels!=384)$fatal(1,"incomplete frame %0d",expected);
 frames<=frames+1;
 $display("FRAME PASS generation=%0d cycles=%0d",q_generation,cycles);
 end
end
task launch;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;launch();
 wait(frames==1);@(negedge clk);expected=0;nearest=1;if(!FIX)input_corners={12'd2,12'd2,12'd13,12'd3,12'd12,12'd9,12'd3,12'd8};launch();
 wait(frames==2);@(negedge clk);expected=0;delay_until=tick+300;launch();
 repeat(55)@(negedge clk);abort=1;@(negedge clk);abort=0;expected=0;
 launch();wait(frames==3); if(max_run<32)$fatal(1,"did not demonstrate streaming throughput"); if(FIX&&stale_seen==0)$fatal(1,"old responses not exercised");
if(!FIX)begin @(negedge clk);input_geometry_valid=0;expected_failure=3;launch();wait(errors_seen==1);@(negedge clk);input_geometry_valid=1;input_corners=0;expected_failure=4;launch();wait(errors_seen==2);end
@(negedge clk);input_geometry_valid=1;input_corners={12'd2,12'd2,12'd13,12'd2,12'd13,12'd9,12'd2,12'd9};expected=0;expected_failure=11;corrupt_response=1;target_errors=errors_seen+1;launch();wait(errors_seen==target_errors);
@(negedge clk);expected=0;expected_failure=0;launch();wait(frames==4);
@(negedge clk);expected=0;expected_failure=5;halt_requests=1;target_errors=errors_seen+1;launch();wait(errors_seen==target_errors);
$display("fault checks passed missing/rejected geometry, tag order recovery, watchdog");
$display("MAX consecutive accepted writes=%0d stale dropped=%0d",max_run,stale_seen);$display("PASS streaming identity/solver stalls padding nearest abort stale generations");$finish;
end
initial begin #3000000;$fatal(1,"stream processor failed to finish");end
endmodule




