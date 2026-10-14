`timescale 1ns/1ps
module tb_ddr_full_frame;
 localparam SRC_W=960,SRC_H=540,OUT_W=640,OUT_H=904;
 localparam PIXELS=OUT_W*OUT_H,BEATS=PIXELS/8;
 localparam [27:0] OUT_BASE=28'h0100000;
 reg clk=0,rst_n=0,start=0,frame_start=0;
 always #18.518518 clk=~clk;

 wire busy,done,error,geometry_valid;
 wire mem_valid,mem_ready,mem_rsp_valid;
 wire [23:0] mem_addr,mem_rgb;
 wire write_valid,write_ready;
 wire [23:0] write_addr,write_rgb;
 wire [31:0] cycles,completed_pixels;
 wire cache_cmd_valid,cache_cmd_ready,cache_cmd_write;
 wire [27:0] cache_cmd_addr;
 wire [255:0] cache_cmd_wdata,cache_rsp_rdata;
 wire [31:0] cache_cmd_wstrb;
 wire cache_rsp_valid,cache_rsp_write;
 wire wr_drained,wr_fault,wr_cmd_valid,wr_cmd_ready,wr_cmd_write;
 wire [27:0] wr_cmd_addr;
 wire [255:0] wr_cmd_wdata;
 wire [31:0] wr_cmd_wstrb;
 wire wr_rsp_valid,wr_rsp_write;
 reg [23:0] source[0:SRC_W*SRC_H-1];
 reg [23:0] expected[0:PIXELS-1];
 reg [31:0] ram[0:SRC_W*SRC_H-1];
 reg [31:0] rng=32'h6d2b79f5;
 reg mem_pending=0;
 integer mem_delay=0,read_beats=0,write_beats=0;
 reg [255:0] pending_data=0;
 reg cache_rsp_valid_r=0;
 reg [255:0] cache_rsp_data_r=0;
 reg wr_rsp_valid_r=0;
 integer writes_checked=0;
 integer first_read=-1,last_read=-1;
 integer first_write=-1,last_write=-1;
 integer row_boundary_checks=0;
 reg test_passed=0;
 integer stage_cycles[0:11];integer profile_total=0;
 integer issued_observed=0,enqueued_observed=0,popped_observed=0,accepted_observed=0;
 integer max_reserved=0,max_queued=0;
 initial begin for(integer s=0;s<12;s=s+1)stage_cycles[s]=0;end
 always @(posedge clk)begin
  if(!rst_n)begin issued_observed=0;enqueued_observed=0;popped_observed=0;accepted_observed=0;end
  else begin
   if(dut.coord_reserved>16 || dut.coord_count>16)$fatal(1,"coordinate credit overflow");
   if(dut.coord_reserved!==issued_observed-accepted_observed)$fatal(1,"coordinate credit conservation");
   if(dut.coord_count!==enqueued_observed-popped_observed)$fatal(1,"coordinate FIFO conservation");
   if(dut.dst_valid)issued_observed=issued_observed+1;
   if(dut.coord_push)begin
    if(dut.req_tag[11:0]!==enqueued_observed%OUT_W || dut.req_tag[23:12]!==enqueued_observed/OUT_W)$fatal(1,"coordinate returned out of order");
    enqueued_observed=enqueued_observed+1;
   end
   if(dut.coord_pop)begin
    if(dut.coord_tags[dut.coord_rptr][11:0]!==popped_observed%OUT_W || dut.coord_tags[dut.coord_rptr][23:12]!==popped_observed/OUT_W)$fatal(1,"coordinate dequeued out of order");
    popped_observed=popped_observed+1;
   end
   if(write_valid&&write_ready)accepted_observed=accepted_observed+1;
   if(dut.coord_reserved>max_reserved)max_reserved=dut.coord_reserved;
   if(dut.coord_count>max_queued)max_queued=dut.coord_count;
   if(busy)begin
    profile_total=profile_total+1;
    if(dut.state<=11)stage_cycles[dut.state]=stage_cycles[dut.state]+1;
   end
  end
 end


 assign cache_cmd_ready=cache_cmd_valid && !mem_pending && rng[2:0]!=3'b000;
 assign cache_rsp_valid=cache_rsp_valid_r;
 assign cache_rsp_write=1'b0;
 assign cache_rsp_rdata=cache_rsp_data_r;
 assign wr_cmd_ready=wr_cmd_valid && rng[5:3]!=3'b000;
 assign wr_rsp_valid=wr_rsp_valid_r;
 assign wr_rsp_write=1'b1;

 frame_processor #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),
  .MIN_PIXELS(16),.MAX_PIXELS(4096),.MAX_SPAN(128),.TIMEOUT_CYCLES(12000000)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.nearest(1'b0),.busy(busy),.done(done),.error(error),
  .mem_valid(mem_valid),.mem_ready(mem_ready),.mem_addr(mem_addr),
  .mem_rsp_valid(mem_rsp_valid),.mem_rgb(mem_rgb),
  .write_valid(write_valid),.write_ready(write_ready),.write_addr(write_addr),.write_rgb(write_rgb),
  .cycles(cycles),.completed_pixels(completed_pixels),.geometry_valid(geometry_valid));

 ddr_pixel_cache cache(
  .clk(clk),.rst_n(rst_n),.invalidate(1'b0),
  .mem_valid(mem_valid),.mem_ready(mem_ready),.mem_addr(mem_addr),
  .mem_rsp_valid(mem_rsp_valid),.mem_rgb(mem_rgb),.base_word_addr(28'd0),
  .cmd_valid(cache_cmd_valid),.cmd_ready(cache_cmd_ready),.cmd_write(cache_cmd_write),
  .cmd_addr(cache_cmd_addr),.cmd_wdata(cache_cmd_wdata),.cmd_wstrb(cache_cmd_wstrb),
  .rsp_valid(cache_rsp_valid),.rsp_write(cache_rsp_write),.rsp_rdata(cache_rsp_rdata));

 ddr_result_writer #(.OUT_W(OUT_W),.OUT_H(OUT_H),.BASE0(OUT_BASE),.BASE1(OUT_BASE+28'h100000)) writer(
  .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.abort_frame(1'b0),.frame_bank(1'b0),
  .write_valid(write_valid),.write_ready(write_ready),.write_addr(write_addr),.write_rgb(write_rgb),
  .drained(wr_drained),.fault(wr_fault),.cmd_valid(wr_cmd_valid),.cmd_ready(wr_cmd_ready),
  .cmd_write(wr_cmd_write),.cmd_addr(wr_cmd_addr),.cmd_wdata(wr_cmd_wdata),.cmd_wstrb(wr_cmd_wstrb),
  .rsp_valid(wr_rsp_valid),.rsp_write(wr_rsp_write));

 always @(posedge clk) begin
  rng <= {rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  cache_rsp_valid_r <= 1'b0;
  wr_rsp_valid_r <= 1'b0;
  if(!rst_n) begin
   mem_pending <= 0; mem_delay <= 0; cache_rsp_data_r <= 0;
  end else begin
   if(cache_cmd_valid && cache_cmd_ready) begin
    if(cache_cmd_write!==1'b0 || cache_cmd_addr[2:0]!==3'b000 || cache_cmd_addr+7 >= SRC_W*SRC_H)
     $fatal(1,"invalid cache DDR read addr=%0d write=%b",cache_cmd_addr,cache_cmd_write);
    if(first_read<0) first_read=cache_cmd_addr;
    last_read=cache_cmd_addr;
    read_beats=read_beats+1;
    for(integer lane=0;lane<8;lane=lane+1)
      pending_data[lane*32+:32] <= ram[(cache_cmd_addr+lane)];
    mem_pending <= 1;
    mem_delay <= 1 + (rng[10:8] % 7);
   end else if(mem_pending) begin
    if(mem_delay>0) mem_delay<=mem_delay-1;
    else begin
     cache_rsp_data_r <= pending_data;
     cache_rsp_valid_r <= 1;
     mem_pending <= 0;
    end
   end

   if(write_valid && write_ready) begin
    if(write_addr >= PIXELS) $fatal(1,"writer received out-of-range pixel %0d",write_addr);
    if(write_addr==0 || write_addr==OUT_W-1 || write_addr==OUT_W || write_addr==PIXELS-1)
      row_boundary_checks=row_boundary_checks+1;
   end
   if(wr_cmd_valid && wr_cmd_ready) begin
    if(wr_cmd_write!==1'b1) $fatal(1,"result writer issued a read");
    if(wr_cmd_addr[2:0]!==3'b000) $fatal(1,"unaligned output beat addr=%h",wr_cmd_addr);
    if(wr_cmd_wstrb!==32'hffffffff) $fatal(1,"bad pixel byte strobes beat=%0d %h",write_beats,wr_cmd_wstrb);
    if(wr_cmd_addr!==OUT_BASE+write_beats*8)
      $fatal(1,"output address mismatch beat=%0d got=%h expected=%h",write_beats,wr_cmd_addr,OUT_BASE+write_beats*8);
    for(integer lane=0;lane<8;lane=lane+1) begin
     if(wr_cmd_wdata[lane*32+:32] !== {8'd0,expected[write_beats*8+lane]})
      $fatal(1,"RGB32 lane mismatch beat=%0d lane=%0d got=%h expected=%h",write_beats,lane,
       wr_cmd_wdata[lane*32+:32],{8'd0,expected[write_beats*8+lane]});
    end
    if(first_write<0) first_write=wr_cmd_addr;
    last_write=wr_cmd_addr;
    write_beats=write_beats+1;
    writes_checked=writes_checked+8;
    wr_rsp_valid_r<=1;
   end
  end
 end

 initial begin
  $readmemh("C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_coordqueue_20261013/results/source_960x540.hex",source);
  $readmemh("C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_coordqueue_20261013/results/expected_640x904.hex",expected);
  for(integer i=0;i<SRC_W*SRC_H;i=i+1) ram[i]={8'd0,source[i]};
  repeat(6) @(negedge clk);
  rst_n=1;
  @(negedge clk); frame_start=1; start=1;
  @(negedge clk); frame_start=0; start=0;
  wait(done || error);
  @(negedge clk);
  repeat(3) @(negedge clk);
  if(error) $fatal(1,"frame processor error cycles=%0d",cycles);
  if(!geometry_valid) $fatal(1,"automatic marker geometry was not accepted");
  if(completed_pixels!==PIXELS || writes_checked!==PIXELS)
   $fatal(1,"pixel total mismatch completed=%0d packed=%0d expected=%0d",completed_pixels,writes_checked,PIXELS);
  if(write_beats!==BEATS || !wr_drained || wr_fault)
   $fatal(1,"writer drain mismatch beats=%0d/%0d drained=%b fault=%b",write_beats,BEATS,wr_drained,wr_fault);
  if(first_read!==0 || last_read<0 || last_read[2:0]!==3'b000)
   $fatal(1,"source DDR address endpoints invalid first=%0d last=%0d",first_read,last_read);
  if(first_write!==OUT_BASE || last_write!==OUT_BASE+(BEATS-1)*8)
   $fatal(1,"output DDR address endpoints invalid first=%h last=%h",first_write,last_write);
  if(row_boundary_checks!=4) $fatal(1,"missing row-boundary address probes count=%0d",row_boundary_checks);
  $display("DDR_FULL_FRAME_PASS pixels=%0d beats=%0d source_reads=%0d",writes_checked,write_beats,read_beats);
  $display("DDR_FULL_FRAME_ADDR source_first=%0d source_last=%0d out_first=%h out_last=%h",first_read,last_read,first_write,last_write);
  $display("DDR_FULL_FRAME_CYCLES=%0d GEOMETRY_VALID=%b",cycles,geometry_valid);
  if(issued_observed!=PIXELS || enqueued_observed!=PIXELS || popped_observed!=PIXELS || accepted_observed!=PIXELS || dut.coord_count!=0 || dut.coord_reserved!=0)$fatal(1,"coordinate frame did not fully drain");
  for(integer s=0;s<12;s=s+1)$display("PROFILE_STAGE state=%0d cycles=%0d",s,stage_cycles[s]);
  $display("PROFILE_TOTAL=%0d",profile_total);
  $display("COORDINATE_CREDIT_PASS issued=%0d enqueued=%0d popped=%0d accepted=%0d max_reserved=%0d max_queued=%0d",issued_observed,enqueued_observed,popped_observed,accepted_observed,max_reserved,max_queued);

  test_passed=1;
  $display("DDR_FULL_FRAME_TEST_PASSED=%0d",test_passed);
  $finish;
 end
 initial begin #4000000000.0; $fatal(1,"full frame simulation timeout"); end
endmodule
