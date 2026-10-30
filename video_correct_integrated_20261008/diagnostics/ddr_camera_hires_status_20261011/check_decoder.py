"""Verify physical-grid field boundaries and reject the older image signature."""
from pathlib import Path
import hashlib
import importlib.util
import json
from PIL import Image,ImageDraw

D=Path(__file__).resolve().parent
O=D/"results"
spec=importlib.util.spec_from_file_location("d206_decoder",D/"decode_status.py")
decoder=importlib.util.module_from_spec(spec)
spec.loader.exec_module(decoder)
rx=(5<<80)|(2<<64)|(518400<<40)|(1080<<24)|(4<<16)|64800
proc=(3<<80)|(9<<48)|(1<<40)|(2<<36)|(8<<32)|25000000
marker=(8<<176)|(1200<<160)|(1201<<144)|(1202<<128)|(1203<<112)
ui=(2500<<48)|(5591<<32)|(1000<<22)|(900<<12)|(3<<10)|(79<<3)|6
word=(0xD206<<496)|(0xf08b<<480)|(rx<<384)|(proc<<256)|(marker<<64)|ui
def frame(value,path):
    image=Image.new("RGB",(1920,1080),(31,31,31))
    draw=ImageDraw.Draw(image)
    for row in range(32):
        for col in range(16):
            bit=(value>>(511-row*16-col))&1
            color=(31,176,31) if bit else (176,31,31)
            draw.rectangle((col*120,720+row*10,(col+1)*120-1,729+row*10),fill=color)
    image.save(path)
path=O/"decoder_d206_fixture.png"
frame(word,path)
record=decoder.decode(path)
expected={"rx_good_captures":5,"rx_bad_captures":2,"last_capture_samples":518400,"last_capture_lines":1080,
    "last_capture_packets":64800,"good_results":3,"rejected_results":9,"processor_cycles":25000000,
    "marker_counts":[1200,1201,1202,1203],"display_last_row_cycles":2500,"display_max_row_cycles":5591,
    "display_rows_done":1000,"display_current_row":900,"display_fetch_state":3,"display_beat_index":79,
    "display_scan_active":True,"display_request_seen":1,"display_ack_seen":0}
for name,value in expected.items():
    assert record[name]==value,(name,record[name],value)
wrong=O/"decoder_old_d205_fixture.png"
frame((word&((1<<496)-1))|(0xD205<<496),wrong)
try:
    decoder.decode(wrong)
except ValueError as error:
    assert "signature" in str(error)
else:
    raise AssertionError("Decoder accepted older D205 firmware")
record={"passed":True,"physical_camera_evidence":False,"checked_fields":expected,
    "wrong_signature_rejected":True,"decoder_sha256":hashlib.sha256((D/"decode_status.py").read_bytes()).hexdigest()}
(O/"decoder_qualification.json").write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
print("D206 decoder field-boundary and wrong-image rejection checks passed; synthetic fixture only.")
