"""Record fresh software-only float/fixed evidence tied to source bytes."""
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime,timezone
from pathlib import Path

HERE=Path(__file__).resolve().parent
names=['lens_golden.py','test_lens_golden.py','lens_fixed.py','test_lens_fixed.py']
hashes={name:hashlib.sha256((HERE/name).read_bytes()).hexdigest() for name in names}
proc=subprocess.run([sys.executable,'-B','-m','unittest','-v','test_lens_golden.py','test_lens_fixed.py'],cwd=HERE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
text=proc.stdout
if proc.returncode or not re.search(r'Ran 17 tests',text) or '\nOK\n' not in text:raise SystemExit(text)
error=float(re.search(r'maximum_source_pixel_error=([\d.e+-]+)',text)[1])
assert error<=.125
for name,digest in hashes.items():assert hashlib.sha256((HERE/name).read_bytes()).hexdigest()==digest
(HERE/'test_results.log').write_text(text)
(HERE/'verification.json').write_text(json.dumps(dict(generated_utc=datetime.now(timezone.utc).isoformat(),status='pass',exit_code=0,
    tests=17,independent_expanded_polynomial_samples=600,fixed_comparison_samples=5000,
    fixed_maximum_source_pixel_error_on_declared_samples=error,source_sha256=hashes,
    scope='synthetic Python float64 and signed Q34.30 integer model only',fixed_integer_model='implemented_and_sample_tested',
    exhaustive_error_bound_proved=False,rtl_lens='not_implemented',real_camera_calibration='not_available',hardware_acceptance=False),indent=2)+'\n')
print('LENS_MODELS_PASS tests=17 max_sample_error='+str(error)+' hardware_accepted=false')
