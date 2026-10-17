"""Intentional incorrect snapshot variants to prove regression sensitivity."""
from pathlib import Path
import sys
kind=sys.argv[1];folder=Path(sys.argv[2]).resolve()
assert folder.name=='source_snapshot' and folder.parent.parent==Path('D:/FPGA/output').resolve()
variants={
 'erase_all_neighbors':('source_marker_clean.v','association_ok&&marker_hit[i]?','association_ok&&(|marker_hit)?'),
 'outside_fill':('frame_region.v',"inside_s1?(s1_target?2'd2:2'd1):2'd0;","inside_s1?(s1_target?2'd2:2'd1):2'd1;"),
 'commit_busy':('frame_region.v',"else if(!s1_valid&&!out_valid&&downstream_idle)begin","else if(1'b1)begin"),
}
name,old,new=variants[kind];p=folder/name;t=p.read_text()
assert t.count(old)==1,('unexpected source',kind)
p.write_text(t.replace(old,new))
