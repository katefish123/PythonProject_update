"""Chessboard line-deviation diagnostic, not a calibration/MTF acceptance."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np

def measure_grid(points):
    p=np.asarray(points,dtype=np.float64)
    if p.ndim!=3 or p.shape[2]!=2 or min(p.shape[:2])<3 or not np.isfinite(p).all():raise ValueError('Invalid corner grid')
    diagonal=float(np.linalg.norm(np.ptp(p.reshape(-1,2),axis=0)))
    row=p[0,-1]-p[0,0];col=p[-1,0]-p[0,0]
    area=abs(row[0]*col[1]-row[1]*col[0])
    if diagonal<1e-9 or area<diagonal**2*1e-9:raise ValueError('Collapsed board')
    def fit(line):
        centered=line-line.mean(axis=0)
        _,_,v=np.linalg.svd(centered,full_matrices=False)
        distances=centered@v[-1]
        return {'rms_px':float(np.sqrt(np.mean(distances**2))),'max_abs_px':float(np.max(np.abs(distances)))}
    rows=[fit(line) for line in p]
    columns=[fit(line) for line in p.transpose(1,0,2)]
    worst=max(r['rms_px'] for r in rows+columns)
    return {'rows':rows,'columns':columns,'worst_line_rms_px':worst,
            'board_bounding_diagonal_px':diagonal,
            'normalized_worst_line_rms':worst/diagonal,
            'method':'Orthogonal least-squares line per corner row/column; normalize by detected board bounding diagonal.'}

def main():
    import cv2
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw',type=Path,required=True)
    parser.add_argument('--corrected',type=Path,required=True)
    parser.add_argument('--columns',type=int,default=9)
    parser.add_argument('--rows',type=int,default=6)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():parser.error('Preserve existing report; choose a fresh output')
    report={'hardware_acceptance':False,'optical_acceptance':False,'MTF_or_SFR':None,
            'pairing_and_independent_capture_provenance':'not_verified',
            'scope':'Detected chessboard geometry diagnostic only; not MTF, focus, independent calibration or board acceptance.',
            'numpy_version':np.__version__,'opencv_version':cv2.__version__}
    for label,path in [('raw',args.raw),('corrected',args.corrected)]:
        im=cv2.imread(str(path),cv2.IMREAD_COLOR)
        if im is None or im.shape[:2]!=(1080,1920):raise ValueError('Expected native1920x1080 '+str(path))
        ok,corners=cv2.findChessboardCornersSB(cv2.cvtColor(im,cv2.COLOR_BGR2GRAY),(args.columns,args.rows),flags=cv2.CALIB_CB_NORMALIZE_IMAGE)
        if not ok:raise ValueError('Complete chessboard not detected: '+str(path))
        points=corners.reshape(args.rows,args.columns,2)
        report[label]={'file':str(path.resolve()),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'corners':points.tolist(),'geometry':measure_grid(points)}
    report['analyzer_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k]['geometry'] for k in ['raw','corrected']},indent=2))

if __name__=='__main__':main()
