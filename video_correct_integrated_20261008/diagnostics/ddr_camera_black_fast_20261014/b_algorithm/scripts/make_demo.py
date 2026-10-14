"""A larger printable-paper scene, explicit inverse sampling for synthesis only."""
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"python"))
from brect.golden import CORNERS,homography,rectify_float,detect_markers
from brect.fixed import rectify_fixed,map_fixed,T


def make():
    width,height=210,297
    doc=Image.new("RGB",(width,height),"white");draw=ImageDraw.Draw(doc)
    try:font=ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf",18)
    except OSError:font=ImageFont.load_default()
    draw.text((14,16),"FPGA MEMBER B",font=font,fill="black")
    draw.text((14,46),"FULL PAPER RECTIFICATION",fill="black")
    draw.text((14,66),"4 markers -> H -> pixel mapping",fill="black")
    draw.rectangle((12,95,197,278),outline="black",width=2)
    for x in range(12,198,23):draw.line((x,95,x,278),fill="#666666",width=1)
    for y in range(95,279,23):draw.line((12,y,197,y),fill="#666666",width=1)
    draw.ellipse((55,138,155,238),outline="black",width=3)
    p=[(210,40),(485,100),(510,440),(90,410)]
    h=homography(p,width,height);forward=np.linalg.inv(h)
    yy,xx=np.mgrid[:480,:640];flat=np.stack([xx.ravel(),yy.ravel(),np.ones(xx.size)])
    mapped=forward@flat;u=mapped[0]/mapped[2];v=mapped[1]/mapped[2]
    mask=(u>=0)&(u<=width-1)&(v>=0)&(v<=height-1)
    image=np.full((480*640,3),180,np.uint8);paper=np.asarray(doc)
    image[mask]=paper[np.floor(v[mask]+.5).astype(int),np.floor(u[mask]+.5).astype(int)]
    image=image.reshape(480,640,3)
    for x,y in p:image[y-4:y+5,x-4:x+5]=0
    # Tight windows separate the corner markers from the genuine black text.
    rois={name:[[x-12,y-12],[x+12,y+12]] for name,(x,y) in zip(CORNERS,p)}
    (ROOT/"examples/rois_demo.json").write_text(json.dumps(rois,indent=2),encoding="utf-8")
    pts,stats=detect_markers(image,rois=rois);assert np.array_equal(pts,p)
    floating,hf=rectify_float(image,pts,width,height)
    fixed,hq=rectify_fixed(image,pts,width,height)
    for name,im in [("demo_document",paper),("demo_input",image),("demo_float",floating),("demo_fixed",fixed)]:
        Image.fromarray(im).save(ROOT/f"examples/{name}.png")
    diff=np.abs(floating.astype(int)-fixed.astype(int))
    info={"marker_mode":"black_rgb_with_spatial_rois","source_size":[640,480],"output_size":[width,height],"points":p,"H_q":hq,
          "roi_file":"examples/rois_demo.json","statistics":stats,
          "pixel_mae":float(diff.mean()),"pixel_max_error":int(diff.max()),"assumption":"Marker centers are the paper corners"}
    (ROOT/"examples/demo_parameters.json").write_text(json.dumps(info,indent=2))
    preview=Image.new("RGB",(905,500),"#eeeeee");d=ImageDraw.Draw(preview)
    d.text((14,12),"Synthetic camera input, 640 x 480",fill="black")
    d.text((668,12),"Rectified, 210 x 297",fill="black")
    preview.paste(Image.fromarray(image),(14,30));preview.paste(Image.fromarray(fixed),(668,80))
    preview.save(ROOT/"examples/demo_preview.png")
    print(json.dumps(info,indent=2))


if __name__=="__main__":make()
