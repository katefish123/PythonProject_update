"""Check actual production wiring, including every consumer of moved regions."""
import argparse,re
from pathlib import Path
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);out=p.parse_args().output
    top=(out/'diagnostics/ddr_camera_hires_prefetch_20261012/results/video_correct_ddr_top.v').read_text()
    core=(out/'rtl/top/video_correct_ddr_core.v').read_text()
    def need(text,fragment):
        if fragment not in re.sub(r'\s+','',text):raise AssertionError('Missing full-HD production wiring: '+fragment)
    for fragment in ['.SRC_W(1920)','.SRC_H(1080)','.OUT_W(640)','.OUT_H(904)','.SCALE(1)',
                     ".RESULT_BASE0(28'h0200000)",".RESULT_BASE1(28'h0400000)",".BIST_BASE(28'h0600000)",
                     '.MARKER_MIN_PIXELS(64)','.MARKER_MAX_PIXELS(16384)','.MARKER_MAX_SPAN(256)']:
        need(top,fragment)
    for instance in ['destination_writer','display_reader']:
        match=re.search(r'\b\w+\s*#\((.*?)\)\s*'+instance+r'\s*\(',core,re.S)
        assert match,instance
        need(match[1],'.BASE0(RESULT_BASE0),.BASE1(RESULT_BASE1)')
    need(core,'.BASE(BIST_BASE)');need(core,'.MAX_PIXELS(MARKER_MAX_PIXELS)');need(core,'.MAX_SPAN(MARKER_MAX_SPAN)')
    assert top.count(".RESULT_BASE0(28'h0200000)")==2,'Core and prefetch engine must agree'
    regions=[(0,1920*1080),(0x200000,0x200000+640*904),(0x400000,0x400000+640*904),(0x600000,0x600000+256*8)]
    assert all(a[1]<=b[0] for a,b in zip(regions,regions[1:]))
    print('FULLHD_CONFIGURATION_PASS source=1920x1080 result=640x904 display=1920x1080 disjoint_regions=4')
if __name__=='__main__':main()
