"""Still-image CLI and optional OpenCV live capture/display adapter."""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image
from .golden import detect_markers, rectify_float
from .fixed import rectify_fixed


def process(rgb, w, h, method, thresholds):
    points, stats = detect_markers(rgb, thresholds)
    if points is None:
        raise ValueError(f"Four valid markers not found: {stats}")
    fp,hf = rectify_float(rgb,points,w,h,method)
    fx,hq = rectify_fixed(rgb,points,w,h,method)
    return fp,fx,{"points_TL_TR_BR_BL":points.tolist(),"float_H":hf.tolist(),"fixed_H":hq,"statistics":stats}


def main():
    a = argparse.ArgumentParser(description="RGB四色标记纸面透视矫正")
    a.add_argument("input", nargs="?")
    a.add_argument("--size", nargs=2, type=int, default=[320,452], metavar=("W","H"))
    a.add_argument("--method", choices=["nearest","bilinear"],default="bilinear")
    a.add_argument("--thresholds", help="JSON: color -> [[Rmin,Gmin,Bmin],[Rmax,Gmax,Bmax]]")
    a.add_argument("--output",default="results/user")
    a.add_argument("--camera",type=int)
    a.add_argument("--update-every",type=int,default=5)
    args=a.parse_args()
    th=json.loads(Path(args.thresholds).read_text()) if args.thresholds else None
    w,h=args.size
    if args.camera is None:
        if not args.input:
            a.error("provide an image or --camera INDEX")
        rgb=np.array(Image.open(args.input).convert("RGB"))
        fp,fx,info=process(rgb,w,h,args.method,th)
        out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
        Image.fromarray(fp).save(out/"float.png")
        Image.fromarray(fx).save(out/"fixed.png")
        (out/"parameters.json").write_text(json.dumps(info,indent=2),encoding="utf-8")
        print(f"Saved {out}; corners={info['points_TL_TR_BR_BL']}")
        return
    if args.update_every < 1:
        a.error("--update-every must be positive")
    import cv2  # Only capture/display/color conversion; geometry is our model.
    cap=cv2.VideoCapture(args.camera); points=None; frame=0
    try:
        if not cap.isOpened():
            raise RuntimeError("Cannot open camera")
        while True:
            ok,bgr=cap.read()
            if not ok: break
            rgb=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
            if frame % args.update_every == 0:
                candidate,_=detect_markers(rgb,th)
                if candidate is not None:
                    try:
                        from .fixed import solve_fixed
                        solve_fixed(candidate,w,h,rgb.shape[1],rgb.shape[0])
                        points=candidate
                    except ValueError: pass
            # This scalar reference is for correctness, not PC video throughput.
            if points is not None:
                fx,_=rectify_fixed(rgb,points,w,h,args.method)
                cv2.imshow("B rectified (reference model)",cv2.cvtColor(fx,cv2.COLOR_RGB2BGR))
            cv2.imshow("Markers input",bgr);frame+=1
            if cv2.waitKey(1)&255 in (27,ord('q')): break
    finally:
        cap.release();cv2.destroyAllWindows()


if __name__ == "__main__": main()
