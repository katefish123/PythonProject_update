"""Prepare independent checked build, decoder and CRAM programming paths."""
from pathlib import Path

D=Path(__file__).resolve().parent
R=D.parents[1]
old=R/"diagnostics/ddr_camera_status_20261011"
for name in ["run_checks.ps1","build.ps1","archive.py"]:
    text=(old/name).read_text(encoding="utf-8-sig")
    text=text.replace("ddr_camera_status","ddr_camera_hires_status")
    if name=="build.ps1":
        text=text.replace("-ne 4","-ne 8").replace("Four diagnostic", "Eight diagnostic")
    if name=="archive.py":
        text=text.replace('== 4 and', '== 8 and')
        text=text.replace('release/ddr_camera_reconnect_20261011','release/ddr_camera_hires_20261011')
        text=text.replace('"ddr_snapshot_capture.v", "ddr_capture_writer.v",', '"ddr_result_display.v", "ddr_snapshot_capture.v", "ddr_capture_writer.v",')
        text=text.replace('"a4bd7f42732c100b598cb974e03477877aab4032e39f6de558bb245d666e232e"','"7aed1ed5af2d32994a620f7bd3f198253365ceeccd967528daa6694e52dac2e0"')
        text=text.replace('"source_sampling": [640, 480], "processed_output": [320, 452]', '"source_sampling": [960, 540], "processed_output": [640, 904]')
        text=text.replace('overlay D205 at y720..1039', 'overlay D206 at y720..1039 with real display row-fetch duration and progress')
        text=text.replace('list(O.glob("tb*.do"))', 'list(O.glob("tb*.do")) + list(O.glob("*.hex")) + list(O.glob("*.pds"))')
    (D/name).write_text(text,encoding="utf-8")
for relative in ["pds/program_ddr_camera_hires.tcl","scripts/program_ddr_camera_hires.ps1"]:
    original=R/relative
    target=original.with_name(original.name.replace("ddr_camera_hires","ddr_camera_hires_status"))
    assert target!=original
    target.write_text(original.read_text(encoding="utf-8-sig").replace("ddr_camera_hires","ddr_camera_hires_status"),encoding="utf-8")
text=(old/"decode_status.py").read_text(encoding="utf-8-sig").replace("D205","D206")
before='''        ui_packets_seen=(ui >> 40) & 0xffffff, ui_packets_written=(ui >> 16) & 0xffffff,
        ui_writer_state=(ui >> 13) & 7, ui_frame_bad=bool((ui >> 12) & 1), ui_rx_capture_ok=bool((ui >> 11) & 1),
        ui_empty_quiet=ui & 0xff)'''
after='''        display_last_row_cycles=(ui >> 48) & 0xffff, display_max_row_cycles=(ui >> 32) & 0xffff,
        display_rows_done=(ui >> 22) & 0x3ff, display_current_row=(ui >> 12) & 0x3ff,
        display_fetch_state=(ui >> 10) & 3, display_beat_index=(ui >> 3) & 0x7f,
        display_scan_active=bool((ui >> 2) & 1), display_request_seen=(ui >> 1) & 1,
        display_ack_seen=ui & 1)'''
assert text.count(before)==1
(D/"decode_status.py").write_text(text.replace(before,after),encoding="utf-8")
print("Prepared independent D206 build/program/decoder; prior releases retained.")
