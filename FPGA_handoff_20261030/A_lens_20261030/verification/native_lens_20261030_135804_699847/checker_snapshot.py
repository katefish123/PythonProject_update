"""Check actual full-board synthesized lens cells against B's exact integer model.

Only the lens leaf is isolated. Its parent-factored input-bit inversions are
reproduced exactly. The parent-trimmed unused destination-tag bit11 is excluded.
"""
from pathlib import Path
import argparse,datetime,hashlib,json,random,re,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
TOOLS=Path('C:/modeltech64_2020.4/win64')
MODELS=Path('C:/pango/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
sys.path.insert(0,'C:/D/FPGA/A_software_20261024/deps')
sys.path.insert(0,'C:/D/FPGA/A_software_20261024/reference/B_lens_v2/python')
from brect.calibration import load_calibration
from brect.lens import _map_hardware
from send_lens_angle import hardware_binding
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--netlist',type=Path,required=True);ap.add_argument('--calibration',type=Path,default=ROOT/'calibration/r50_18mm_hdmi_trial.json');a=ap.parse_args()
    net=a.netlist.resolve();candidate=net.parents[3]
    assert hardware_binding(a.calibration,candidate,[1920,1080])['compatible']
    original_sha=sha(net);text=net.read_text();modules={m[1]:m[0] for m in re.finditer(r'(?m)^module\s+(\w+)\b.*?^endmodule',text,re.S|re.M)}
    lens=modules['lens_distort_coord'];algorithm=modules['lens_affine_instance'];processor=modules['frame_processor_stream']
    instance=re.search(r'(?m)^    lens_distort_coord\s+lens\s*\(.*?\);',algorithm,re.S).group()
    bindings={m[1].strip():m[2].strip() for m in re.finditer(r'\.(\\\S+|\w+)\s*\(([^)]*)\)',instance)}
    header=lens[:lens.index(');')+2]
    ports=[]
    for line in header.splitlines():
        if line.strip().startswith('input '):ports.append(re.sub(r'^input\s+(?:\[[^]]+\]\s+)?','',line.strip()).rstrip(',').strip())
    standard={'clk','in_valid','in_tag','in_x','in_y'}
    extra=set(ports)-standard
    nx=next(p for p in extra if p.endswith('/nx'));ny=next(p for p in extra if p.endswith('/ny'))
    ix=next(p for p in extra if 'N120[7]_inv' in p);iy=next(p for p in extra if 'N122[0]_inv' in p)
    reset_ports=extra-{nx,ny,ix,iy};assert len(reset_ports)==1;reset=next(iter(reset_ports))
    # These are actual parent LUT equations, not arbitrary values tied to zero.
    assert '// LUT = (~I1)|(~I0) ;' in algorithm and '// Z5 = (~I2)|(~I0) ;' in algorithm
    cell=re.search(r'(?m)^    GTP_LUT6D /\* N120_inv \*/.*?\);',algorithm,re.S).group()
    assert '.I0 (affine_valid)' in cell and '.I1 (nx[23])' in cell and '.I2 (ny[16])' in cell and '.Z (\\N120[7]_inv )' in cell and '.Z5 (\\N122[0]_inv )' in cell
    algorithm_instance=re.search(r'(?m)^    lens_affine_instance\s+.*?\);',processor,re.S).group()
    algorithm_bindings={m[1].strip():m[2].strip() for m in re.finditer(r'\.(\\\S+|\w+)\s*\(([^)]*)\)',algorithm_instance)}
    reset_parent=algorithm_bindings[bindings[reset]]
    reset_cell=next(c for c in re.findall(r'(?m)^    GTP_LUT3 .*?\);',processor,re.S) if re.search(r'\.Z\s*\('+re.escape(reset_parent)+r'\)',c))
    assert ".INIT(8'b11111110)" in reset_cell and '.I0 (abort)' in reset_cell and '.I2 (state_reg[0])' in reset_cell
    # The header/parent explicitly omit the unused tag bit11 for this1920-wide build.
    assert 'in_tag' in bindings and "1'bx" in bindings['in_tag']
    assert re.search(r'out_tag.*?\\lens_out_tag\[11\]_floating',instance,re.S)
    out=ROOT/'verification'/('native_lens_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir();print('NATIVE_LENS '+str(out),flush=True)
    selected=set();todo=['lens_distort_coord'];prims={'GTP_GRS','GTP_MUX2LUT6','INT_LUTMUX2_UDP','INT_LUTMUX4_UDP'}
    while todo:
        name=todo.pop()
        if name in selected:continue
        selected.add(name);prims.update(re.findall(r'\bGTP_\w+\b',modules[name]))
        for child in re.findall(r'(?m)^    (\w+)\s+(?:/\*.*?\*/\s*)?(?:#\s*\(|(?:\\\S+|\w+)\s*\()',modules[name]):
            if child in modules:todo.append(child)
    extracted=out/'actual_lens.vm';extracted.write_text('\n\n'.join(modules[n] for n in sorted(selected)))
    hw=load_calibration(a.calibration,(1920,1080)).to_hardware();rng=random.Random(20261030)
    points=[(x*256+f,y*256+g) for x in [0,1,959,1918,1919] for y in [0,1,539,1078,1079] for f,g in [(0,0),(1,255),(127,128)]]
    points += [(rng.randrange(1<<20),rng.randrange(1<<20)) for _ in range(3000)]
    points += [(rng.randrange(1920*256),rng.randrange(1080*256)) for _ in range(1000)]
    inputs=[];expected=[]
    for u,v in points:
        tag=(rng.getrandbits(26)&~(1<<11))|(1<<24)
        sx,sy,ok=_map_hardware(hw,u,v)
        if not ok:sx=sy=0
        inputs.append((u<<46)|(v<<26)|tag)
        expected.append((int(not ok)<<106)|(tag<<80)|((sx&((1<<40)-1))<<40)|(sy&((1<<40)-1)))
    (out/'input.hex').write_text(''.join('%017x\n'%v for v in inputs));(out/'expected.hex').write_text(''.join('%027x\n'%v for v in expected))
    wrapper='\n'.join([' .'+p+' ('+value+'),' for p,value in [(nx,'nx'),(ny,'ny'),(ix,'~in_x[7]'),(iy,'~in_y[0]'),(reset,'~rst_n')]])
    bench=r'''`timescale 1ns/1ps
module tb_native_lens;
 localparam N=@N@;reg clk=0,rst_n=0,in_valid=0;always #5.387205 clk=~clk;
 reg[19:0]in_x=0,in_y=0;reg[25:0]in_tag=0;wire[63:0]nx={28'd0,in_x,16'd0},ny={28'd0,in_y,16'd0};
 wire out_valid,out_error;wire[25:0]out_tag;wire[39:0]out_x,out_y;
 GTP_GRS GRS_INST(.GRS_N(rst_n));
 lens_distort_coord dut(
 @WRAPPER@
 .clk(clk),.in_valid(in_valid),.in_x(in_x),.in_y(in_y),.in_tag(in_tag),.out_valid(out_valid),.out_error(out_error),.out_x(out_x),.out_y(out_y),.out_tag(out_tag));
 reg[65:0]vectors[0:N-1];reg[106:0]gold[0:N-1];integer queue[$];integer index=0,sent=0,received=0,cancelled=0,errors=0,bubbles=0;
 integer ignored,k;reg[31:0]rng=32'hae1863db;
 always @(posedge clk)begin
  if(!rst_n)begin cancelled=cancelled+queue.size();queue.delete();end
  else begin
   if(in_valid)begin queue.push_back(index);sent++;end else bubbles++;
   if(out_valid)begin
    if(queue.size()==0)$fatal(1,"NATIVE_UNEXPECTED_OUTPUT");k=queue.pop_front();
    if(out_error!==gold[k][106]||out_x!==gold[k][79:40]||out_y!==gold[k][39:0]||(((out_tag^gold[k][105:80])&26'h3fff7ff)!==0))
     $fatal(1,"NATIVE_LENS_MISMATCH index=%0d actual=%b/%h/%h expected=%h",k,out_error,out_x,out_y,gold[k]);
    received++;if(out_error)errors++;
   end
  end
 end
 initial begin
  $readmemh("input.hex",vectors);$readmemh("expected.hex",gold);
  repeat(8)@(negedge clk);rst_n=1;
  for(integer j=0;j<N;j++)begin
   @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   in_valid=1;index=j;{in_x,in_y,in_tag}=vectors[j];
   if(j==500||j==2000)begin @(negedge clk);in_valid=0;rst_n=0;repeat(5)@(negedge clk);rst_n=1;end
   else if(rng[2:0]==0)begin @(negedge clk);in_valid=0;repeat(3)@(negedge clk);end
  end
  @(negedge clk);in_valid=0;repeat(60)@(negedge clk);
  if(sent!=N||received+cancelled!=N||errors<10||bubbles<10||cancelled==0)$fatal(1,"NATIVE_COVERAGE");
  $display("NATIVE_LENS_PASS points=%0d checked=%0d numerical_errors=%0d cancelled=%0d bubbles=%0d consumed_tag_bits=25 ignored_trimmed_tag_bit=11",N,received,errors,cancelled,bubbles);$finish;
 end
 initial begin #2000000;$fatal(1,"NATIVE_LENS_TIMEOUT");end
endmodule
'''.replace('@N@',str(len(points))).replace('@WRAPPER@',wrapper)
    test=out/'tb_native_lens.sv';test.write_text(bench);shutil.copyfile(Path(__file__),out/'checker_snapshot.py')
    record={'scope':__doc__,'full_netlist':str(net),'full_netlist_sha256':original_sha,'candidate':str(candidate),
            'source_sha256':json.loads((candidate/'project/source_manifest.json').read_text())['source_sha256'],
            'extracted_sha256':sha(extracted),'modules':sorted(selected),'primitive_sha256':{n:sha(MODELS/(n+'.v')) for n in sorted(prims)},
            'parent_inversion_cell':cell,'parent_reset_cell':reset_cell,'parent_instance':instance,
            'vectors_sha256':{str(out/n):sha(out/n) for n in ['input.hex','expected.hex']},'bench_sha256':sha(test),'checker_sha256':sha(Path(__file__))}
    (out/'inputs.json').write_text(json.dumps(record,indent=2));ini=out/'modelsim.ini';shutil.copyfile(TOOLS.parent/'modelsim.ini',ini)
    def run(argv,name):
        with (out/name).open('w') as log:r=subprocess.run([p.as_posix() if isinstance(p,Path) else str(p) for p in argv],cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        if r.returncode:raise RuntimeError(str(out/name))
    run([TOOLS/'vlib.exe',out/'work'],'library.log');run([TOOLS/'vmap.exe','-modelsimini',ini,'work',out/'work'],'mapping.log')
    run([TOOLS/'vlog.exe','-sv','-modelsimini',ini,*[MODELS/(n+'.v') for n in sorted(prims)],extracted,test],'compile.log')
    do=out/'run.do';do.write_text('onerror {quit -code 2 -f}\nonbreak {resume}\nonfinish stop\nrun -all\nquit -f\n')
    try:run([TOOLS/'vsim.exe','-c','-modelsimini',ini,'work.tb_native_lens','-do',do],'simulation.log')
    except RuntimeError:pass
    log=(out/'simulation.log').read_text(errors='replace');passed='NATIVE_LENS_PASS' in log and not re.search(r'\*\* (?:Warning|Fatal|Error)(?:\s|:)',log)
    assert sha(net)==original_sha
    result={'passed':passed,'hardware_accessed':False,'scope':__doc__,'inputs_sha256':sha(out/'inputs.json'),'simulation_log_sha256':sha(out/'simulation.log'),
            'observations':[v for v in log.splitlines() if '_PASS' in v or '** Fatal' in v or '** Warning' in v or '** Error' in v]}
    (out/'verification.json').write_text(json.dumps(result,indent=2));print(json.dumps({'directory':str(out),**result},indent=2));raise SystemExit(0 if passed else 1)

if __name__=='__main__':main()
