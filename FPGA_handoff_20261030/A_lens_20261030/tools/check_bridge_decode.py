"""Original/new request bridge equivalence, malformed guards and exact division."""
from pathlib import Path
import datetime,hashlib,json,random,re,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'candidate_host_angle_v3_cache64';OLD=ROOT/'candidate_host_angle_v2_product_stage'
TOOLS=Path('C:/modeltech64_2020.4/win64')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def pack(fields):
    n=0
    for v,w in fields:n=(n<<w)|(int(v)&((1<<w)-1))
    return n

def vectors(width,height,out_width,out_height,count):
    rng=random.Random(20261030+width);inputs=[];gold=[]
    for i in range(count):
        x=rng.randrange(width);y=rng.randrange(height);a00=y*width+x;nn=rng.randrange(2);inside=1
        nx=min(x+1,width-1) if not nn else x;ny=min(y+1,height-1) if not nn else y
        addresses=[a00,y*width+nx,ny*width+x,ny*width+nx]
        tag=(rng.randrange(out_height)<<12)|rng.randrange(out_width)
        if i>=400:
            if i%7==0:addresses[0]=rng.getrandbits(24)
            if i%7==1:addresses[2]^=1
            if i%7==2:tag|=0xfff000
            if i%7==3:inside=0;addresses=[rng.getrandbits(24) for _ in range(4)]
            if i%7==4:addresses[0]=[width*height,(1<<21),(1<<23),0xffffff][(i//7)%4]
        base=0 if i%2 else 0x800000;generation=rng.getrandbits(32);fx=rng.randrange(256);fy=rng.randrange(256)
        inputs.append(pack([(base,28),(generation,32),*[(a,24) for a in addresses],(tag,24),(fx,8),(fy,8),(inside,1),(nn,1)]))
        sx=addresses[0]%width;sy=addresses[0]//width
        ex=min(sx+1,width-1) if not nn else sx;ey=min(sy+1,height-1) if not nn and sy<height-1 else sy
        bad_tag=(tag&4095)>=out_width or (tag>>12)>=out_height
        bad_addr=inside and (addresses[0]>=width*height or addresses[1]!=sy*width+ex or addresses[2]!=ey*width+sx or addresses[3]!=ey*width+ex)
        ok=inside and not bad_tag and not bad_addr
        gold.append(pack([(base,28),(generation,32),(sx if ok else 0,12),(sy if ok else 0,12),(nn,1),(ok,1),(tag,24),(fx,8),(fy,8)]))
    return inputs,gold

BENCH=r'''`timescale 1ns/1ps
module bridge_lane #(parameter REF=0,W=1920,H=1080,OW=1920,OH=1080,N=5000)(
 input wire proc_clk,ui_clk,rst_n,output reg[31:0]sent=0,received=0,output wire fault);
 reg[197:0]vectors[0:N-1];reg[125:0]expected[0:N-1];integer ptick=0,utick=0,qstalls=0,rstalls=0;
 wire q_valid=rst_n&&sent<N&&ptick%9>=2,q_ready;
 wire[27:0]q_base;wire[31:0]q_generation;wire[23:0]q_addr00,q_addr10,q_addr01,q_addr11,q_tag;wire[7:0]q_fx,q_fy;wire q_inside,q_nearest;
 assign {q_base,q_generation,q_addr00,q_addr10,q_addr01,q_addr11,q_tag,q_fx,q_fy,q_inside,q_nearest}=vectors[sent];
 wire req_valid,req_ready=rst_n&&utick%37>=20;wire[27:0]req_base;wire[31:0]req_generation;wire[11:0]req_x,req_y;
 wire req_nearest,req_inside;wire[23:0]req_tag;wire[7:0]req_fx,req_fy;
 wire[125:0]actual={req_base,req_generation,req_x,req_y,req_nearest,req_inside,req_tag,req_fx,req_fy};
 wire rsp_ready,r_valid,r_inside;wire[23:0]r_p00,r_p10,r_p01,r_p11,r_tag;wire[7:0]r_fx,r_fy;wire[31:0]r_generation;
 generate if(REF)begin: reference
 quad_packet_bridge_reference #(.SRC_W(W),.SRC_H(H),.OUT_W(OW),.OUT_H(OH),.FIFO_ADDR_BITS(3)) dut(
 @PORTS@
 );
 end else begin: candidate
 quad_packet_bridge #(.SRC_W(W),.SRC_H(H),.OUT_W(OW),.OUT_H(OH),.FIFO_ADDR_BITS(3)) dut(
 @PORTS@
 );end endgenerate
 always @(posedge proc_clk)begin
  ptick<=ptick+1;
  if(!rst_n)sent<=0;
  else if(q_valid&&q_ready)sent<=sent+1;
  else if(q_valid&&!q_ready)qstalls++;
 end
 reg held=0;reg[125:0]held_payload;
 always @(posedge ui_clk)begin
  utick<=utick+1;
  if(!rst_n)begin received<=0;held<=0;end
  else begin
   if(held&&(!req_valid||actual!==held_payload))$fatal(1,"BRIDGE_UNSTABLE ref=%0d W=%0d",REF,W);
   held<=req_valid&&!req_ready;held_payload<=actual;
   if(req_valid&&!req_ready)rstalls++;
   if(req_valid&&req_ready)begin
    if(received>=N||actual!==expected[received])$fatal(1,"BRIDGE_PACKET_MISMATCH ref=%0d W=%0d index=%0d actual=%h expected=%h",REF,W,received,actual,expected[received]);
    received<=received+1;
   end
  end
 end
 initial begin
  if(W==1920)begin $readmemh("large_input.hex",vectors);$readmemh("large_expected.hex",expected);end
  else begin $readmemh("small_input.hex",vectors);$readmemh("small_expected.hex",expected);end
 end
endmodule
module bridge_case #(parameter W=1920,H=1080,OW=1920,OH=1080)(output reg finished=0);
 reg proc_clk=0,ui_clk=0,rst_n=0;always #5.387205 proc_clk=~proc_clk;initial begin #1.733;forever #4 ui_clk=~ui_clk;end
 wire[31:0]a_sent,b_sent,a_received,b_received;wire a_fault,b_fault;
 bridge_lane #(.REF(0),.W(W),.H(H),.OW(OW),.OH(OH)) newer(proc_clk,ui_clk,rst_n,a_sent,a_received,a_fault);
 bridge_lane #(.REF(1),.W(W),.H(H),.OW(OW),.OH(OH)) original(proc_clk,ui_clk,rst_n,b_sent,b_received,b_fault);
 initial begin
  repeat(10)@(negedge proc_clk);rst_n=1;
  wait(a_sent>=300&&b_sent>=300);
  if(a_fault||b_fault)$fatal(1,"LEGAL_BRIDGE_PACKET_REJECTED W=%0d",W);
  @(negedge proc_clk);rst_n=0;repeat(20)@(negedge proc_clk);
  if(a_fault||b_fault)$fatal(1,"BRIDGE_FAULT_NOT_RESET");
  rst_n=1;wait(a_received==5000&&b_received==5000);repeat(200)@(negedge ui_clk);
  if(a_received!=5000||b_received!=5000||!a_fault||!b_fault||newer.qstalls==0||newer.rstalls==0)$fatal(1,"BRIDGE_COVERAGE W=%0d",W);
  $display("REQUEST_BRIDGE_PASS width=%0d packets_per_lane=5000 actual_and_original=2 legal_prefix=300 reset_cancel=1 malformed_tag_address=1 outside=1 qstalls=%0d rstalls=%0d",W,newer.qstalls,newer.rstalls);finished=1;
 end
endmodule
module tb_bridge;
 wire a,b;bridge_case large(a);bridge_case #(.W(128),.H(16),.OW(64),.OH(16)) fallback(b);
 initial begin wait(a&&b);$display("BRIDGE_DECODE_EQUIVALENCE_PASS");$finish;end
 initial begin #10000000;$fatal(1,"BRIDGE_TIMEOUT");end
endmodule
'''

def main():
    assert all((n*34953)>>19==n//15 for n in range(65536))
    out=ROOT/'verification'/('bridge_decode_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir();print('BRIDGE_DECODE '+str(out),flush=True)
    for name,dims in [('large',(1920,1080,1920,1080)),('small',(128,16,64,16))]:
        a,b=vectors(*dims,5000)
        (out/(name+'_input.hex')).write_text(''.join('%050x\n'%v for v in a))
        (out/(name+'_expected.hex')).write_text(''.join('%032x\n'%v for v in b))
    port_names=['proc_clk','ui_clk','rst_n','q_valid','q_ready','q_inside','q_nearest','q_addr00','q_addr10','q_addr01','q_addr11','q_tag','q_fx','q_fy','q_generation','q_base','fault',
                'req_valid','req_ready','req_base','req_generation','req_x','req_y','req_nearest','req_inside','req_tag','req_fx','req_fy','rsp_ready','r_valid','r_inside','r_p00','r_p10','r_p01','r_p11','r_tag','r_fx','r_fy','r_generation']
    ports=','.join('.'+n+'('+n+')' for n in port_names)+",.rsp_valid(1'b0),.rsp_inside(1'b0),.rsp_p00(24'd0),.rsp_p10(24'd0),.rsp_p01(24'd0),.rsp_p11(24'd0),.rsp_tag(24'd0),.rsp_fx(8'd0),.rsp_fy(8'd0),.rsp_generation(32'd0),.r_ready(1'b1)"
    test=out/'tb_bridge.sv';test.write_text(BENCH.replace('@PORTS@',ports))
    old=OLD/'sources/quad_packet_bridge.v';reference=out/'quad_packet_bridge_reference.v';reference.write_text(old.read_text().replace('module quad_packet_bridge #(','module quad_packet_bridge_reference #(',1))
    excluded={'ddr3_ip.v','ddr3_ip_ddrphy_top.v','ddr3_ip_slice_top_v1_10.v','config_pll_27m_10m.v','video_pll_27m_148m5.v'}
    files=sorted(p for p in (R/'sources').glob('*.v') if p.name not in excluded)
    needed=['quad_packet_bridge.v','async_packet_stream.v','async_packet_fifo.v']
    inputs={'source_sha256':{str(R/'sources'/n):sha(R/'sources'/n) for n in needed},'reference_sha256':sha(old),'generated_reference_sha256':sha(reference),
            'testbench_sha256':sha(test),'checker_sha256':sha(Path(__file__)),'division_domain_exhaustive_n':65536,'hardware_accessed':False,
            'fixtures':{p.name:sha(p) for p in out.glob('*.hex')}}
    (out/'inputs.json').write_text(json.dumps(inputs,indent=2));ini=out/'modelsim.ini';shutil.copyfile(TOOLS.parent/'modelsim.ini',ini)
    def run(argv,name):
        with (out/name).open('w') as log:r=subprocess.run([p.as_posix() if isinstance(p,Path) else str(p) for p in argv],cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        if r.returncode:raise RuntimeError(str(out/name))
    run([TOOLS/'vlib.exe',out/'work'],'library.log');run([TOOLS/'vmap.exe','-modelsimini',ini,'work',out/'work'],'mapping.log')
    run([TOOLS/'vlog.exe','-sv','-modelsimini',ini,*files,reference,test],'compile.log')
    do=out/'run.do';do.write_text('onerror {quit -code 2 -f}\nonbreak {resume}\nonfinish stop\nrun -all\nquit -f\n')
    try:run([TOOLS/'vsim.exe','-c','-modelsimini',ini,'work.tb_bridge','-do',do],'simulation.log')
    except RuntimeError:pass
    log=(out/'simulation.log').read_text(errors='replace');compiled=(out/'compile.log').read_text(errors='replace')
    passed='BRIDGE_DECODE_EQUIVALENCE_PASS' in log and not re.search(r'\*\* (?:Warning|Fatal|Error)(?:\s|:)',log+compiled)
    assert all(sha(p)==h for p,h in inputs['source_sha256'].items())
    result={'passed':passed,'hardware_accessed':False,'scope':__doc__,'inputs_sha256':sha(out/'inputs.json'),'simulation_log_sha256':sha(out/'simulation.log'),'compile_log_sha256':sha(out/'compile.log'),
            'observations':[v for v in log.splitlines() if '_PASS' in v or '** Fatal' in v or '** Error' in v or '** Warning' in v]}
    (out/'verification.json').write_text(json.dumps(result,indent=2));print(json.dumps({'directory':str(out),**result},indent=2));raise SystemExit(0 if passed else 1)

if __name__=='__main__':main()
