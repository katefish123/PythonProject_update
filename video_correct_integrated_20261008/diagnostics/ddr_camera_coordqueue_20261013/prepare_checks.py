from pathlib import Path
import json
D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'results'
p=O/'tb_ddr_full_frame.sv'
s=p.read_text(encoding='utf-8-sig')
anchor=' reg test_passed=0;'
assert s.count(anchor)==1
s=s.replace(anchor,anchor+'''
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
''')
anchor='  $display("DDR_FULL_FRAME_CYCLES=%0d GEOMETRY_VALID=%b",cycles,geometry_valid);'
assert s.count(anchor)==1
s=s.replace(anchor,anchor+'''
  if(issued_observed!=PIXELS || enqueued_observed!=PIXELS || popped_observed!=PIXELS || accepted_observed!=PIXELS || dut.coord_count!=0 || dut.coord_reserved!=0)$fatal(1,"coordinate frame did not fully drain");
  for(integer s=0;s<12;s=s+1)$display("PROFILE_STAGE state=%0d cycles=%0d",s,stage_cycles[s]);
  $display("PROFILE_TOTAL=%0d",profile_total);
  $display("COORDINATE_CREDIT_PASS issued=%0d enqueued=%0d popped=%0d accepted=%0d max_reserved=%0d max_queued=%0d",issued_observed,enqueued_observed,popped_observed,accepted_observed,max_reserved,max_queued);
''')
p.write_text(s,encoding='utf-8')
cases=json.loads((O/'simulation_cases.json').read_text(encoding='utf-8-sig'))
(O/'simulation_cases.json').write_text(json.dumps(cases,indent=2)+'\n',encoding='utf-8')
print('Native golden now checks coordinate tags, all credit conservation and final drain.')
