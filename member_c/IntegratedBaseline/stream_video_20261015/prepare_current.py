"""Generate current high-resolution continuous candidate from repository sources.

Every stage uses a fresh immutable directory. This does not compile, program,
replace main-C, or declare timing/hardware acceptance.
"""
from pathlib import Path
import argparse,subprocess,sys
HERE=Path(__file__).resolve().parent
def prepare(out):
 stages=[out.with_name(out.name+'_base_continuous'),out.with_name(out.name+'_base_display'),out.with_name(out.name+'_base_turnaround'),out]
 assert all(not p.exists() for p in stages), 'All output/staging directories must be fresh'
 commands=[
  [HERE/'continuous_integration/prepare_board.py','--output',stages[0]],
  [HERE/'display_block/prepare_candidate.py','--baseline',stages[0],'--output',stages[1],'--fair'],
  [HERE/'turnaround/prepare_candidate.py','--baseline',stages[1],'--output',stages[2]],
  [HERE/'clock57/prepare_candidate.py','--baseline',stages[2],'--output',stages[3]],
 ]
 for argv in commands:subprocess.run([sys.executable,*map(str,argv)],check=True)
 print('CURRENT_CANDIDATE_READY; timing and hardware acceptance remain false')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=Path);a=p.parse_args();prepare(a.output.resolve())
