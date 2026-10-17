"""Reproducible RGB scene, scalar model vectors and independent float metrics."""
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"python"))
from brect.golden import homography,map_float,rectify_float,detect_markers
from brect.fixed import solve_fixed,map_fixed,rectify_fixed,sample_fixed,addresses,S,T


def make_scene(points,width=64,height=48):
    # Back-project a printable grid onto an oblique plane, no warpPerspective.
    h=homography(points,32,24);forward=np.linalg.inv(h)
    im=np.full((height,width,3),180,np.uint8)
    for y in range(height):
        for x in range(width):
            uvw=forward@np.array([x,y,1.])
            u,v=uvw[:2]/uvw[2]
            if 0<=u<=31 and 0<=v<=23:
                val=200 if (int(u)//4+int(v)//4)%2 else 245
                im[y,x]=[val,val,val]
                if abs(u-15.5)<.4 or abs(v-11.5)<.4:im[y,x]=[80,80,80]
    for x,y in points:
        im[y-2:y+3,x-2:x+3]=0
    return im


def write_rgb(path,image):
    path.write_text("".join(f"{int(r):02x}{int(g):02x}{int(b):02x}\n" for r,g,b in image.reshape(-1,3)))


def generate():
    (ROOT/"vectors").mkdir(exist_ok=True);(ROOT/"results").mkdir(exist_ok=True)
    p0=[(10,8),(52,13),(56,40),(7,38)]
    p1=[(14,7),(49,10),(54,37),(10,41)]
    src=[make_scene(p0),make_scene(p1)]
    src.append(src[1].copy());src[2][35:40,52:57]=180 # remove BR black marker
    for i,im in enumerate(src):
        write_rgb(ROOT/f"vectors/source{i}.hex",im);Image.fromarray(im).save(ROOT/f"examples/source{i}.png")
    h0=solve_fixed(p0,32,24,64,48);h1=solve_fixed(p1,32,24,64,48)
    outputs=[]
    metrics={}
    for i,(points,method) in enumerate([(p0,"bilinear"),(p1,"nearest")]):
        fp,_=rectify_float(src[i],points,32,24,method);fx,hq=rectify_fixed(src[i],points,32,24,method)
        write_rgb(ROOT/f"vectors/expected{i}.hex",fx);outputs.append(fx)
        Image.fromarray(fp).save(ROOT/f"examples/float{i}.png");Image.fromarray(fx).save(ROOT/f"examples/fixed{i}.png")
        diff=np.abs(fp.astype(int)-fx.astype(int));err=[]
        hf=homography(points,32,24)
        for y in range(24):
            for x in range(32):
                a,b,_=map_float(hf,x,y);qx,qy,v=map_fixed(hq,x,y)
                assert v;err.extend([abs(a-qx/T),abs(b-qy/T)])
        metrics[f"scene{i}"]={"points":points,"H_q":hq,"method":method,"coordinate_max_error_px":max(err),
                               "pixel_mae":float(diff.mean()),"pixel_max_error":int(diff.max())}
        found,_=detect_markers(src[i]);assert found is not None and np.array_equal(found,points)
    assert detect_markers(src[2])[0] is None
    # While a new H is pending, the current frame keeps its old H.
    for name,im,h,method in [("precommit",src[1],h0,"bilinear"),("hold",src[2],h1,"nearest")]:
        result=np.zeros((24,32,3),np.uint8)
        for y in range(24):
            for x in range(32):
                qx,qy,v=map_fixed(h,x,y)
                if v:result[y,x]=sample_fixed(im,qx,qy,method)
        write_rgb(ROOT/f"vectors/{name}.hex",result)
    for name,h,method,count,geometry in [("bootstrap",h0,"bilinear",16,False),("frame0",h0,"bilinear",768,True),
                       ("precommit",h0,"bilinear",8,True),("frame1",h1,"nearest",768,True),("hold",h1,"nearest",768,True)]:
        with (ROOT/f"vectors/{name}_req.txt").open("w") as f:
            for i in range(count):
                x,y=i%32,i//32;qx,qy,v=map_fixed(h,x,y)
                ok,a,fx,fy=addresses(qx,qy,64,48,method)
                if not geometry:ok=False;a=[0]*4;fx=fy=0
                f.write(f"{(y<<12)|x} {int(ok and v)} 0 "+" ".join(str(v) for v in a)+f" {fx} {fy}\n")
    # Coordinate cases: positive/negative coefficients, affine, real perspective,
    # corners, 4095 bound, denominator threshold, ratio overflow and bubbles.
    rng=np.random.default_rng(100676);coord=[]
    hs=[h0,h1,[S,0,0,0,S,0,0,0,S],[S,0,3*S,0,S,2*S,0,0,S]]
    for h in hs:
        for y in range(24):
            for x in range(32):coord.append((h,x,y))
    hd_points=[(203,114),(1697,183),(1802,974),(121,1002)]
    hd_q=solve_fixed(hd_points,1280,720,1920,1080);hd_f=homography(hd_points,1280,720)
    hd_errors=[]
    for y in range(0,720,29):
        for x in range(0,1280,41):
            coord.append((hd_q,x,y));a,b,_=map_float(hd_f,x,y);qx,qy,valid=map_fixed(hd_q,x,y)
            assert valid;hd_errors.extend([abs(a-qx/T),abs(b-qy/T)])
    metrics["hd_coordinates"]={"source_size":[1920,1080],"output_size":[1280,720],"samples":len(hd_errors)//2,
                               "coordinate_max_error_px":max(hd_errors),"H_q":hd_q}
    for _ in range(450):
        h=[int(v) for v in rng.integers(-5*S,5*S,9)]
        h[2]=int(rng.integers(-2*S,100*S));h[5]=int(rng.integers(-2*S,100*S));h[8]=int(rng.integers(-S,5*S))
        coord.append((h,int(rng.integers(4096)),int(rng.integers(4096))))
    for d in [0,-1,S//16,S//16+1,S]:
        coord.append(([S,0,0,0,S,0,0,0,d],0,0))
    coord.extend([([S,0,0,0,S,0,0,0,S],4095,4095),([S,0,4096*S,0,S,0,0,0,S],0,0)])
    with (ROOT/"vectors/coord.txt").open("w") as f:
        for tag,(h,x,y) in enumerate(coord):
            qx,qy,v=map_fixed(h,x,y);gap=1 if tag%17==0 else 0
            f.write(f"{gap} {x} {y} {tag} "+" ".join(f"{v&((1<<40)-1):010x}" for v in h)+f" {qx} {qy} {int(not v)}\n")
    # Standalone solver with different frame sizes, large integer corners,
    # negative cross terms, affine, bow-tie and extreme foreshortening.
    quads=[p0,p1,[(0,0),(4095,0),(4095,4095),(0,4095)],[(100,80),(3000,200),(3500,3000),(20,3600)],
           [(20,20),(20,500),(500,500),(500,20)],[(0,0)]*4,
           [(0,0),(4095,0),(2100,100),(2000,100)]]
    for _ in range(30):
        quads.append([(int(rng.integers(30)),int(rng.integers(30))),
                      (int(rng.integers(100,200)),int(rng.integers(30))),
                      (int(rng.integers(100,200)),int(rng.integers(90,160))),
                      (int(rng.integers(30)),int(rng.integers(90,160)))])
    with (ROOT/"vectors/solver.txt").open("w") as f:
        for p in quads:
            try:h=solve_fixed(p,320,452);err=0
            except ValueError:h=[0]*9;err=1
            f.write(" ".join(str(v) for pt in p for v in pt)+f" {err} "+" ".join(f"{v&((1<<40)-1):010x}" for v in h)+"\n")
    # RGB interpolation vectors incl. weight zero, 255, half and invalid samples.
    with (ROOT/"vectors/interp.txt").open("w") as f:
        from brect.fixed import interpolate
        for tag in range(1000):
            pix=rng.integers(0,256,(4,3),dtype=np.uint8)
            fx,fy=[0,128,255][tag%3],int(rng.integers(256));ok=int(tag%11!=0)
            if tag<3:pix[:]=255
            rgb=interpolate(pix,fx,fy) if ok else np.zeros(3,np.uint8)
            packed=[int(c[0])<<16|int(c[1])<<8|int(c[2]) for c in pix]
            expected=int(rgb[0])<<16|int(rgb[1])<<8|int(rgb[2])
            f.write(f"{tag%19==0:d} {tag} {ok} {fx} {fy} "+" ".join(f"{v:06x}" for v in packed)+f" {expected:06x}\n")
    # Visual verification artifact at native pixels scaled by nearest neighbor.
    canvas=Image.new("RGB",(640,310),"#eeeeee");draw=ImageDraw.Draw(canvas)
    draw.text((12,8),"Black markers / oblique paper",fill="black")
    draw.text((330,8),"Rectified full rectangle (RTL target)",fill="black")
    canvas.paste(Image.fromarray(src[0]).resize((288,216)),(12,38))
    canvas.paste(Image.fromarray(outputs[0]).resize((288,216)),(330,38))
    draw.text((12,275),"4 black markers: TL / TR / BR / BL spatial ROIs",fill="black")
    canvas.save(ROOT/"examples/preview.png")
    manifest={"marker_mode":"black_rgb_with_spatial_rois","seed":100676,"source_size":[64,48],"output_size":[32,24],"coordinate_vectors":len(coord),
              "solver_vectors":len(quads),"interpolation_vectors":1000,"metrics":metrics}
    (ROOT/"vectors/manifest.json").write_text(json.dumps(manifest,indent=2))
    return manifest


if __name__=="__main__":print(json.dumps(generate(),indent=2))
