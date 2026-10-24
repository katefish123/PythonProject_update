"""Reproduce duplicated status ROM precedence; only fresh offline test outputs."""
from pathlib import Path
import argparse,hashlib,json,re,shutil

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    text=a.source.read_text();rows=re.findall(r"9'h([0-9a-f]+): bits=160'h([0-9a-f]+);",text)
    expected={int(k,16):v for k,v in rows} # intended final replacement labels
    checks=[]
    for code in [12,13,15,28,29]:
        for y in range(16):
            key=code*16+y
            checks.append(f"force dut.shown=5'd{code}; y=12'd{y*4}; #1; if(dut.bits!==160'h{expected[key]}) $fatal(1,\"WRONG_STATUS_GLYPH code={code} row={y}\");")
    tb='''`timescale 1ns/1ps
module tb;
reg clk=0,rst_n=0,scan_de=0,scan_start=0; reg[11:0]x=0,y=0; reg[4:0]status=0;wire on;wire[23:0]rgb;
always #5 clk=~clk;
status_overlay dut(.*);
initial begin
'''+ '\n'.join(checks)+'''
$display("PASS STATUS_ROM all 80 replacement glyph rows selected");$finish;
end
endmodule
'''
    shutil.copyfile(a.source,a.output/'status_overlay.v');(a.output/'tb.sv').write_text(tb)
    (a.output/'binding.json').write_text(json.dumps({'original':str(a.source),'original_sha256':hashlib.sha256(a.source.read_bytes()).hexdigest(),
        'duplicate_addresses':sorted({k for k,v in rows if sum(x==k for x,y in rows)>1}),
        'expected_replacement_rows':80},indent=2)+'\n')
    (a.output/'run.ps1').write_text("& D:/softwares/modelsim/win64/vlib.exe work *> library.log\n& D:/softwares/modelsim/win64/vlog.exe -sv status_overlay.v tb.sv *> compile.log\n& D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop;run -all;quit -f' work.tb *> simulation.log\nGet-Content simulation.log -Tail 9\n")
    print(a.output)

if __name__=='__main__':main()
