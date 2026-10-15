"""Add verified frame-age overlay to a fresh generated continuous candidate."""
from pathlib import Path
import argparse,hashlib,json,shutil
HERE=Path(__file__).resolve().parent
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')
def once(s,a,b):
 assert s.count(a)==1,(a,s.count(a))
 return s.replace(a,b,1)
def install(out):
 top=out/CAND/'video_correct_ddr_top.v';s=top.read_text()
 s=once(s,'wire[23:0]rgb,preview_rgb,overlay_rgb;','wire[23:0]rgb,preview_rgb,overlay_rgb,status_rgb,telemetry_rgb;\n wire status_on,telemetry_on;\n wire[31:0]displayed_id,display_age,admitted_count,published_count,rejected_count;wire[511:0]reject_counts;')
 s=once(s,'.status(screen_status),.on(overlay_on),.rgb(overlay_rgb));','.status(screen_status),.on(status_on),.rgb(status_rgb));\n frame_telemetry_overlay telemetry_view(.proc_clk(proc_clk54),.proc_rst_n(proc_rst),.pix_clk(pix_clk),.pix_rst_n(scan_reset_n),\n .scan_de(scan_de),.scan_start(scan_start),.x(scan_x),.y(scan_y),.displayed_frame_id(displayed_id),.display_age_ms(display_age),\n .admitted_frames(admitted_count),.published_frames(published_count),.rejected_frames(rejected_count),.reject_reason_counts(reject_counts),.image_valid(image_valid),.on(telemetry_on),.rgb(telemetry_rgb));\n assign overlay_on=status_on||telemetry_on;\n assign overlay_rgb=status_on?status_rgb:telemetry_rgb;')
 s=once(s,'.good_frames(),.rejected_frames(),','.good_frames(published_count),.rejected_frames(rejected_count),\n .capture_frame_id(),.processing_frame_id(),.published_frame_id(),.displayed_frame_id(displayed_id),.display_age_ms(display_age),.admitted_frames(admitted_count),.dropped_frames(),.rejected_reason_counts(reject_counts),')
 top.write_text(s)
 dst=out/'rtl/stream/frame_telemetry_overlay.v';shutil.copyfile(HERE.parent/'telemetry/frame_telemetry_overlay.v',dst)
 build=out/CAND/'build.tcl';build.write_text(once(build.read_text(),'compile -top_module','add_design {'+dst.as_posix()+'}\ncompile -top_module'))
 mpath=out/'stream_sources.json';m=json.loads(mpath.read_text())
 for p in [top,dst,build]:m['files'][p.relative_to(out).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
 m['telemetry']='Frame-consistent mailbox: corrected-frame source age, displayed generation and rejection counters; optical quality unverified.'
 mpath.write_text(json.dumps(m,indent=2)+'\n')
 print('CONTINUOUS_TELEMETRY_INSTALLED; NOT hardware qualified')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=Path);a=p.parse_args();install(a.output.resolve())
