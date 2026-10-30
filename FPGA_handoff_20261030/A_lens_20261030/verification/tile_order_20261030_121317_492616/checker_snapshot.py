"""Check64x8/raster traversal and actual processor/writer control RTL.

The processor boundary uses an explicit coordinate/tag passthrough math model:
this checks traversal, independent stalls, addresses and frame-affine commits,
not affine arithmetic, lens accuracy, DDR throughput or hardware30fps.
"""
from pathlib import Path
import datetime,hashlib,json,re,shutil,struct,subprocess,sys

ROOT=Path(__file__).resolve().parent.parent
CANDIDATE=ROOT/'candidate_host_angle_v1'
TOOLS=Path('C:/modeltech64_2020.4/win64')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()


def oracle(k,width,tiled):
    if not tiled:return k%width,k//width
    tile=k//512
    return (tile%(width//64))*64+k%64,(tile//(width//64))*8+(k//64)%8


def full_extent_check(width=1920,height=1080):
    results=[]
    for tiled in [False,True]:
        seen=bytearray(width*height);x=y=address=0;digest=hashlib.sha256()
        jumps=0
        for k in range(width*height):
            assert (x,y)==oracle(k,width,tiled)
            assert address==y*width+x and 0<=address<len(seen) and not seen[address]
            seen[address]=1;digest.update(struct.pack('<I',address))
            if k%64==0:assert address%64==0;burst_first=address
            assert address==burst_first+k%64
            nx,ny=x+1,y;next_addr=address+1
            if tiled and x%64==63:
                if y%8!=7:nx,ny=x-63,y+1;next_addr=address+width-63
                elif x==width-1:nx,ny=0,y+1
                else:nx,ny=x+1,y-7;next_addr=address+1-7*width
            elif not tiled and x==width-1:nx,ny=0,y+1
            jumps+=next_addr!=address+1
            x,y,address=nx,ny,next_addr
        assert all(seen) and address==width*height
        results.append({'tiled':tiled,'pixels':len(seen),'bursts':len(seen)//64,
                        'nonlinear_block_jumps':jumps,'every_pixel_once':True,
                        'contiguous_aligned64word_bursts':True,
                        'address_sequence_sha256':digest.hexdigest()})
    return results


BENCH=r'''`timescale 1ns/1ps
module coordinate_math_stub(
 input wire clk,rst_n,in_valid,nearest,input wire[11:0]dst_x,dst_y,
 output reg req_valid,req_inside,req_error,output reg[23:0]req_tag,addr00,addr10,addr01,addr11,
 output reg[7:0]req_fx,req_fy,
 input wire rsp_valid,rsp_inside,input wire[23:0]rsp_tag,p00,p10,p01,p11,input wire[7:0]rsp_fx,rsp_fy,
 output reg out_valid,output reg[23:0]out_rgb,out_tag);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin req_valid<=0;req_inside<=0;req_error<=0;req_tag<=0;addr00<=0;addr10<=0;addr01<=0;addr11<=0;req_fx<=0;req_fy<=0;out_valid<=0;out_rgb<=0;out_tag<=0;end
  else begin
   req_valid<=in_valid;req_inside<=1;req_error<=0;req_tag<={dst_y,dst_x};
   addr00<=dst_y*128+dst_x;addr10<=dst_y*128+dst_x;addr01<=dst_y*128+dst_x;addr11<=dst_y*128+dst_x;req_fx<=0;req_fy<=0;
   out_valid<=rsp_valid;out_rgb<=p00;out_tag<=rsp_tag;
  end
 end
endmodule
module lens_affine_instance(
 input wire clk,rst_n,in_valid,nearest,input wire[239:0]affine,input wire[11:0]dst_x,dst_y,
 output wire req_valid,req_inside,req_error,output wire[23:0]req_tag,addr00,addr10,addr01,addr11,
 output wire[7:0]req_fx,req_fy,
 input wire rsp_valid,rsp_inside,input wire[23:0]rsp_tag,p00,p10,p01,p11,input wire[7:0]rsp_fx,rsp_fy,
 output wire out_valid,output wire[23:0]out_rgb,out_tag);
 coordinate_math_stub model(.*);
endmodule
module lens_autocrop_instance(
 input wire clk,rst_n,in_valid,nearest,input wire[11:0]dst_x,dst_y,
 output wire req_valid,req_inside,req_error,output wire[23:0]req_tag,addr00,addr10,addr01,addr11,
 output wire[7:0]req_fx,req_fy,
 input wire rsp_valid,rsp_inside,input wire[23:0]rsp_tag,p00,p10,p01,p11,input wire[7:0]rsp_fx,rsp_fy,
 output wire out_valid,output wire[23:0]out_rgb,out_tag);
 coordinate_math_stub model(.*);
endmodule

module processor_case #(parameter TILE=0,RUNTIME=0)(output reg finished=0);
 localparam W=128,H=16,N=W*H;
 localparam[239:0]SAFE={40'h0006000000,40'h0000fe56d6,40'h0000000000,40'h0008b988e6,40'h0000000000,40'h0000fe56d6};
 localparam[239:0]A={40'h0009000000,40'h0001000000,40'h0000000000,40'h0002000000,40'h0000000000,40'h0001000000};
 localparam[239:0]B={40'h000a000000,40'h0000ff0000,40'h0000000010,40'h0003000000,40'h0000000020,40'h0000ff0000};
 reg clk=0,rst_n=0,start=0,abort=0;always #5 clk=~clk;
 reg cfg_valid=0;wire cfg_ready;reg[239:0]cfg_affine=SAFE;reg[15:0]cfg_sequence=0;wire commit_valid;wire[15:0]commit_sequence;
 wire[359:0]debug_h;wire busy,done,error,geometry_valid;wire[3:0]failure_reason;wire[31:0]cycles,completed_pixels;
 wire q_valid,q_inside,q_nearest,r_ready,write_valid;wire[23:0]q_addr00,q_addr10,q_addr01,q_addr11,q_tag,write_addr,write_rgb;
 wire[7:0]q_fx,q_fy;wire[31:0]q_generation;
 integer tick=0,qn=0,rn=0,wn=0,qstalls=0,rstalls=0,wstalls=0,commits=0;
 reg[23:0]tags[0:4095];reg[31:0]gens[0:4095];
 wire q_ready=(tick%11>=4)&&(qn-rn<100);
 wire r_valid=(rn<qn)&&(tick%9>=3);
 wire[23:0]r_tag=tags[rn];wire[31:0]r_generation=gens[rn];
 wire[23:0]response_rgb=((r_tag[23:12]*W+r_tag[11:0])^24'h5a1234);
 wire write_ready=(tick%101>=73);
 frame_processor_stream #(.SRC_W(W),.SRC_H(H),.OUT_W(W),.OUT_H(H),.ACTIVE_W(W),.ACTIVE_X(0),.FIXED_IDENTITY(1),.TILED_ORDER(TILE),.RUNTIME_AFFINE(RUNTIME)) dut(
 .debug_h(debug_h),.clk(clk),.rst_n(rst_n),.start(start),.abort(abort),.nearest(1'b1),.input_geometry_valid(1'b0),.input_corners(96'd0),
 .busy(busy),.done(done),.error(error),.failure_reason(failure_reason),.cycles(cycles),.completed_pixels(completed_pixels),.geometry_valid(geometry_valid),
 .q_valid(q_valid),.q_ready(q_ready),.q_inside(q_inside),.q_nearest(q_nearest),.q_addr00(q_addr00),.q_addr10(q_addr10),.q_addr01(q_addr01),.q_addr11(q_addr11),.q_tag(q_tag),.q_fx(q_fx),.q_fy(q_fy),.q_generation(q_generation),
 .r_valid(r_valid),.r_ready(r_ready),.r_inside(1'b1),.r_p00(response_rgb),.r_p10(response_rgb),.r_p01(response_rgb),.r_p11(response_rgb),.r_tag(r_tag),.r_fx(8'd0),.r_fy(8'd0),.r_generation(r_generation),
 .write_valid(write_valid),.write_ready(write_ready),.write_addr(write_addr),.write_rgb(write_rgb),
 .cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_affine(cfg_affine),.cfg_sequence(cfg_sequence),.commit_valid(commit_valid),.commit_sequence(commit_sequence));
 function[23:0]position(input integer k);
 integer x,y,t;
 begin
  if(TILE)begin t=k/512;x=(t%(W/64))*64+k%64;y=(t/(W/64))*8+(k/64)%8;end
  else begin x=k%W;y=k/W;end
  position=(y<<12)|x;
 end endfunction
 function[23:0]address(input integer k);reg[23:0]p;begin p=position(k);address=p[23:12]*W+p[11:0];end endfunction
 always @(posedge clk)if(rst_n)begin
  tick=tick+1;
  if(error)$fatal(1,"PROCESSOR_ERROR TILE=%0d reason=%0d",TILE,failure_reason);
  if(commit_valid)commits=commits+1;
  if(q_valid&&!q_ready)qstalls=qstalls+1;
  if(r_valid&&!r_ready)rstalls=rstalls+1;
  if(write_valid&&!write_ready)wstalls=wstalls+1;
  if(q_valid&&q_ready)begin
   if(qn>=N||q_tag!==position(qn))$fatal(1,"Q_ORDER TILE=%0d n=%0d tag=%h",TILE,qn,q_tag);
   tags[qn]=q_tag;gens[qn]=q_generation;qn=qn+1;
  end
  if(r_valid&&r_ready)rn=rn+1;
  if(write_valid&&write_ready)begin
   if(wn>=N||write_addr!==address(wn)||write_rgb!==(address(wn)^24'h5a1234))$fatal(1,"PIXEL_ORDER TILE=%0d n=%0d addr=%0d",TILE,wn,write_addr);
   wn=wn+1;
  end
 end
 task launch(input bit new_command,input[239:0]affine,input[15:0]seq);
 begin
  qn=0;rn=0;wn=0;@(negedge clk);cfg_affine=affine;cfg_sequence=seq;cfg_valid=new_command;start=1;
  #1;if(cfg_ready!==RUNTIME[0])$fatal(1,"CONFIG_READY TILE=%0d",TILE);
  @(negedge clk);start=0;cfg_valid=0;
  if(RUNTIME&&(dut.active_affine!==affine||commit_valid!==new_command))$fatal(1,"CONFIG_SNAPSHOT TILE=%0d",TILE);
  if(RUNTIME&&new_command&&commit_sequence!==seq)$fatal(1,"CONFIG_SEQUENCE TILE=%0d",TILE);
 end endtask
 task wait_frame(input[239:0]affine);
 integer timeout;
 begin
  timeout=0;
  while(!done&&timeout<50000)begin @(negedge clk);timeout=timeout+1;
   if(RUNTIME&&dut.active_affine!==affine)$fatal(1,"MIDFRAME_AFFINE_CHANGED");
  end
  if(!done||wn!=N||qn!=N||rn!=N||completed_pixels!=N)$fatal(1,"PROCESSOR_INCOMPLETE TILE=%0d counts=%0d/%0d/%0d",TILE,qn,rn,wn);
  if(RUNTIME&&debug_h!=={40'h0001000000,40'd0,40'd0,affine})$fatal(1,"DEBUG_H_ORDER");
  repeat(3)@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
  if(dut.active_affine!==SAFE)$fatal(1,"CONFIG_RESET_DEFAULT");
  launch(1,A,16'd17);
  repeat(15)@(negedge clk);cfg_affine=B;cfg_valid=1;cfg_sequence=18;
  repeat(20)begin @(negedge clk);if(cfg_ready||commit_valid)$fatal(1,"MIDFRAME_COMMAND_ACCEPTED");end
  cfg_valid=0;wait_frame(A);
  if(RUNTIME&&dut.active_affine!==A)$fatal(1,"IDLE_AFFINE_CLEARED");
  launch(0,B,16'd18);wait_frame(B);
  if(RUNTIME&&(commits!=1||commit_sequence!=17))$fatal(1,"NO_COMMAND_RECEIPT");
  launch(1,A,16'd19);while(wn<25)@(negedge clk);abort=1;@(negedge clk);abort=0;cfg_valid=0;
  repeat(8)@(negedge clk);
  if(busy||write_valid||done)$fatal(1,"PROCESSOR_ABORT_LEAK");
  if(qstalls==0||rstalls==0||wstalls==0)$fatal(1,"MISSING_PIPELINE_STALL_COVERAGE %0d/%0d/%0d",qstalls,rstalls,wstalls);
  $display("PROCESSOR_ORDER_PASS tiled=%0d runtime=%0d full_frames=2 qstalls=%0d rstalls=%0d wstalls=%0d abort=1 cfg_snapshot_no_new_command=1",TILE,RUNTIME,qstalls,rstalls,wstalls);
  finished=1;
 end
endmodule

module writer_case #(parameter TILE=0)(output reg finished=0);
 localparam W=128,H=16,N=W*H;localparam[27:0]BASE0=28'h0100000,BASE1=28'h0200000;
 reg clk=0,ui_clk=0,rst_n=0;always #5 clk=~clk;always #7 ui_clk=~ui_clk;
 reg frame_start=0,abort_frame=0,frame_bank=0,write_valid=0;reg[23:0]write_addr=0,write_rgb=0;
 wire write_ready,drained,fault,cmd_valid,cmd_write,cmd_write_block;wire[27:0]cmd_addr;wire[255:0]cmd_wdata;wire[31:0]cmd_wstrb;wire[2047:0]cmd_block_data;
 integer ui_tick=0,delay_count=0,block_index=0,total_blocks=0,input_stalls=0,held_cycles=0;
 reg native_enable=1,rsp_valid=0,rsp_write=1;reg[27:0]score_base=BASE0;
 wire cmd_ready=native_enable&&ui_tick>300&&(ui_tick%13>=9);
 ddr_result_writer_burst64 #(.OUT_W(W),.OUT_H(H),.BASE0(BASE0),.BASE1(BASE1),.FIFO_ADDR_BITS(2),.TILED_ORDER(TILE)) dut(
 .clk(clk),.rst_n(rst_n),.ui_clk(ui_clk),.ui_rst_n(rst_n),.frame_start(frame_start),.abort_frame(abort_frame),.frame_bank(frame_bank),
 .write_valid(write_valid),.write_ready(write_ready),.write_addr(write_addr),.write_rgb(write_rgb),.drained(drained),.fault(fault),
 .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),.cmd_write_block(cmd_write_block),.cmd_block_data(cmd_block_data),.rsp_valid(rsp_valid),.rsp_write(rsp_write));
 function[23:0]address(input integer k);integer x,y,t;
 begin
  if(TILE)begin t=k/512;x=(t%(W/64))*64+k%64;y=(t/(W/64))*8+(k/64)%8;end
  else begin x=k%W;y=k/W;end
  address=y*W+x;
 end endfunction
 function[23:0]rgb(input[23:0]a);begin rgb=a^24'h63a52c;end endfunction
 reg prev_held=0;reg[27:0]held_addr;reg[2047:0]held_data;
 always @(posedge ui_clk)begin
  if(!rst_n)begin ui_tick=0;delay_count=0;rsp_valid<=0;prev_held<=0;end
  else begin
   ui_tick=ui_tick+1;rsp_valid<=0;
   if(prev_held&&(cmd_addr!==held_addr||cmd_block_data!==held_data||!cmd_valid))$fatal(1,"WRITER_UNSTABLE_COMMAND TILE=%0d",TILE);
   prev_held<=cmd_valid&&!cmd_ready;held_addr<=cmd_addr;held_data<=cmd_block_data;
   if(cmd_valid&&!cmd_ready)held_cycles=held_cycles+1;
   if(delay_count>0)begin delay_count=delay_count-1;if(delay_count==0)rsp_valid<=1;end
   if(cmd_valid&&cmd_ready)begin
    if(delay_count!=0||!cmd_write||!cmd_write_block||cmd_wstrb!==32'hffffffff||cmd_addr!==score_base+address(block_index*64))$fatal(1,"WRITER_COMMAND TILE=%0d block=%0d addr=%h",TILE,block_index,cmd_addr);
    for(integer j=0;j<64;j=j+1)if(cmd_block_data[j*32+:32]!=={8'd0,rgb(address(block_index*64)+j)})$fatal(1,"WRITER_DATA TILE=%0d block=%0d word=%0d",TILE,block_index,j);
    block_index=block_index+1;total_blocks=total_blocks+1;delay_count=6+(total_blocks%11);
   end
  end
 end
 task start_frame(input bit bank);
 begin
  while(!drained)@(negedge clk);
  repeat(4)@(negedge clk);block_index=0;score_base=bank?BASE1:BASE0;frame_bank=bank;frame_start=1;
  @(negedge clk);frame_start=0;
 end endtask
 task send_pixel(input[23:0]a);
 begin
  @(negedge clk);write_addr=a;write_rgb=rgb(a);write_valid=1;
  @(posedge clk);while(!write_ready)begin input_stalls=input_stalls+1;@(posedge clk);end
  @(negedge clk);write_valid=0;
 end endtask
 task wait_drain;
 integer t;
 begin
  t=0;while(!drained&&t<30000)begin @(negedge clk);t=t+1;end
  if(!drained)$fatal(1,"WRITER_DRAIN_TIMEOUT TILE=%0d",TILE);
  repeat(5)@(negedge clk);
 end endtask
 initial begin
  repeat(6)@(negedge clk);rst_n=1;repeat(10)@(negedge clk);
  start_frame(1);for(integer k=0;k<N;k=k+1)send_pixel(address(k));wait_drain();
  if(fault||block_index!=N/64||dut.expected_addr!=N)$fatal(1,"WRITER_FRAME_FAIL TILE=%0d blocks=%0d",TILE,block_index);
  start_frame(0);send_pixel(24'd1);repeat(3)@(negedge clk);
  if(!fault||write_ready||block_index!=0)$fatal(1,"WRONG_ADDRESS_NOT_REJECTED TILE=%0d",TILE);
  abort_frame=1;@(negedge clk);abort_frame=0;wait_drain();
  start_frame(1);native_enable=0;for(integer k=0;k<70;k=k+1)send_pixel(address(k));
  abort_frame=1;@(negedge clk);abort_frame=0;
  if(drained)$fatal(1,"ABORT_RELEASED_OWNED_BURST TILE=%0d",TILE);
  native_enable=1;wait_drain();
  if(fault||block_index!=1||write_ready)$fatal(1,"ABORT_PARTIAL_LEAK TILE=%0d blocks=%0d",TILE,block_index);
  start_frame(0);for(integer k=0;k<N;k=k+1)send_pixel(address(k));wait_drain();
  if(fault||block_index!=N/64||total_blocks!=2*N/64+1)$fatal(1,"WRITER_RESTART_FAIL TILE=%0d",TILE);
  if(input_stalls==0||held_cycles==0)$fatal(1,"MISSING_WRITER_STALL_COVERAGE");
  $display("WRITER_ORDER_PASS tiled=%0d full_frames=2 bursts=%0d input_stalls=%0d cmd_stalls=%0d wrong_address_rejected=1 partial_abort_drained=1 restart=1",TILE,total_blocks,input_stalls,held_cycles);
  finished=1;
 end
endmodule

module tb_tile_order;
 wire p0,p1,w0,w1;
 processor_case #(.TILE(0),.RUNTIME(0)) legacy_processor(p0);
 processor_case #(.TILE(1),.RUNTIME(1)) tiled_processor(p1);
 writer_case #(.TILE(0)) legacy_writer(w0);
 writer_case #(.TILE(1)) tiled_writer(w1);
 initial begin wait(p0&&p1&&w0&&w1);$display("TILE_ORDER_RTL_PASS raster_default=1 tiled=1 runtime_commit=1");$finish;end
 initial begin #2000000;$fatal(1,"TILE_ORDER_TIMEOUT");end
endmodule
'''


def main():
    static=full_extent_check()
    out=ROOT/'verification'/('tile_order_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir(parents=True);print('TILE_ORDER_RUN '+str(out),flush=True)
    files=[CANDIDATE/'sources'/n for n in ['frame_processor_stream.v','ddr_result_writer_burst64.v']]
    hashes={str(p):sha(p) for p in files};snapshot=out/'source_snapshot';snapshot.mkdir()
    for p in files:shutil.copyfile(p,snapshot/p.name)
    test=out/'tb_tile_order.sv';test.write_text(BENCH)
    checker=out/'checker_snapshot.py';shutil.copyfile(Path(__file__),checker)
    ini=out/'modelsim.ini';shutil.copyfile(TOOLS.parent/'modelsim.ini',ini)
    inputs={'source_sha256':hashes,'testbench_sha256':sha(test),'checker_sha256':sha(checker),
            'static_full_frame':static,'scope':__doc__,'hardware_accessed':False,
            'throughput_or_optical_acceptance':False}
    (out/'inputs.json').write_text(json.dumps(inputs,indent=2))
    def run(argv,name):
        with (out/name).open('w') as log:
            r=subprocess.run([p.as_posix() if isinstance(p,Path) else str(p) for p in argv],cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        if r.returncode:raise RuntimeError(str(out/name))
    run([TOOLS/'vlib.exe',out/'work'],'library.log')
    run([TOOLS/'vmap.exe','-modelsimini',ini,'work',out/'work'],'mapping.log')
    run([TOOLS/'vlog.exe','-sv','-modelsimini',ini,*[snapshot/p.name for p in files],test],'compile.log')
    script=out/'run.do';script.write_text('onerror {quit -code 2 -f}\nonbreak {resume}\nonfinish stop\nrun -all\nquit -f\n')
    try:run([TOOLS/'vsim.exe','-modelsimini',ini,'-c','work.tb_tile_order','-do',script],'simulation.log')
    except RuntimeError:pass
    log=(out/'simulation.log').read_text(errors='replace')
    passed='TILE_ORDER_RTL_PASS' in log and not re.search(r'\*\* (?:Fatal|Error|Warning)(?:\s|:)',log)
    assert all(sha(p)==hashes[str(p)] for p in files),'RTL changed during the check'
    result={'passed':passed,'hardware_accessed':False,'throughput_or_optical_acceptance':False,
            'scope':__doc__,'input_manifest_sha256':sha(out/'inputs.json'),
            'compile_log_sha256':sha(out/'compile.log'),'simulation_log_sha256':sha(out/'simulation.log'),
            'observations':[x for x in log.splitlines() if '_PASS' in x or '** Fatal' in x or '** Error' in x or '** Warning' in x]}
    (out/'verification.json').write_text(json.dumps(result,indent=2))
    print(json.dumps({'directory':str(out),**result},indent=2),flush=True)
    return 0 if passed else 1


if __name__=='__main__':sys.exit(main())
