`timescale 1ns/1ps
module tb_control_pipeline;
 localparam W=256,H=16,N=W*H,BIT=234;
 reg s_clk=0,clk=0,public_reset=0,rst_n=0,start=0,uart_rx=1,nearest=0,output_enable=0;
 always #18.518518 s_clk=~s_clk;
 initial begin #1.733;forever #5.387205 clk=~clk;end
 wire host_reset;reset_sync host_reset_sync(s_clk,public_reset,host_reset);
 wire uart_tx,s_valid,s_ready,s_commit_valid,d_valid,cfg_ready;
 wire[239:0]s_affine,d_affine;wire[15:0]s_sequence,s_commit_sequence,d_sequence;
 lens_uart_control host(.clk(s_clk),.rst_n(host_reset),.uart_rx(uart_rx),.uart_tx(uart_tx),
  .cfg_valid(s_valid),.cfg_ready(s_ready),.cfg_affine(s_affine),.cfg_sequence(s_sequence),
  .commit_valid(s_commit_valid),.commit_sequence(s_commit_sequence));
 lens_parameter_mailbox mailbox(.s_clk(s_clk),.d_clk(clk),.rst_n(public_reset),
  .s_valid(s_valid),.s_ready(s_ready),.s_affine(s_affine),.s_sequence(s_sequence),
  .s_commit_valid(s_commit_valid),.s_commit_sequence(s_commit_sequence),
  .d_valid(d_valid),.d_ready(cfg_ready),.d_affine(d_affine),.d_sequence(d_sequence));
 wire[359:0]debug_h;wire busy,done,error,geometry_valid,commit_valid;wire[15:0]commit_sequence;
 wire[3:0]failure_reason;wire[31:0]cycles,completed_pixels;
 wire q_valid,q_inside,q_nearest,r_ready,write_valid;wire[23:0]q_addr00,q_addr10,q_addr01,q_addr11,q_tag,write_addr,write_rgb;
 wire[7:0]q_fx,q_fy;wire[31:0]q_generation;
 integer tick=0,qn=0,rn=0,wn=0,frame_index=0,commits=0,total_pixels=0,write_stalls=0;
 reg[136:0]responses[0:N-1];reg[31:0]generations[0:N-1];
 wire q_ready=(tick%11>=4)&&(qn-rn<100);
 wire r_valid=(rn<qn)&&(tick%9>=3);
 wire[23:0]r_a00,r_a10,r_a01,r_a11,r_tag;wire[7:0]r_fx,r_fy;wire r_inside;
 assign {r_inside,r_tag,r_a00,r_a10,r_a01,r_a11,r_fx,r_fy}=responses[rn];
 wire[31:0]r_generation=generations[rn];
 wire write_ready=output_enable&&(tick%101>=37);
 function[23:0]pixel(input[23:0]a);reg[7:0]r,g,b;
 begin r=a*13+(a>>8)+17;g=a*7+(a>>3)+43;b=a*3+(a>>11)+97;pixel={r,g,b};end endfunction
 frame_processor_stream #(.SRC_W(1920),.SRC_H(1080),.OUT_W(W),.OUT_H(H),.ACTIVE_W(W),.ACTIVE_X(0),.RUNTIME_AFFINE(1),.TILED_ORDER(1)) dut(
 .debug_h(debug_h),.clk(clk),.rst_n(rst_n),.start(start),.abort(1'b0),.nearest(nearest),.input_geometry_valid(1'b0),.input_corners(96'd0),
 .busy(busy),.done(done),.error(error),.failure_reason(failure_reason),.cycles(cycles),.completed_pixels(completed_pixels),.geometry_valid(geometry_valid),
 .q_valid(q_valid),.q_ready(q_ready),.q_inside(q_inside),.q_nearest(q_nearest),.q_addr00(q_addr00),.q_addr10(q_addr10),.q_addr01(q_addr01),.q_addr11(q_addr11),.q_tag(q_tag),.q_fx(q_fx),.q_fy(q_fy),.q_generation(q_generation),
 .r_valid(r_valid),.r_ready(r_ready),.r_inside(r_inside),.r_p00(pixel(r_a00)),.r_p10(pixel(r_a10)),.r_p01(pixel(r_a01)),.r_p11(pixel(r_a11)),.r_tag(r_tag),.r_fx(r_fx),.r_fy(r_fy),.r_generation(r_generation),
 .write_valid(write_valid),.write_ready(write_ready),.write_addr(write_addr),.write_rgb(write_rgb),
 .cfg_valid(d_valid),.cfg_ready(cfg_ready),.cfg_affine(d_affine),.cfg_sequence(d_sequence),.commit_valid(commit_valid),.commit_sequence(commit_sequence));
 reg[137:0]expected_req[0:4*N-1];reg[23:0]expected_rgb[0:4*N-1];reg[239:0]matrices[0:3];
 function[23:0]position(input integer k);
 integer x,y;begin
  if(frame_index==3)begin x=k%W;y=k/W;end
  else begin x=(k/(128*H))*128+k%128;y=(k/128)%H;end
  position=(y<<12)|x;
 end endfunction
 function[23:0]address(input integer k);reg[23:0]p;begin p=position(k);address=p[23:12]*W+p[11:0];end endfunction
 always @(posedge clk)begin
  tick=tick+1;
  if(!rst_n)begin if(cfg_ready)$fatal(1,"ACK_DURING_APPLICATION_RESET");end
  else begin
   if(error)$fatal(1,"PIPELINE_ERROR reason=%0d",failure_reason);
   if(busy&&dut.active_affine!==matrices[frame_index])$fatal(1,"MIDFRAME_PARAMETERS_CHANGED");
   if(commit_valid)begin
    if(commits==0&&commit_sequence!==16'h1234||commits==1&&commit_sequence!==16'h5678||commits>1)$fatal(1,"WRONG_PROCESSOR_COMMIT");
    commits=commits+1;
   end
   if(write_valid&&!write_ready)write_stalls=write_stalls+1;
   if(q_valid&&q_ready)begin
    if(qn>=N||q_tag!==position(qn))$fatal(1,"CONTROL_Q_ORDER");
    if({1'b0,q_inside,q_tag,q_addr00,q_addr10,q_addr01,q_addr11,q_fx,q_fy}!==expected_req[frame_index*N+address(qn)])$fatal(1,"CONTROL_REQUEST_MISMATCH frame=%0d n=%0d",frame_index,qn);
    responses[qn]={q_inside,q_tag,q_addr00,q_addr10,q_addr01,q_addr11,q_fx,q_fy};generations[qn]=q_generation;qn=qn+1;
   end
   if(r_valid&&r_ready)rn=rn+1;
   if(write_valid&&write_ready)begin
    if(wn>=N||write_addr!==address(wn)||write_rgb!==expected_rgb[frame_index*N+address(wn)])$fatal(1,"CONTROL_RGB_MISMATCH frame=%0d n=%0d",frame_index,wn);
    wn=wn+1;total_pixels=total_pixels+1;
   end
  end
 end
 reg[7:0]pa[0:37],pb[0:37],pc[0:37],ack_expected[0:15],ack_received[0:15];
 integer ack_bytes=0;reg[7:0]ack_byte;
 initial forever begin
  @(negedge uart_tx);
  if(commits<=ack_bytes/8)$fatal(1,"UART_ACK_BEFORE_FRAME_COMMIT");
  repeat(BIT+BIT/2)@(posedge s_clk);#1;
  for(integer j=0;j<8;j=j+1)begin ack_byte[j]=uart_tx;repeat(BIT)@(posedge s_clk);#1;end
  if(!uart_tx||ack_bytes>=16||ack_byte!==ack_expected[ack_bytes])$fatal(1,"CONTROL_ACK_WIRE_MISMATCH byte=%0d value=%h",ack_bytes,ack_byte);
  ack_received[ack_bytes]=ack_byte;ack_bytes=ack_bytes+1;
 end
 task byte_send(input[7:0]v);
 begin
  @(negedge s_clk);uart_rx=0;repeat(BIT)@(negedge s_clk);
  for(integer j=0;j<8;j=j+1)begin uart_rx=v[j];repeat(BIT)@(negedge s_clk);end
  uart_rx=1;repeat(BIT)@(negedge s_clk);
 end endtask
 task send_packet(input integer index);
 begin for(integer k=0;k<38;k=k+1)case(index)0:byte_send(pa[k]);1:byte_send(pb[k]);2:byte_send(pc[k]);endcase
  repeat(BIT*2)@(negedge s_clk);
 end endtask
 task reset_application_with_pending(input[239:0]expected);
 begin
  @(negedge clk);rst_n=0;start=1;
  repeat(40)begin @(negedge clk);if(cfg_ready||d_affine!==expected||!d_valid)$fatal(1,"RESET_CONSUMED_PENDING_COMMAND");end
  start=0;rst_n=1;repeat(5)@(negedge clk);
 end endtask
 task launch(input integer index,input bit nn);
 begin
  if(busy)$fatal(1,"LAUNCH_WHILE_BUSY");
  @(negedge clk);frame_index=index;nearest=nn;qn=0;rn=0;wn=0;start=1;
  @(negedge clk);start=0;
  if(dut.active_affine!==matrices[index])$fatal(1,"WRONG_FRAME_SNAPSHOT");
 end endtask
 task wait_frame;
 integer t;begin
  t=0;while(!done&&t<100000)begin @(negedge clk);t=t+1;end
  if(!done||qn!=N||rn!=N||wn!=N||completed_pixels!=N)$fatal(1,"CONTROL_FRAME_INCOMPLETE");
  if(debug_h!=={40'h0001000000,40'd0,40'd0,matrices[frame_index]})$fatal(1,"WRONG_DEBUG_MATRIX");
  repeat(4)@(negedge clk);
 end endtask
 initial begin
  $readmemh("packet_a.hex",pa);$readmemh("packet_b.hex",pb);$readmemh("packet_c.hex",pc);
  $readmemh("acks.hex",ack_expected);$readmemh("requests.hex",expected_req);$readmemh("rgb.hex",expected_rgb);$readmemh("matrices.hex",matrices);
  repeat(10)@(negedge s_clk);public_reset=1;repeat(10)@(negedge s_clk);
  send_packet(0);wait(d_valid);
  if(ack_bytes!=0||d_sequence!=16'h1234)$fatal(1,"INITIAL_PENDING_COMMAND");
  reset_application_with_pending(matrices[0]);launch(0,0);
  wait(ack_bytes==8);repeat(BIT*3)@(negedge s_clk);
  send_packet(1);wait(d_valid);
  if(!busy||dut.active_affine!==matrices[0]||ack_bytes!=8)$fatal(1,"MIDFRAME_COMMAND_APPLIED");
  output_enable=1;wait_frame();
  reset_application_with_pending(matrices[1]);launch(1,1);wait_frame();
  wait(ack_bytes==16);repeat(BIT*3)@(negedge s_clk);
  @(negedge clk);rst_n=0;repeat(10)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
  if(d_valid||d_affine!==matrices[2])$fatal(1,"LAST_PARAMETER_NOT_RETAINED");
  launch(2,0);wait_frame();
  if(commits!=2||ack_bytes!=16)$fatal(1,"DUPLICATE_COMMIT_AFTER_APPLICATION_RESET");
  send_packet(2);wait(d_valid);
  @(negedge s_clk);public_reset=0;rst_n=0;repeat(20)@(negedge s_clk);public_reset=1;
  repeat(20)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
  if(d_valid||d_affine!==matrices[3])$fatal(1,"PUBLIC_RESET_DID_NOT_CANCEL_PENDING");
  launch(3,0);wait_frame();
  if(commits!=2||ack_bytes!=16||total_pixels!=4*N||write_stalls<1000)$fatal(1,"CONTROL_COVERAGE_MISSING");
  $display("CONTROL_PIPELINE_PASS baud=115200 source_mhz=27 processing_mhz=92.8125 frames=4 pixels=%0d frame_commits=2 ack_bytes=16 pending_app_reset=2 retained_app_reset=1 public_cancel=1 midframe_atomic=1 bilinear=3 nearest=1 write_stalls=%0d",total_pixels,write_stalls);$finish;
 end
 initial begin #25000000;$fatal(1,"CONTROL_PIPELINE_TIMEOUT");end
endmodule
