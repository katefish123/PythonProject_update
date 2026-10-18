`timescale 1ns/1ps
module tb_publish #(parameter NATIVE=0,WITH_SAMPLER=0);
 localparam W=NATIVE?1920:32,H=NATIVE?1080:4,N=W*H;
 reg clk=0,ui_clk=0;always #5 clk=~clk;always #7 ui_clk=~ui_clk;
 reg rst_n=0,start=0,abort=0,iv=0,scene=1,pixel_error=0,srcbank=0,pbank=1,frontbank=0,frontvalid=1,last=0,upstream_idle=1;
 reg[31:0]sf=11,sv=13,pf=11,pv=13;reg[11:0]x=0,y=0;reg[23:0]rgb=0;
 wire sr,busy,ir,ws,wa,wb,wv,wr,drained,wfault,pub;reg pubready=0;wire[23:0]addr,wrgb;
 wire gv,gr,gs,ge,gb,gl,sampler_idle;wire[11:0]gx,gy;wire[23:0]gp;wire[31:0]gf,gver;
 wire[31:0]of,ov;wire osb,orb;wire[12:0]ow,oh;wire[24:0]completed;wire failed;wire[3:0]reason;
 corrected_frame_guard #(.WIDTH(W),.HEIGHT(H)) dut(.clk(clk),.rst_n(rst_n),.start(start),.start_ready(sr),.abort_frame(abort),
 .source_frame_id(sf),.source_version(sv),.source_bank(srcbank),.result_bank(1'b1),.front_valid(frontvalid),.front_bank(frontbank),
 .in_valid(gv),.in_ready(gr),.in_scene_valid(gs),.in_error(ge),.in_x(gx),.in_y(gy),.in_last(gl),.in_rgb(gp),
 .in_frame_id(gf),.in_version(gver),.in_bank(gb),.upstream_idle(upstream_idle&&sampler_idle),.writer_drained(drained),.writer_fault(wfault),
 .writer_frame_start(ws),.writer_abort(wa),.writer_bank(wb),.write_valid(wv),.write_ready(wr),.write_addr(addr),.write_rgb(wrgb),
 .publish_valid(pub),.publish_ready(pubready),.publish_frame_id(of),.publish_version(ov),.publish_source_bank(osb),.publish_result_bank(orb),
 .publish_width(ow),.publish_height(oh),.completed_pixels(completed),.busy(busy),.failed(failed),.failure_reason(reason));
 wire cmdv,cmdw,block;reg cmdready=1,rspvalid=0,rspwrite=1;wire[27:0]cmdaddr;wire[255:0]cmddata;wire[31:0]strb;wire[2047:0]blockdata;
 ddr_result_writer_burst64 #(.OUT_W(W),.OUT_H(H)) writer(.clk(clk),.rst_n(rst_n),.ui_clk(ui_clk),.ui_rst_n(rst_n),
 .frame_start(ws),.abort_frame(wa),.frame_bank(wb),.write_valid(wv),.write_ready(wr),.write_addr(addr),.write_rgb(wrgb),.drained(drained),.fault(wfault),
 .cmd_valid(cmdv),.cmd_ready(cmdready),.cmd_write(cmdw),.cmd_addr(cmdaddr),.cmd_wdata(cmddata),.cmd_wstrb(strb),.cmd_write_block(block),.cmd_block_data(blockdata),.rsp_valid(rspvalid),.rsp_write(rspwrite));
 function[23:0]pattern(input integer a);reg[7:0]r,g,b;begin r=a%251;g=(a*7)%253;b=(a*13)%255;pattern={r,g,b};end endfunction
 generate if(!WITH_SAMPLER)begin: direct_pixels
 assign gv=iv;assign ir=gr;assign gs=scene;assign ge=pixel_error;assign gb=pbank;assign gl=last;
 assign gx=x;assign gy=y;assign gp=rgb;assign gf=pf;assign gver=pv;assign sampler_idle=1'b1;
 end else begin: actual_sampler
 reg[511:0]params=0;reg[575:0]h=0;wire sbusy,sqv,srr,sbank;wire[11:0]sx0,sy0,sx1,sy1;wire[31:0]st,sf0,sv0;
 reg captured_last=0,captured_error=0,rv=0,rbank=0;reg[95:0]rp=0;reg[31:0]rt=0,rf=0,rver=0;wire[31:0]unused_tag;wire sample_error;
 initial begin params[0*64+:64]=64'sd1073741824*W;params[1*64+:64]=64'sd1073741824*H;
 h[0*64+:64]=64'sd1073741824;h[4*64+:64]=64'sd1073741824;h[8*64+:64]=64'sd1073741824;end
 assign sampler_idle=!sbusy;assign gl=captured_last;assign ge=sample_error||captured_error;
 always @(posedge clk)if(iv&&ir)begin captured_last<=last;captured_error<=pixel_error;end
 // Behavioral source memory, separate from the actual result writer endpoint.
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin rv<=0;rp<=0;rt<=0;rf<=0;rver<=0;rbank<=0;end
 else begin
 if(rv&&srr)rv<=0;
 if(sqv&&!rv)begin rv<=1;rt<=st;rf<=sf0;rver<=sv0;rbank<=sbank;
 rp<={pattern(sy1*W+sx1),pattern(sy1*W+sx0),pattern(sy0*W+sx1),pattern(sy0*W+sx0)};end
 end end
 region_sample sampler(.clk(clk),.rst_n(rst_n),.in_valid(iv),.in_ready(ir),.in_route(2'd2),.in_scene_valid(scene),.in_markers_enabled(1'b0),
 .in_bank(pbank),.in_x(x),.in_y(y),.in_u(x),.in_v(y),.in_rgb(rgb),.in_background(24'd0),.in_tag({8'd0,y,x}),.in_frame_id(pf),.in_version(pv),
 .profile_valid(1'b1),.profile_params(params),.profile_h(h),.profile_version(sv),.profile_frame_id(sf),.width(13'(W)),.height(13'(H)),.busy(sbusy),
 .q_valid(sqv),.q_ready(!rv),.q_x0(sx0),.q_y0(sy0),.q_x1(sx1),.q_y1(sy1),.q_tag(st),.q_frame_id(sf0),.q_version(sv0),.q_bank(sbank),
 .r_valid(rv),.r_ready(srr),.r_pixels(rp),.r_tag(rt),.r_frame_id(rf),.r_version(rver),.r_bank(rbank),.r_mask_valid(1'b1),.r_mask_frame_id(rf),.r_mask_version(rver),.r_marker_hit(4'd0),
 .out_valid(gv),.out_ready(gr),.out_rgb(gp),.out_scene_valid(gs),.out_error(sample_error),.out_bank(gb),.out_x(gx),.out_y(gy),.out_tag(unused_tag),.out_frame_id(gf),.out_version(gver));
 end endgenerate
 integer commands=0,acked=0,writes=0,publishes=0,failures=0,delay_count=0;
 reg pending=0,hold_ack=0,bad_ack=0;integer j,base_index,expected_write;
 integer ui_cycles=0,command_stalls=0,first_stalls=0;reg stalled=0;reg[2365:0]stalled_packet;
 wire[2365:0]command_packet={cmdaddr,blockdata,cmddata,strb,cmdw,block};
 always @(negedge ui_clk)begin ui_cycles=ui_cycles+1;
 if(commands==0&&cmdv&&first_stalls<6)begin cmdready=0;first_stalls=first_stalls+1;end
 else cmdready=ui_cycles%17>=5;end
 // Behavioral DDR endpoint: only one outstanding native block, delayed responses.
 always @(posedge ui_clk)begin
 rspvalid<=0;
 if(!rst_n)begin pending<=0;delay_count<=0;stalled<=0;end
 else begin
 if(stalled&&(!cmdv||command_packet!==stalled_packet))$fatal(1,"NATIVE_COMMAND_BACKPRESSURE");
 stalled<=cmdv&&!cmdready;if(cmdv&&!cmdready)begin stalled_packet<=command_packet;command_stalls=command_stalls+1;end
 if(cmdv&&cmdready)begin
 if(pending)$fatal(1,"MULTIPLE_NATIVE_BLOCKS");
 if(!cmdw||!block||strb!==32'hffffffff)$fatal(1,"NATIVE_COMMAND");
 base_index=cmdaddr-28'h0400000;
 if(base_index<0||base_index%64!=0||base_index>=N)$fatal(1,"BLOCK_ADDRESS %h",cmdaddr);
 for(j=0;j<64;j=j+1)if(blockdata[j*32+:32]!=={8'b0,pattern(base_index+j)})$fatal(1,"BLOCK_PIXELS %d %d",base_index,j);
 commands=commands+1;pending<=1;delay_count<=3;
 end
 if(pending)begin
 if(delay_count!=0)delay_count<=delay_count-1;
 else if(!hold_ack)begin rspvalid<=1;rspwrite<=!bad_ack;pending<=0;acked=acked+1;end
 end end end
 always @(posedge clk)if(rst_n)begin
 if(wv&&wr)begin if(addr!==expected_write||wrgb!==pattern(expected_write))$fatal(1,"RASTER_WRITE");expected_write=expected_write+1;writes=writes+1;end
 if(pub&&pubready)publishes=publishes+1;
 if(failed)failures=failures+1;
 end
 task tick;begin @(posedge clk);#1;end endtask
 task launch;integer t;begin
 t=0;while(!sr)begin tick();t++;if(t>1000)$fatal(1,"START_TIMEOUT");end
 expected_write=0;@(negedge clk);start=1;tick();@(negedge clk);start=0;tick();
 end endtask
 task send_pixel(input integer index,input integer kind);
 integer t;begin @(negedge clk);x=index%W;y=index/W;rgb=pattern(index);last=index==N-1;
 scene=kind!=1;pixel_error=kind==2;pf=kind==3?sf+1:sf;pv=kind==4?sv+1:sv;pbank=kind==5?!srcbank:srcbank;
 if(kind==6)x=x+1;if(kind==7)last=!last;
 iv=1;t=0;while(!ir)begin tick();t++;if(t>2000)$fatal(1,"PIXEL_TIMEOUT");@(negedge clk);end
 tick();@(negedge clk);iv=0;scene=1;pixel_error=0;pf=sf;pv=sv;pbank=srcbank;
 end endtask
 task await_failure;integer t,prev;begin prev=failures;t=0;while(failures==prev)begin tick();t++;if(pub)$fatal(1,"FAILED_FRAME_PUBLISHED");if(t>3000)$fatal(1,"FAILURE_TIMEOUT");end
 repeat(5)tick();if(busy||pub)$fatal(1,"FAILURE_NOT_RETIRED");end endtask
 integer k,c0,a0,w0,f0,p0;reg[127:0]held;
 initial begin
 expected_write=0;repeat(5)tick();rst_n=1;repeat(15)tick();pbank=srcbank;
 // Valid full raster; last native acknowledgement is deliberately withheld.
 launch();hold_ack=1;
 for(k=0;k<N;k=k+1)begin
 // Hold only the final acknowledgement; earlier blocks must progress.
 if(k<N-64)hold_ack=0;else hold_ack=1;
 send_pixel(k,0);
 end
 repeat(40)begin tick();if(pub)$fatal(1,"PUBLISHED_BEFORE_DDR_DRAIN");end
 upstream_idle=0;hold_ack=0;k=0;while(!drained)begin tick();k++;if(k>3000)$fatal(1,"DRAIN_TIMEOUT");end
 repeat(10)begin tick();if(pub||!busy)$fatal(1,"PUBLISHED_BEFORE_UPSTREAM_IDLE");end
 upstream_idle=1;k=0;while(!pub)begin tick();k++;if(k>3000)$fatal(1,"PUBLICATION_TIMEOUT");end
 if(completed!==N||of!==sf||ov!==sv||osb!==srcbank||orb!==1||ow!==W||oh!==H||expected_write!=N)$fatal(1,"PUBLICATION_METADATA");
 held={of,ov,osb,orb,ow,oh,completed};repeat(7)begin tick();if(!pub||{of,ov,osb,orb,ow,oh,completed}!==held||!busy||sr)$fatal(1,"PUBLICATION_BACKPRESSURE");end
 @(negedge clk);pubready=1;tick();@(negedge clk);pubready=0;tick();
 if(commands!=N/64||acked!=N/64||publishes!=1)$fatal(1,"NATIVE_COUNTS %d %d %d",commands,acked,publishes);
 if(command_stalls==0)$fatal(1,"NO_COMMAND_BACKPRESSURE_COVERAGE");
 if(NATIVE)begin $display("PASS FRAME_PUBLISH native=1 pixels=%0d blocks=%0d acknowledged=%0d publishes=%0d command_stalls=%0d last_ack_held,upstream retirement,packed RGB,raster,backpressure",N,commands,acked,publishes,command_stalls);$finish;end
 // Reject result bank equal to the live front bank, before writer start.
 c0=commands;w0=writes;frontbank=1;launch();repeat(8)tick();if(pub||busy||commands!=c0||writes!=w0)$fatal(1,"FRONT_BANK_PROTECTION");frontbank=0;
 sf=0;launch();repeat(8)tick();if(pub||busy||commands!=c0||writes!=w0)$fatal(1,"ZERO_FRAME_ID");sf=11;
 sv=0;launch();repeat(8)tick();if(pub||busy||commands!=c0||writes!=w0)$fatal(1,"ZERO_VERSION");sv=13;
 // Independent pixel,metadata,coordinate and EOF faults after partial writes.
 for(k=1;k<=7;k=k+1)begin
 launch();send_pixel(0,0);send_pixel(1,k);await_failure();
 end
 // Bad final pixel must not publish a nearly complete frame.
 launch();for(k=0;k<N-1;k=k+1)send_pixel(k,0);send_pixel(N-1,1);await_failure();
 // Missing pixels remain incomplete; abort flushes the writer's partial block.
 launch();for(k=0;k<3;k=k+1)send_pixel(k,0);repeat(30)begin tick();if(pub)$fatal(1,"TRUNCATED_FRAME_PUBLISHED");end
 @(negedge clk);abort=1;tick();@(negedge clk);abort=0;await_failure();
 // Accepted native writes keep ownership through abort until their ACK.
 launch();hold_ack=1;for(k=0;k<64;k=k+1)send_pixel(k,0);upstream_idle=0;
 while(!pending)tick();@(negedge clk);abort=1;tick();@(negedge clk);abort=0;
 repeat(30)begin tick();if(pub||!busy||sr)$fatal(1,"ABORT_LOST_WRITE_OWNERSHIP");end
 hold_ack=0;repeat(50)begin tick();if(pub||!busy||sr)$fatal(1,"ABORT_LOST_UPSTREAM_OWNERSHIP");end
 // A late output from the cancelled upstream transaction is drained, not written.
 w0=writes;send_pixel(64,0);if(writes!=w0)$fatal(1,"ABORT_WROTE_LATE_PIXEL");upstream_idle=1;await_failure();
 // A reservation violation in flight cancels; it cannot safely be published.
 launch();send_pixel(0,0);frontbank=1;await_failure();frontbank=0;
 // Cancellation while the completed descriptor is backpressured withdraws it.
 launch();for(k=0;k<N;k=k+1)send_pixel(k,0);k=0;while(!pub)begin tick();k++;if(k>3000)$fatal(1,"COMMIT_TIMEOUT");end
 @(negedge clk);abort=1;tick();@(negedge clk);abort=0;await_failure();
 // Wrong native response is an error, never a completed image.
 launch();bad_ack=1;for(k=0;k<64;k=k+1)send_pixel(k,0);await_failure();bad_ack=0;
 if(publishes!=1)$fatal(1,"FAULT_PUBLICATION_COUNT");
 // Coordinated reset cancels the producer's accepted outstanding block.
 launch();hold_ack=1;for(k=0;k<64;k=k+1)send_pixel(k,0);while(!pending)tick();rst_n=0;repeat(5)tick();rst_n=1;hold_ack=0;
 repeat(50)begin tick();if(pub||busy)$fatal(1,"RESET_OLD_PUBLICATION");end
 $display("PASS FRAME_PUBLISH native=0 sampler=%0d full-frame gate,7 independent pixel faults,last-pixel reject,truncation,front bank,abort/upstream drain,commit cancel,bad ACK,backpressure,reset publishes=%0d failures=%0d command_stalls=%0d",WITH_SAMPLER,publishes,failures,command_stalls);$finish;
 end
 initial begin #200000000;$fatal(1,"WATCHDOG");end
endmodule
