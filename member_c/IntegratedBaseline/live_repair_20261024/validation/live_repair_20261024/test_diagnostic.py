from pathlib import Path
import unittest
class DiagnosticContract(unittest.TestCase):
 def test_diagnostic_is_always_visible(self):
  top=(Path(__file__).parent/'candidate_v2/sources/video_correct_ddr_top.v').read_text()
  self.assertIn('assign overlay_on=status_on||telemetry_on;',top)
 def test_reason_and_scan_observers(self):
  top=(Path(__file__).parent/'candidate_v2/sources/video_correct_ddr_top.v').read_text()
  self.assertIn('reject_counts[12*32+:32],reject_counts[13*32+:32]',top)
  self.assertIn('reject_counts[14*32+:32],reject_counts[15*32+:32]',top)
  self.assertIn('proc_scan_count',top)
  self.assertIn('ui_service_totals',top)
if __name__=='__main__':unittest.main()
