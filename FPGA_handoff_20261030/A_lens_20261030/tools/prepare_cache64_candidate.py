"""Isolate the measured bridge decode and cache-layout timing repairs."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1]
OLD=ROOT/'candidate_host_angle_v2_product_stage';R=ROOT/'candidate_host_angle_v3_cache64'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def replace_once(s,a,b):
    if s.count(a)!=1:raise ValueError((a,s.count(a)))
    return s.replace(a,b,1)

def main():
    if R.exists():raise ValueError('Candidate already exists')
    R.mkdir();(R/'sources').mkdir();(R/'project').mkdir();(R/'build').mkdir()
    for p in (OLD/'sources').iterdir():
        if p.is_file():shutil.copyfile(p,R/'sources'/p.name)
    shutil.copyfile(OLD/'project/build_parent_reference.tcl',R/'project/build_parent_reference.tcl')
    p=R/'sources/video_correct_ddr_top.v';s=p.read_text();s=replace_once(s,'.SOURCE_CACHE_LINES(128)','.SOURCE_CACHE_LINES(64)');p.write_text(s)
    p=R/'sources/frame_processor_stream.v';s=p.read_text()
    for a,b in [('128x128 traversal','64x64 traversal'),('two adjacent bursts','successive source rows'),
                ('x[6:0]','x[5:0]'),('y[6:0]','y[5:0]'),('x-12\'d127','x-12\'d63'),
                ("{y[11:7],7'd0}","{y[11:6],6'd0}"),('OUT_W-127','OUT_W-63'),
                ('==127','==63'),('!=127','!=63'),('OUT_W<128','OUT_W<64'),('OUT_W%128','OUT_W%64'),
                ('128-column tiles with clipped128-row bands','64-column tiles with clipped64-row bands')]:s=s.replace(a,b)
    p.write_text(s)
    p=R/'sources/ddr_result_writer_burst64.v';s=p.read_text()
    for a,b in [('reg[6:0]tile_row','reg[5:0]tile_row'),('tile_row==127','tile_row==63'),
                ('tiled_active&&closes&&write_addr[6]','tiled_active&&closes'),('OUT_W-127','OUT_W-63'),
                ('OUT_W/128-1','OUT_W/64-1'),("tile_y_base+12'd128","tile_y_base+12'd64"),
                ('OUT_W<128','OUT_W<64'),('OUT_W%128','OUT_W%64'),
                ('128-column tiles with clipped128-row bands','64-column tiles with clipped64-row bands')]:s=s.replace(a,b)
    p.write_text(s)
    p=R/'sources/quad_packet_bridge.v';s=p.read_text()
    s=replace_once(s,'// Three elastic stages separate descriptor capture, constant address decode,',
                    '// Four elastic stages separate capture, reciprocal product, exact decode,')
    s=replace_once(s,'reg raw_valid,decoded_valid,packet_valid;','reg raw_valid,divide_valid,decoded_valid,packet_valid;')
    s=replace_once(s,'wire decoded_ready=!decoded_valid||cooked_ready;',
                    'wire decoded_ready=!decoded_valid||cooked_ready;\n wire divide_ready=!divide_valid||decoded_ready;')
    s=replace_once(s,'assign q_ready=rst_n&&(!raw_valid||decoded_ready);','assign q_ready=rst_n&&(!raw_valid||divide_ready);')
    s=replace_once(s,'wire[23:0]raw_x=raw_addr00%SRC_W,raw_y=raw_addr00/SRC_W;',r'''
 //1920=128*15. For all65536 unsigned16-bit values n,
 // floor(n/15)=(n*34953)>>19. All legal1920x<=4096 source addresses
 // have bit23=0; that bit remains in the descriptor's independent range check.
 localparam FAST_DECODE=(SRC_W==1920&&SRC_H<=4096);
 reg[197:0]divide_payload;reg[31:0]divide_product;
 wire[31:0]raw_product=raw_addr00[22:7]*16'd34953;
 wire[23:0]divide_addr=divide_payload[137:114];
 wire[23:0]raw_y=FAST_DECODE?(divide_product>>19):(divide_addr/SRC_W);
 wire[23:0]remainder_words={8'd0,divide_addr[22:7]}-raw_y*24'd15;
 wire[23:0]raw_x=FAST_DECODE?{13'd0,remainder_words[3:0],divide_addr[6:0]}:(divide_addr%SRC_W);''')
    s=replace_once(s,'raw_valid<=0;decoded_valid<=0;','raw_valid<=0;divide_valid<=0;divide_payload<=0;divide_product<=0;decoded_valid<=0;')
    s=replace_once(s,'decoded_valid<=raw_valid;\n    if(raw_valid)decoded_payload<={raw_payload,raw_x,raw_y};',
                    'decoded_valid<=divide_valid;\n    if(divide_valid)decoded_payload<={divide_payload,raw_x,raw_y};')
    s=replace_once(s,'   if(q_ready)begin',
                    '   if(divide_ready)begin\n    divide_valid<=raw_valid;\n    if(raw_valid)begin divide_payload<=raw_payload;divide_product<=raw_product;end\n   end\n   if(q_ready)begin')
    p.write_text(s)
    record={'base':str(OLD),'candidate':str(R),'hardware_accessed':False,'qualified':False,
            'scope':'Same11-stage lens arithmetic.64x64 rotated traversal/cache64. Exact1920 address division uses registered reciprocal product and one added elastic stage; original bad-address/tag checks remain.'}
    (R/'preparation.json').write_text(json.dumps(record,indent=2));print(json.dumps(record,indent=2))

if __name__=='__main__':main()
