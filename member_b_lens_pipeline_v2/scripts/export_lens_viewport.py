"""Export one exhaustively verified crop/H/calibration binding for the FPGA."""
import argparse
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'python'))
from brect.calibration import load_calibration
from brect.viewport import plan_viewport, read_homography


def export(calibration, output_prefix, H=None, output_size=None):
    profile=load_calibration(calibration)
    effective,framing=plan_viewport(profile,H=H,output_size=output_size)
    hardware=profile.to_hardware();width,height=framing['output_size']
    header=['// Generated binding: calibration + base H + crop + exact fixed H.',
            '// Re-export when any bound geometry changes; metadata retains trial status.',
            '`ifndef BRECT_SAFE_VIEWPORT_VH','`define BRECT_SAFE_VIEWPORT_VH',
            f'`define SAFE_SRC_W {profile.width}',f'`define SAFE_SRC_H {profile.height}',
            f'`define SAFE_DST_W {width}',f'`define SAFE_DST_H {height}']
    for key,value in hardware.items():header.append(f"`define SAFE_{key} 32'sh{value & 0xffffffff:08x}")
    for index,value in enumerate(framing['H_q24']):
        header.append(f"`define SAFE_H{index//3}{index%3}_Q24 40'sh{value & ((1<<40)-1):010x}")
    header+=['`endif','']
    document={'source_profile_name':Path(calibration).name,'hardware_parameters':hardware,
              'H_q24':framing['H_q24'],'effective_H':effective.tolist(),'framing':framing,
              'calibration_metadata':profile.metadata,
              'deployment_note':'This is a compile-time geometry binding, not optical accuracy or board validation.'}
    prefix=Path(output_prefix);prefix.parent.mkdir(parents=True,exist_ok=True)
    Path(str(prefix)+'.vh').write_text('\n'.join(header),encoding='utf-8')
    Path(str(prefix)+'.json').write_text(json.dumps(document,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    return document


def main():
    parser=argparse.ArgumentParser(description='Verified black-border-free crop and FPGA constants')
    parser.add_argument('--calibration',required=True)
    parser.add_argument('--output-prefix',required=True)
    parser.add_argument('--H',help='Destination-to-ideal-source H JSON, default identity')
    parser.add_argument('--size',nargs=2,type=int)
    args=parser.parse_args()
    try:
        result=export(args.calibration,args.output_prefix,H=read_homography(args.H),output_size=args.size)
    except (ValueError,TypeError,OSError) as error:parser.exit(2,f'export_lens_viewport: {error}\n')
    print(json.dumps({'output_prefix':args.output_prefix,'zoom':result['framing']['zoom'],
                      'before':result['framing']['before'],'after':result['framing']['after']},indent=2))


if __name__=='__main__':main()
