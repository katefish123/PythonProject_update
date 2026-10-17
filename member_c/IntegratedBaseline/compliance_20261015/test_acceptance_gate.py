import unittest
from pathlib import Path
from acceptance_gate import evaluate

ROOT=Path(__file__).resolve().parent.parent

class AcceptanceGateTests(unittest.TestCase):
 def test_current_H_only_release_cannot_satisfy_enterprise_lens_acceptance(self):
  result=evaluate(ROOT)
  self.assertFalse(result['enterprise_acceptance'])
  self.assertIn('LENS_RTL',result['unmet'])
  self.assertIn('REAL_CALIBRATION',result['unmet'])
  self.assertIn('HELD_OUT_QUALITY',result['unmet'])
  self.assertEqual(result['decision'],'NOT_READY')
 def test_fresh_model_evidence_is_only_software_evidence(self):
  r=evaluate(ROOT)
  self.assertEqual(r['checks']['SOFTWARE_REFERENCE']['status'],'PASS')
  self.assertEqual(r['checks']['SOFTWARE_REFERENCE']['scope'],'synthetic_software_only')
  self.assertFalse(r['enterprise_acceptance'])
 def test_changed_reference_hash_rejects_software_evidence(self):
  import json
  receipt=json.loads((ROOT/'lens_model_20261015/verification.json').read_text())
  receipt['source_sha256']['lens_fixed.py']='0'*64
  r=evaluate(ROOT,model_receipt=receipt)
  self.assertEqual(r['checks']['SOFTWARE_REFERENCE']['status'],'FAIL')
 def test_synthetic_pass_and_V5C_timing_never_grant_lens_qualification(self):
  import json
  receipt=json.loads((ROOT/'lens_model_20261015/verification.json').read_text())
  receipt.update(hardware_acceptance=True,real_camera_calibration='passed',rtl_lens='passed')
  r=evaluate(ROOT,model_receipt=receipt)
  self.assertFalse(r['enterprise_acceptance'])
  self.assertEqual(r['checks']['SOFTWARE_REFERENCE']['status'],'FAIL')
  self.assertEqual(r['checks']['LENS_PDS']['status'],'UNVERIFIED')
 def test_missing_calibration_file_remains_explicit_data_gap(self):
  r=evaluate(ROOT)
  self.assertEqual(r['checks']['REAL_CALIBRATION']['status'],'MISSING_DATA')
  self.assertTrue(r['checks']['REAL_CALIBRATION']['external_data_required'])
 def test_local_frame_rules_are_a_separate_unqualified_gate(self):
  r=evaluate(ROOT)
  self.assertIn('LOCAL_FRAME_COMPOSITION',r['unmet'])
  self.assertNotEqual(r['checks']['LOCAL_FRAME_COMPOSITION']['status'],'PASS')

if __name__=='__main__':unittest.main()
