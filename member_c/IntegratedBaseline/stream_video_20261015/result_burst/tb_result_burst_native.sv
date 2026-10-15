`timescale 1ns/1ps
module tb_result_burst_native;
localparam N=768*1080;
reg clk=0,ui_clk=0;always #9.259259 clk=~clk;always #4 ui_clk=~ui_clk;
reg rst_n=0,ui_rst_n=0,frame_start=0,abort_frame=0,frame_bank=0,write_valid=0;
reg[23:0]write_addr=0,write_rgb=0;wire write_ready,drained,fault,w_cmd_valid,cmd_ready,cmd_write,cmd_write_block;
wire[27:0]cmd_addr;wire[255:0]cmd_wdata;wire[31:0]cmd_wstrb;wire[2047:0]cmd_block_data;
wire rsp_valid,rsp_write;wire[255:0]rsp_rdata;wire[2047:0]rsp_source_block;wire ef;wire[3:0]er;
integer ticks=0;wire allow_cmd=(ticks%31<27);wire cmd_valid=w_cmd_valid&&allow_cmd;wire engine_ready;
assign cmd_ready=engine_ready&&allow_cmd;
ddr_result_writer_burst64 writer(.clk(clk),.ui_clk(ui_clk),.rst_n(rst_n),.ui_rst_n(ui_rst_n),.frame_start(frame_start),.abort_frame(abort_frame),.frame_bank(frame_bank),.write_valid(write_valid),.write_ready(write_ready),.write_addr(write_addr),.write_rgb(write_rgb),.drained(drained),.fault(fault),.cmd_valid(w_cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_write_block(cmd_write_block),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),.cmd_block_data(cmd_block_data),.rsp_valid(rsp_valid),.rsp_write(rsp_write));
wire[27:0]axi_awaddr,axi_araddr;wire[3:0]axi_awlen,axi_arlen,axi_awuser_id,axi_aruser_id;wire axi_awvalid,axi_arvalid,axi_awuser_ap,axi_aruser_ap;wire[255:0]axi_wdata;wire[31:0]axi_wstrb;
reg awready=0,wready=0,wopen=0,hold_native=0;integer remaining=0;reg[27:0]wa=0;wire last=wopen?(remaining==1):(axi_awlen==0);
ddr_word_engine_result_burst #(.CAPTURE_BURST_BEATS(1),.RESULT_WORDS(N),.RESULT_BASE0(28'h200000),.RESULT_BASE1(28'h400000)) engine(
.clk(ui_clk),.rst_n(ui_rst_n),.init_done(ui_rst_n),.cmd_valid(cmd_valid),.cmd_ready(engine_ready),.cmd_write(cmd_write),.cmd_source_block(1'b0),.cmd_result_block(cmd_write_block),.result_block_data(cmd_block_data),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),.capture_burst_data(2048'hbadbad),.rsp_valid(rsp_valid),.rsp_write(rsp_write),.rsp_rdata(rsp_rdata),.rsp_source_block(rsp_source_block),.fault(ef),.fault_reason(er),
.axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awuser_ap),.axi_awuser_id(axi_awuser_id),.axi_awlen(axi_awlen),.axi_awvalid(axi_awvalid),.axi_awready(awready),.axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(wready),.axi_wusero_id(4'b0),.axi_wusero_last(last),.axi_araddr(axi_araddr),.axi_aruser_ap(axi_aruser_ap),.axi_aruser_id(axi_aruser_id),.axi_arlen(axi_arlen),.axi_arvalid(axi_arvalid),.axi_arready(1'b0),.axi_rdata(256'b0),.axi_rid(4'b0),.axi_rlast(1'b0),.axi_rvalid(1'b0));
reg[23:0]golden[0:N-1];reg[31:0]ram0[0:N-1],ram1[0:N-1];string gp;integer frame=0,p=0,commands=0,beats=0,responses=0,words=0,stalls=0,idx,l;reg[27:0]base=28'h200000;time began;
always @(negedge ui_clk)begin awready=ui_rst_n&&!hold_native&&(ticks%11!=2);wready=ui_rst_n&&!hold_native&&(wopen||(axi_awvalid&&awready))&&(ticks%7!=1);end
always @(posedge ui_clk)if(ui_rst_n)begin
 ticks=ticks+1;if(ef||fault)$fatal(1,"native/writer fault reason=%0d",er);if(axi_arvalid)$fatal(1,"unexpected read");
 if(axi_awvalid&&awready)begin
  if(wopen||axi_awlen!=7||axi_awaddr!==base+commands*64)$fatal(1,"AW block address/length mismatch frame=%0d command=%0d",frame,commands);
  wopen=1;remaining=8;wa=axi_awaddr;commands=commands+1;
 end
 if(wready&&wopen)begin
  if(wa!==base+words||axi_wstrb!==32'hffffffff)$fatal(1,"native beat address/mask mismatch");
  for(l=0;l<8;l=l+1)begin idx=words+l;if(axi_wdata[l*32+:32]!=={8'b0,golden[idx]})$fatal(1,"native golden mismatch frame=%0d pixel=%0d got=%h expected=%h",frame,idx,axi_wdata[l*32+:32],golden[idx]);if(frame==1)ram1[idx]=axi_wdata[l*32+:32];else ram0[idx]=axi_wdata[l*32+:32];end
  words=words+8;beats=beats+1;remaining=remaining-1;wa=wa+8;if(remaining==0)wopen=0;
 end
 if(rsp_valid)begin if(!rsp_write||words!=responses*64+64)$fatal(1,"native response before all8beats");responses=responses+1;end
end
task short_start(input integer bank,input integer variant);
begin
 frame=bank;base=bank?28'h400000:28'h200000;commands=0;beats=0;responses=0;words=0;
 gp=$sformatf("D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/fixtures/generated/fullhd/variant%0d/expected_bilinear.hex",variant);$readmemh(gp,golden);
 @(negedge clk);frame_bank=bank;frame_start=1;@(negedge clk);frame_start=0;
end endtask
task prefix(input integer count);
begin
 for(p=0;p<count;p=p+1)begin write_valid=1;write_addr=p;write_rgb=golden[p];frame_bank=~frame_bank;#1;while(!write_ready)@(negedge clk);@(posedge clk);#1;@(negedge clk);end
 write_valid=0;
end endtask
initial begin
 #50;rst_n=1;ui_rst_n=1;repeat(10)@(negedge clk);
 for(frame=0;frame<($test$plusargs("ABORT_ONLY")?0:3);frame=frame+1)begin
  gp=$sformatf("D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/fixtures/generated/fullhd/variant%0d/expected_bilinear.hex",frame);$readmemh(gp,golden);
  commands=0;beats=0;responses=0;words=0;stalls=0;base=(frame==1)?28'h400000:28'h200000;
  @(negedge clk);frame_bank=(frame==1);frame_start=1;began=$time;@(negedge clk);frame_start=0;
  for(p=0;p<N;p=p+1)begin
   write_valid=1;write_addr=p;write_rgb=golden[p];frame_bank=~frame_bank;#1;
   while(!write_ready)begin @(negedge clk);stalls=stalls+1;end
   @(posedge clk);#1;@(negedge clk);
  end
  write_valid=0;while(!drained)@(negedge clk);
  if(commands!=12960||responses!=12960||beats!=103680||words!=N||wopen||stalls!=0)$fatal(1,"fullframe counts/throughput/retirement mismatch");
  for(p=0;p<N;p=p+1)if((frame==1?ram1[p]:ram0[p])!=={8'b0,golden[p]})$fatal(1,"result RAM readback mismatch");
  $display("PASS burst64 native fullframe=%0d pixels=%0d commands=%0d beats=%0d responses=%0d source_stalls=%0d elapsed_ns=%0d",frame,N,commands,beats,responses,stalls,$time-began);
 end
 if(!$test$plusargs("ABORT_ONLY"))$display("PASS burst64 native3fullgoldenframes54MHzsource125MHzUI");
 hold_native=1;short_start(0,0);prefix(209);
 abort_frame=1;@(negedge clk);abort_frame=0;
 repeat(20)begin @(negedge clk);if(drained)$fatal(1,"abort forgot queued native writes");end
 hold_native=0;while(!drained)@(negedge clk);
 if(commands!=3||beats!=24||responses!=3||words!=192)$fatal(1,"abort failed partial versus owned distinction");
 short_start(1,1);prefix(64);while(!drained)@(negedge clk);
 if(commands!=1||beats!=8||responses!=1||words!=64)$fatal(1,"postabort epoch frame failed");
 hold_native=1;short_start(0,0);prefix(64);
 rst_n=0;ui_rst_n=0;wopen=0;remaining=0;#50;rst_n=1;ui_rst_n=1;hold_native=0;repeat(10)@(negedge clk);
 if(!drained||fault||ef)$fatal(1,"common reset failed to flush engine and writer");
 short_start(0,0);prefix(64);while(!drained)@(negedge clk);
 if(commands!=1||beats!=8||responses!=1)$fatal(1,"postreset native frame failed");
 $display("PASS burst64 native abort partial17 queued3blocks lateACK next_epoch common_reset");$finish;
end
initial begin #100000000;$fatal(1,"native full watchdog");end
endmodule
