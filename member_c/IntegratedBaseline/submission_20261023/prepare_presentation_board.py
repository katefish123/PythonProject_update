"""Fresh board candidate: presentation controls only, preserving qualified RTL."""
from pathlib import Path
import argparse,hashlib,json,shutil

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    q=json.loads((a.baseline/'release/qualification.json').read_text())
    for n,h in q['candidate_source_sha256'].items():
        if sha(a.baseline/'sources'/n)!=h:raise ValueError('Qualified source drift '+n)
    a.output.mkdir(parents=True,exist_ok=False);(a.output/'build').mkdir();shutil.copytree(a.baseline/'sources',a.output/'sources')
    p=a.output/'sources/video_correct_ddr_top.v';s=p.read_text()
    old_header=' parameter HDMI_HOLD=10000,RECOVERY_HOLD=100000,RECOVERY_TIMEOUT=5000000,RECOVERY_SETTLE=1000000'
    new_header=old_header+',\n parameter DIAGNOSTIC_HOLD_CYCLES=500000,PRESENTATION_STALE_FRAMES=30'
    old_overlay=' assign overlay_on=status_on||telemetry_on;\n assign overlay_rgb=status_on?status_rgb:telemetry_rgb;\n'
    new_overlay=''' // BEGIN_PRESENTATION_POLICY
 // The key chord changes only the view, never the numerical algorithm.
 // Existing KEY1 RAW / KEY2 nearest behavior remains in effect while held.
 localparam DIAG_WIDTH=DIAGNOSTIC_HOLD_CYCLES<2?1:$clog2(DIAGNOSTIC_HOLD_CYCLES+1);
 (* ASYNC_REG="TRUE" *)reg[2:0]diagnostic_key_sync;
 reg[DIAG_WIDTH-1:0]diagnostic_hold;
 reg diagnostic_pressed,diagnostic_requested;
 always @(posedge cfg_clk or negedge cfg_rst)begin
  if(!cfg_rst)begin diagnostic_key_sync<=0;diagnostic_hold<=0;diagnostic_pressed<=0;diagnostic_requested<=0;end
  else begin
   diagnostic_key_sync<={diagnostic_key_sync[1:0],!key1_pattern_n&&!key2_nearest_n};
   if(!diagnostic_key_sync[2])begin diagnostic_hold<=0;diagnostic_pressed<=0;end
   else if(!diagnostic_pressed)begin
    if(diagnostic_hold==DIAGNOSTIC_HOLD_CYCLES-1)begin diagnostic_requested<=!diagnostic_requested;diagnostic_pressed<=1;end
    else diagnostic_hold<=diagnostic_hold+1'b1;
   end
  end
 end
 (* ASYNC_REG="TRUE" *)reg[2:0]diagnostic_pix_sync;
 localparam STALE_WIDTH=PRESENTATION_STALE_FRAMES<2?1:$clog2(PRESENTATION_STALE_FRAMES+1);
 reg[STALE_WIDTH-1:0]presentation_same_scans;
 reg[31:0]presentation_last_id;
 wire presentation_stale=image_valid&&debug_display_id==presentation_last_id&&presentation_same_scans>=PRESENTATION_STALE_FRAMES-1;
 assign presentation_status=presentation_stale&&(pix_status==5'd9||pix_status==5'd12||pix_status==5'd13)?5'd13:pix_status;
 reg diagnostic_shown,warning_shown;
 always @(posedge pix_clk or negedge pix_rst)begin
  if(!pix_rst)begin diagnostic_pix_sync<=0;diagnostic_shown<=0;warning_shown<=1;presentation_same_scans<=0;presentation_last_id<=0;end
  else begin
   diagnostic_pix_sync<={diagnostic_pix_sync[1:0],diagnostic_requested};
   if(scan_start)begin
    diagnostic_shown<=diagnostic_pix_sync[2];
    presentation_last_id<=debug_display_id;
    if(!image_valid||debug_display_id!=presentation_last_id)presentation_same_scans<=0;
    else if(presentation_same_scans<PRESENTATION_STALE_FRAMES)presentation_same_scans<=presentation_same_scans+1'b1;
    warning_shown<=!image_valid||presentation_stale||(pix_status!=5'd9&&pix_status!=5'd12&&pix_status!=5'd13);
   end
  end
 end
 assign overlay_on=(status_on&&(diagnostic_shown||warning_shown))||(telemetry_on&&diagnostic_shown);
 assign overlay_rgb=status_on&&(diagnostic_shown||warning_shown)?status_rgb:telemetry_rgb;
 // END_PRESENTATION_POLICY
'''
    if s.count(old_header)!=1 or s.count(old_overlay)!=1:raise ValueError('Unexpected parent presentation')
    old_status=next(line for line in s.splitlines() if 'status_overlay status_view(' in line)+'\n'
    new_status=' wire[4:0]presentation_status;\n'+old_status.replace('.status(pix_status)','.status(presentation_status)')
    if s.count(old_status)!=1:raise ValueError('Unexpected status renderer')
    p.write_text(s.replace(old_header,new_header).replace(old_overlay,new_overlay).replace(old_status,new_status))
    m=json.loads((a.baseline/'source_manifest.json').read_text())
    m['presentation']={'qualified_parent':str(a.baseline.resolve()),'qualified_parent_top_sha256':sha(a.baseline/'sources/video_correct_ddr_top.v'),'old_header':old_header,'new_header':new_header,'old_overlay':old_overlay,'new_overlay':new_overlay,'old_status':old_status,'new_status':new_status}
    m['candidate_source_sha256']={p.name:sha(p) for p in (a.output/'sources').iterdir()}
    m['scope']+='; clean fullHD default, frame-boundary diagnostic toggle, fault banner retained'
    (a.output/'source_manifest.json').write_text(json.dumps(m,indent=2)+'\n')
    (a.output/'build.tcl').write_text((a.baseline/'build.tcl').read_text().replace(a.baseline.resolve().as_posix(),a.output.resolve().as_posix()))
    print(a.output)

if __name__=='__main__':main()
