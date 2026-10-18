"""Deliberate faults in isolated snapshots; never edit production inputs."""
from pathlib import Path
import sys
name,directory=sys.argv[1:];p=Path(directory).resolve()
assert p.parent.parent==Path('D:/FPGA/output').resolve() and p.name=='source_snapshot'
f=p/'corrected_frame_guard.v';s=f.read_text()
mutations={
 'publish_early':('DRAIN:if(writer_drained&&upstream_idle)state<=COMMIT;','DRAIN:begin state<=COMMIT;end'),
 'ignore_scene':('wire scene_good=in_scene_valid&&!in_error;','wire scene_good=1\'b1;'),
 'ignore_source_bank':('&&in_bank==sb;',';'),
 'ignore_upstream':('ABORT_DRAIN:if(writer_drained&&upstream_idle)','ABORT_DRAIN:if(writer_drained)'),
}
old,new=mutations[name];assert s.count(old)==1;s=s.replace(old,new)
if name=='publish_early':
 # Mutate all drain guards, otherwise COMMIT would still safely block release.
 s=s.replace('state==COMMIT&&upstream_idle&&writer_drained&&','state==COMMIT&&upstream_idle&&')
 s=s.replace("COMMIT:if(!writer_drained||!upstream_idle)cancel(4'd7);else if(publish_valid&&publish_ready)state<=IDLE;","COMMIT:if(publish_valid&&publish_ready)state<=IDLE;")
f.write_text(s)
