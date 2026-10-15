`timescale 1ns/1ps
module tb_stream_burst_path;
`ifdef FULL
 localparam SW=1920,SH=1080,OW=768,OH=1080,AW=765;
`else
 localparam SW=128,SH=48,OW=32,OH=48,AW=29;
`endif
`ifdef SOLVER
 localparam FIX=0;
`else
 localparam FIX=1;
`endif
localparam PIXELS=OW*OH;
reg proc_clk=0,ui_clk=0;always #9.259259 proc_clk=~proc_clk;always #4 ui_clk=~ui_clk;
reg rst_n=0,start=0,abort=0,nearest=0,input_geometry_valid=1,frame_bank=0;
reg[27:0]source_base=0;
`ifdef FULL
reg[95:0]input_corners=96'h28a0464e206e5283f224e3c0;
`else
reg[95:0]input_corners=96'h02200405d00606702a019027;
`endif
wire start_ready,busy,done,error;wire[3:0]failure_reason;wire[31:0]completed_pixels,processor_cycles;
wire cmd_valid,cmd_ready,cmd_write,cmd_source_block,cmd_result_block;wire[2047:0]result_block_data;wire[27:0]cmd_addr;wire[255:0]cmd_wdata;wire[31:0]cmd_wstrb;
wire rsp_valid,rsp_write,engine_fault;wire[255:0]rsp_rdata;wire[2047:0]rsp_source_block;wire[3:0]engine_reason;
c_stream_burst_correction_path #(.SRC_W(SW),.SRC_H(SH),.OUT_W(OW),.OUT_H(OH),.ACTIVE_W(AW),.ACTIVE_X(1),.FIXED_IDENTITY(FIX)) dut(.*);
wire[27:0]axi_awaddr,axi_araddr;wire axi_awuser_ap,axi_aruser_ap;wire[3:0]axi_awuser_id,axi_aruser_id,axi_awlen,axi_arlen;wire axi_awvalid,axi_arvalid;
wire[255:0]axi_wdata;wire[31:0]axi_wstrb;
reg axi_awready=0,axi_arready=0,axi_wready=0,axi_rvalid=0,axi_rlast=0;
wire[3:0]axi_wusero_id=0,axi_rid=0;
reg[255:0]axi_rdata=0;
reg write_open=0;integer write_remaining=0;
wire axi_wusero_last=write_open ? (write_remaining==1):(axi_awlen==0);
ddr_word_engine_result_burst #(.WATCHDOG_CYCLES(1024),.SOURCE_PREFETCH_ENABLE(0),.SOURCE_WORDS(SW*SH),.SOURCE_BASE1(28'h800000),.RESULT_WORDS(PIXELS),.RESULT_BASE0(28'h200000),.RESULT_BASE1(28'h400000)) engine(
 .clk(ui_clk),.rst_n(rst_n),.init_done(rst_n),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_source_block(cmd_source_block),.cmd_result_block(cmd_result_block),.result_block_data(result_block_data),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),.capture_burst_data(2048'b0),
 .rsp_valid(rsp_valid),.rsp_write(rsp_write),.rsp_rdata(rsp_rdata),.rsp_source_block(rsp_source_block),.fault(engine_fault),.fault_reason(engine_reason),
 .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awuser_ap),.axi_awuser_id(axi_awuser_id),.axi_awlen(axi_awlen),.axi_awvalid(axi_awvalid),.axi_awready(axi_awready),
 .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(axi_wready),.axi_wusero_id(axi_wusero_id),.axi_wusero_last(axi_wusero_last),
 .axi_araddr(axi_araddr),.axi_aruser_ap(axi_aruser_ap),.axi_aruser_id(axi_aruser_id),.axi_arlen(axi_arlen),.axi_arvalid(axi_arvalid),.axi_arready(axi_arready),.axi_rdata(axi_rdata),.axi_rid(axi_rid),.axi_rlast(axi_rlast),.axi_rvalid(axi_rvalid));
reg[31:0]ram0[0:PIXELS-1],ram1[0:PIXELS-1];reg[23:0]golden[0:PIXELS-1];string golden_path,golden_root;integer golden_variant;reg golden_root_present=0;
integer generation=11,ui_ticks=0,source_commands=0,result_beats=0,result_words=0,total_publications=0;
integer result_commands=0,result_responses=0,result_commands_before=0,result_responses_before=0;
integer expected_errors=0,errors_seen=0;
integer read_index=0,read_total=0,read_delay=0;reg read_open=0;
reg[27:0]read_address=0,write_address=0,expected_source=0,expected_result=28'h200000;
integer k,j,index,x,y,offset,guard,read_before,write_before,frame_number=0;reg[31:0]want_word,actual_word;reg[27:0]consume_address;time began;
function[23:0]source_rgb(input integer address,input integer gen);begin
 source_rgb={8'((address+gen*13)%251),8'((address/7+gen*29)%253),8'((address/13+gen*41)%255)};
end endfunction
function[23:0]expected_rgb(input integer position);integer xx,yy;begin
 xx=position%OW;yy=position/OW;
 if(!FIX)expected_rgb=golden[position];
 else expected_rgb=(xx<1||xx>=1+AW) ? 0:source_rgb(yy*SW+xx-1,generation);
end endfunction
always @(negedge ui_clk)begin
 axi_awready=rst_n&&(ui_ticks%11!=3);axi_arready=rst_n&&!read_open&&(ui_ticks%13!=4);
 axi_wready=rst_n&&(write_open||(axi_awvalid&&axi_awready))&&(ui_ticks%7!=2);
 axi_rvalid=rst_n&&read_open&&(read_delay==0)&&(ui_ticks%9!=1);
 axi_rlast=read_index==read_total-1;
 for(k=0;k<8;k=k+1)axi_rdata[k*32+:32]={8'b0,source_rgb(read_address-expected_source+read_index*8+k,generation)};
end
always @(posedge ui_clk)if(rst_n)begin
 ui_ticks=ui_ticks+1;
 if(engine_fault)$fatal(1,"native engine fault reason=%0d",engine_reason);
 if(cmd_valid&&cmd_ready)begin
  if(cmd_write)begin
   if(!cmd_result_block||cmd_source_block)$fatal(1,"writer grant lost exclusive resultblock flag");
   result_commands=result_commands+1;
  end else if(!cmd_source_block||cmd_result_block)$fatal(1,"gather grant lost exclusive sourceblock flag");
 end
 if(rsp_valid&&rsp_write)begin
  result_responses=result_responses+1;
  if(write_open||result_words%64!=0)$fatal(1,"result response before eighth WREADY");
 end
 if(axi_arvalid&&axi_arready)begin
  if(read_open)$fatal(1,"overlapping native reads");
  if(axi_araddr<expected_source||axi_araddr+axi_arlen*8+7>=expected_source+SW*SH)$fatal(1,"source bank or range changed mid frame");
  if(axi_arlen!=7||axi_araddr[5:0]!=0)$fatal(1,"tile refill not an aligned64 native burst");
  read_open=1;read_address=axi_araddr;read_index=0;read_total=axi_arlen+1;read_delay=2;source_commands=source_commands+1;
 end
 if(read_delay>0)read_delay=read_delay-1;
 if(axi_rvalid)begin if(!read_open)$fatal(1,"unexpected read beat");if(axi_rlast)read_open=0;else read_index=read_index+1;end
 if(axi_awvalid&&axi_awready)begin
  if(write_open||axi_awlen!=7||axi_awaddr[5:0]!=0)$fatal(1,"result path must issue aligned64word AWLEN7 burst, got len=%0d addr=%h",axi_awlen,axi_awaddr);
  write_address=axi_awaddr;write_remaining=axi_awlen+1;write_open=1;
 end
 if(axi_wready&&write_open)begin
  consume_address=write_address;offset=consume_address-expected_result;
  if(offset!=result_words||offset<0||offset+7>=PIXELS)$fatal(1,"result bank/order mismatch addr=%h expected=%h",consume_address,expected_result+result_words);
  for(j=0;j<8;j=j+1)begin
   index=offset+j;want_word={8'b0,expected_rgb(index)};
   actual_word=expected_result==28'h200000 ? ram0[index] : ram1[index];
   for(integer bb=0;bb<4;bb=bb+1)if(axi_wstrb[j*4+bb])actual_word[bb*8+:8]=axi_wdata[j*32+bb*8+:8];
   if(actual_word!==want_word||axi_wstrb[j*4+:4]!==4'hf)$fatal(1,"native pixel mismatch frame=%0d pixel=%0d expected=%h got=%h mask=%h",frame_number,index,want_word,actual_word,axi_wstrb);
   if(expected_result==28'h200000)ram0[index]=actual_word;else ram1[index]=actual_word;
  end
  result_words=result_words+8;result_beats=result_beats+1;write_remaining=write_remaining-1;write_address=write_address+8;if(write_remaining==0)write_open=0;
 end
end
always @(posedge proc_clk)if(rst_n&&error)begin
 if(expected_errors==0||failure_reason!=3)$fatal(1,"path fault reason=%0d pixels=%0d",failure_reason,completed_pixels);
 errors_seen=errors_seen+1;
end
task launch(input integer bank,input integer srcbank,input integer gen);begin
 guard=0;while(!start_ready)begin @(negedge proc_clk);guard=guard+1;if(guard>200000)$fatal(1,"start_ready timeout");end
 generation=gen;
 if(!FIX)begin
  if(golden_root_present)begin golden_variant=(gen==11)?0:(gen==29)?1:2;if(nearest)golden_path=$sformatf("%s/variant%0d/expected_nearest.hex",golden_root,golden_variant);else golden_path=$sformatf("%s/variant%0d/expected_bilinear.hex",golden_root,golden_variant);end
  $readmemh(golden_path,golden);
 end
 source_base=srcbank ? 28'h800000:0;expected_source=source_base;frame_bank=bank;expected_result=bank ? 28'h400000:28'h200000;result_words=0;
 @(negedge proc_clk);start=1;began=$time;read_before=source_commands;write_before=result_beats;result_commands_before=result_commands;result_responses_before=result_responses;@(negedge proc_clk);start=0;
 // Pins may change after start; every accepted request retains the session values.
 source_base=source_base^28'h800000;frame_bank=~frame_bank;
end endtask
task finishframe;begin
 guard=0;while(!done)begin @(negedge proc_clk);guard=guard+1;if(guard>20000000)$fatal(1,"publication timeout");end
 if(result_words!=PIXELS||completed_pixels!=PIXELS||read_open||write_open)$fatal(1,"published before native result retirement");
 if(result_commands-result_commands_before!=PIXELS/64||result_responses-result_responses_before!=PIXELS/64)$fatal(1,"publication lost or duplicated result command acknowledgement");
 for(index=0;index<PIXELS;index=index+1)if((expected_result==28'h200000 ? ram0[index] : ram1[index])!=={8'b0,expected_rgb(index)})$fatal(1,"RAM readback mismatch");
 total_publications=total_publications+1;
 $display("PASS burst path publication=%0d shape=%0dx%0d active=%0d source=%0dx%0d elapsed_ns=%0d proc_cycles=%0d source_commands=%0d result_commands=%0d result_beats=%0d result_responses=%0d generation_pattern=%0d",total_publications,OW,OH,AW,SW,SH,$time-began,processor_cycles,source_commands-read_before,result_commands-result_commands_before,result_beats-write_before,result_responses-result_responses_before,generation);
 @(negedge proc_clk);frame_number=frame_number+1;
end endtask
initial begin
 nearest=$test$plusargs("NEAREST");
 golden_root_present=$value$plusargs("GOLDEN_ROOT=%s",golden_root);
 if(!FIX&&!golden_root_present&&!$value$plusargs("GOLDEN=%s",golden_path))$fatal(1,"solver requires independent GOLDEN file or GOLDEN_ROOT");
 #100;rst_n=1;repeat(20)@(negedge proc_clk);
 abort=1;start=1;#1;if(start_ready)$fatal(1,"start accepted during abort");
 repeat(2)@(negedge proc_clk);start=0;abort=0;#1;if(busy||done)$fatal(1,"coincident abort/start launched work");
 if(!FIX)begin
  expected_errors=1;input_geometry_valid=0;launch(0,0,11);guard=0;
  while(errors_seen==0)begin @(negedge proc_clk);guard=guard+1;if(guard>2000)$fatal(1,"invalid geometry did not report failure");end
  repeat(5)@(negedge proc_clk);
  if(busy||done||!start_ready||result_words!=0||result_commands!=result_commands_before||source_commands!=read_before)$fatal(1,"invalid geometry performed native traffic or blocked recovery");
  expected_errors=0;input_geometry_valid=1;
  $display("PASS invalid geometry rejected before native traffic, next frame ready");
 end
 launch(0,0,11);finishframe();
 launch(1,1,29);finishframe();launch(0,0,43);finishframe();
 if($test$plusargs("ABORT_TEST"))begin
  launch(1,1,29);while(result_words<64)@(negedge proc_clk);
  abort=1;@(negedge proc_clk);abort=0;
  repeat(10000)begin @(negedge proc_clk);if(done)$fatal(1,"aborted frame published");end
  if(write_open||read_open)$fatal(1,"aborted native traffic did not retire");
  $display("PASS native abort retired prefix_words=%0d without publication",result_words);
  launch(0,0,43);finishframe();
 end
 $display("PASS stream native integration complete publications=%0d",total_publications);$finish;
end
initial begin #500000000;$fatal(1,"native integration watchdog");end
endmodule





