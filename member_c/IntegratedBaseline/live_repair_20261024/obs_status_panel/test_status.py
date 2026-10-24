import unittest
from status_model import summarize

class StatusTests(unittest.TestCase):
    def fields(self, **kw):
        d=dict(image_valid=True,pix_raw=False,pix_frame_id=10,displayed=10,
               corrected=20,raw=0,current_mask=0,first_mask=0,age_ms=150,
               fifo_peak=158,recovery=1)
        d.update(kw)
        return d

    def test_no_data_is_not_success(self):
        self.assertIn('不可用', summarize({},None,0)['text'])

    def test_age_alone_does_not_claim_overflow(self):
        r=summarize(self.fields(age_ms=180),None,0)
        self.assertNotIn('溢出',r['text'])
        self.assertIn('实测',r['text'])

    def test_history_is_not_current_failure(self):
        r=summarize(self.fields(first_mask=8),None,0)
        self.assertIn('历史记录：有故障记录',r['text'])
        self.assertIn('当前故障：未置位',r['text'])

    def test_corrected_counter_not_scan_or_id_fps(self):
        prev={'fields':self.fields(), 'time':0, 'unchanged_since':0}
        r=summarize(self.fields(corrected=40,pix_frame_id=90,displayed=90),prev,2)
        self.assertEqual(r['corrected_fps'],10)

    def test_raw_switch_and_counter_reset_do_not_fake_rate(self):
        prev={'fields':self.fields(), 'time':0,'unchanged_since':0}
        self.assertIsNone(summarize(self.fields(pix_raw=True),prev,2)['corrected_fps'])
        self.assertIsNone(summarize(self.fields(corrected=1),prev,2)['corrected_fps'])

    def test_unchanged_id_warns_and_acknowledges_not_scene_validation(self):
        prev={'fields':self.fields(), 'time':0,'unchanged_since':0}
        r=summarize(self.fields(),prev,3)
        self.assertIn('停更',r['text'])
        self.assertIn('不等于实景正确',r['text'])

if __name__=='__main__':unittest.main()
