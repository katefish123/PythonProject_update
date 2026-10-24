"""Full native RAW with shared capture/display arbitration and bounded service stalls."""
from pathlib import Path
import argparse,hashlib,json,shutil

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--long-every',type=int,default=128);a=p.parse_args()
    assert a.long_every>0
    base=Path('D:/FPGA/output/b_lens_release2_frontsync_20261023')
    a.output.mkdir(parents=True,exist_ok=False);shutil.copytree(base/'source_snapshot',a.output/'source_snapshot')
    tb=a.output/'source_snapshot/tb_lens_board.sv';text=tb.read_text()
    text=text.replace('integer ui_tick=0,','integer write_delay=0,aw_commands=0;\n integer ui_tick=0,')
    text=text.replace('wready=rst_n&&(ui_tick%11!=0)','wready=rst_n&&write_pending&&write_delay==0&&(ui_tick%11!=0)')
    text=text.replace('if(awvalid&&awready)begin\n if(write_pending)',f'if(write_delay>0)write_delay<=write_delay-1;\n if(awvalid&&awready)begin\n write_delay<=aw_commands%{a.long_every}=={a.long_every-1}?322:4;aw_commands<=aw_commands+1;\n if(write_pending)')
    text=text.replace('read_delay<=28+((reads%128==127)?100:0)',f'read_delay<=reads%{a.long_every}=={a.long_every-1}?332:28')
    assert 'aw_commands<=' in text and 'CORRECTED=1' in text
    tb.write_text(text)
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    files={p.name:sha(p) for p in (a.output/'source_snapshot').iterdir() if p.name!='tb_lens_board.sv'}
    (a.output/'binding.json').write_text(json.dumps({'width':1920,'height':1080,'mode':'RAW','profile_long_every':a.long_every,
        'first_write_cycles':{'normal':4,'long':322},'first_read_cycles':{'normal':28,'long':332},
        'scope':'Sensitivity model using observed maxima, frequency hypothetical; not measured physical service distribution',
        'production_sha256':files,'original_test_sha256':sha(base/'source_snapshot/tb_lens_board.sv'),'testbench_sha256':sha(tb)},indent=2)+'\n')
    run=(base/'run.ps1').read_text().replace('work.tb_raw_pipeline','-gCORRECTED=0 work.tb_raw_pipeline')
    (a.output/'run.ps1').write_text(run)
    print(a.output)
