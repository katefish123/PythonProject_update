"""Check frozen-dependency generation against the accepted build inputs."""
import argparse
import hashlib
import json
from pathlib import Path
from package_merged import PRODUCTION


def main():
    p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--replica',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    baseline,replica=a.baseline.resolve(),a.replica.resolve()
    names=list(PRODUCTION)
    names+=['rtl/algo/marker_detector.v']+['vendor/b/rtl/'+n for n in ['b_rectifier.v','bilinear_interp.v','homography_solver.v','perspective_coord.v','perspective_core.v','scaled_div_pipe.v','signed_div_seq.v','unsigned_div_seq.v']]
    names+=sorted(p.relative_to(baseline).as_posix() for p in (baseline/'fullhd_tests').rglob('*.hex'))
    files={}
    for name in names:
        left,right=baseline/name,replica/name
        assert left.read_bytes()==right.read_bytes(),name
        files[name]=hashlib.sha256(left.read_bytes()).hexdigest()
    normalized=[]
    for src in (baseline/'fullhd_tests').glob('*.sv'):
        other=replica/'fullhd_tests'/src.name
        left=src.read_text().replace(baseline.as_posix(),'@OUTPUT@')
        right=other.read_text().replace(replica.as_posix(),'@OUTPUT@')
        assert left==right,src.name
        normalized.append(src.name)
    a.output.write_text(json.dumps(dict(passed=True,baseline=str(baseline),replica=str(replica),
        production_files=len(PRODUCTION),original_b_files=9,files_exact_sha256=files,
        test_sources_equal_after_output_path_relocation=normalized,
        scope='source_and_fixture_reproduction_only_not_new_simulation_or_hardware_acceptance'),indent=2)+'\n')
    print('FROZEN_DEPENDENCY_REPRODUCTION_PASS production='+str(len(PRODUCTION))+' B=9 exact_files='+str(len(files))+' relocated_tests='+str(len(normalized)))


if __name__=='__main__':main()
