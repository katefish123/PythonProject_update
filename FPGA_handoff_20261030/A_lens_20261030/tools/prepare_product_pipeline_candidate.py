"""Prepare an isolated lens-product timing experiment; preserve V1 and its run."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1]
V1=ROOT/'candidate_host_angle_v1';R=ROOT/'candidate_host_angle_v2_product_stage'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    if R.exists():raise ValueError('Candidate already exists')
    R.mkdir();(R/'sources').mkdir();(R/'project').mkdir();(R/'build').mkdir()
    for p in (V1/'sources').iterdir():
        if p.is_file():shutil.copyfile(p,R/'sources'/p.name)
    shutil.copyfile(V1/'project/build_parent_reference.tcl',R/'project/build_parent_reference.tcl')
    p=R/'sources/lens_distort_coord.v';s=p.read_text()
    changes=[
        ('// Ten register stages: request captured at E0, response at E9 (9 intervals).','// Eleven register stages: request captured at E0, response at E10.\n// One exact product boundary separates radial multiply from its constant add.'),
        ('localparam integer STAGES=10;','localparam integer STAGES=11;'),
        ('if(error_pipe[8])','if(error_pipe[STAGES-2])'),
        ("x_pipe[8]});out_y<=$signed({20'd0,y_pipe[8]}","x_pipe[STAGES-2]});out_y<=$signed({20'd0,y_pipe[STAGES-2]}"),
        ("wire signed [71:0] radial_next=72'sd67108864+(r2_inner>>>26);","reg signed [71:0] r2_inner4;\n  wire signed [71:0] radial_next=72'sd67108864+(r2_inner4>>>26);\n  reg signed [31:0] x3d,y3d;\n  reg signed [39:0] tx4d,ty4d;"),
        ('radial4<=0;tx4<=0;ty4<=0;x4<=0;y4<=0;','radial4<=0;tx4<=0;ty4<=0;x4<=0;y4<=0;r2_inner4<=0;x3d<=0;y3d<=0;tx4d<=0;ty4d<=0;'),
        ('radial4<=radial_next[47:0];tx4<=tx_next[39:0];ty4<=ty_next[39:0];x4<=x3;y4<=y3;',
         'r2_inner4<=r2_inner;x3d<=x3;y3d<=y3;tx4<=tx_next[39:0];ty4<=ty_next[39:0];\n    radial4<=radial_next[47:0];x4<=x3d;y4<=y3d;tx4d<=tx4;ty4d<=ty4;'),
        ('x_radial5<=x_radial;y_radial5<=y_radial;tx5<=tx4;ty5<=ty4;','x_radial5<=x_radial;y_radial5<=y_radial;tx5<=tx4d;ty5<=ty4d;'),
    ]
    for a,b in changes:
        if s.count(a)!=1:raise ValueError('Unexpected source '+a)
        s=s.replace(a,b,1)
    p.write_text(s)
    record={'base':str(V1),'candidate':str(R),'scope':'One added exact pipeline stage, no rounding/model changes; V1 remains unchanged.',
            'v1_lens_sha256':sha(V1/'sources/lens_distort_coord.v'),'new_lens_sha256':sha(p),'hardware_accessed':False,'qualified':False}
    (R/'preparation.json').write_text(json.dumps(record,indent=2));print(json.dumps(record,indent=2))

if __name__=='__main__':main()
