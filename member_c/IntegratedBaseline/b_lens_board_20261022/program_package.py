"""Verify the offline delivery, then temporarily program CRAM and read back."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,re,socket,subprocess,time

def require(ok,msg):
    if not ok:raise RuntimeError(msg)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def ensure_jtag_server(tool,run):
    # Fabric Configuration User Guide section 3.1 documents cdt_js -port.
    # This is deliberately called only after immutable package checks and
    # after --check-only has returned; offline validation never starts it.
    def listening():
        try:
            with socket.create_connection(('127.0.0.1',65420),timeout=0.3):return True
        except OSError:return False
    if listening():return
    server=tool.with_name('cdt_js.exe');require(server.is_file(),'Missing matching PDS cdt_js.exe')
    with (run/'jtag_server.log').open('wb') as f:
        child=subprocess.Popen([str(server),'-port','65420'],cwd=tool.parent,stdout=f,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    for _ in range(100):
        if listening():return
        require(child.poll() is None,'JTAG server stopped; inspect jtag_server.log')
        time.sleep(0.1)
    raise RuntimeError('JTAG server did not start; inspect jtag_server.log')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check-only',action='store_true');args=parser.parse_args()
    root=Path(__file__).resolve().parent.parent
    manifest=json.loads((root/'MANIFEST_SHA256.json').read_text())
    for name,h in manifest.items():
        p=root/name;require(p.resolve().is_relative_to(root),'Path escapes package')
        # PDS updates its project/cache/logs when opened. The qualified image,
        # exact sources and independent reports remain immutable below.
        if p.resolve().relative_to(root).parts[0]=='project':continue
        require(p.is_file() and sha(p)==h,'Package changed: '+name)
    q=json.loads((root/'release/qualification.json').read_text())
    require(q['ready_for_authorized_cram_experiment'] and q['timing_qualified'],'Unqualified release')
    bit=root/'release/video_correct_ddr_top.sbit';mask=bit.with_suffix('.smsk')
    require(sha(bit)==q['bitstream_sha256'] and sha(mask)==q['mask_sha256'],'Bit/mask mismatch')
    for n,h in q['candidate_source_sha256'].items():require(sha(root/'sources'/n)==h,'Source drift '+n)
    report=root/'validation/final_timing.rtr'
    require(sha(report)==q['final_timing_sha256'],'Timing report mismatch')
    if args.check_only:
        print('PACKAGE_INTEGRITY_VERIFIED; hardware not accessed')
        return
    # A qualified image is a candidate for a live test, not optical acceptance.
    tool=Path(os.environ.get('PDS_CFG_SHELL','D:/softwares/PDS/PDS_2022.2-SP6.4/bin/cdt_cfg_shell.exe'))
    require(tool.is_file(),'Set PDS_CFG_SHELL to the installed cdt_cfg_shell.exe')
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    run=root/'program_logs'/stamp;run.mkdir(parents=True,exist_ok=False)
    ensure_jtag_server(tool,run)
    tcl='cfg_set_tcl_break -flag true\ncfg_connect -ip 127.0.0.1 -port 65420\ncfg_scan_chain\n'+f'cfg_assign_file -file {{{bit.as_posix()}}} -device_index 0\n'+'cfg_set_device_property -device_index 0 -program 1\ncfg_program -device_index 0\ncfg_verify -device_index 0\ncfg_disconnect\ncfg_close\n'
    (run/'program.tcl').write_text(tcl)
    with (run/'program.log').open('wb') as f:
        result=subprocess.run([str(tool),'-file',str(run/'program.tcl')],cwd=run,stdout=f,stderr=subprocess.STDOUT)
    raw=(run/'program.log').read_bytes();log=raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig',errors='replace')
    require(result.returncode==0 and not re.search(r'^E:|ERROR:',log,re.M),'Programming failed: '+str(run/'program.log'))
    for token in ['PG2L100H','COMMAND[Program] execute successfully','Executing : cfg_program -device_index 0 successfully.','COMMAND[Verify] execute successfully','Executing : cfg_verify -device_index 0 successfully.']:
        require(token in log,'Missing hardware proof: '+token)
    (run/'hardware_programming.json').write_text(json.dumps(dict(hardware_programmed=True,readback_verified=True,flash_programmed=False,bitstream_sha256=sha(bit),program_log_sha256=sha(run/'program.log'),real_video_acceptance=False,timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat()),indent=2)+'\n')
    print('CRAM Program + Verify passed. Continue the live camera/RAW/corrected acceptance steps.')
    print(run)
if __name__=='__main__':main()
