import unittest
import video_metrics as metrics

class VideoMetricsTests(unittest.TestCase):
    def test_simulation_source_id_jumps_are_not_extra_results(self):
        text='\n'.join(f'# PIPELINE_PUBLICATION corrected=1 id={i} count={n} time={t}' for i,n,t in [(1,1,100000000000),(8,2,200000000000),(14,3,300000000000)])
        r=metrics.analyze_publications(text,'ps')
        self.assertAlmostEqual(r['new_result_fps_between_events'],10)
        self.assertEqual(r['new_result_events'],3)
        self.assertFalse(r['hardware_acceptance'])

    def test_two_events_are_a_sample_not_sustained_acceptance(self):
        r=metrics.analyze_publications('PIPELINE_PUBLICATION corrected=1 id=1 count=1 time=10\nPIPELINE_PUBLICATION corrected=1 id=2 count=2 time=30','ms')
        self.assertAlmostEqual(r['new_result_fps_between_events'],50)
        self.assertEqual(r['intervals'],1)
        self.assertEqual(r['evidence_scope'],'simulation_sample')

    def test_counter_reset_requires_separate_epoch(self):
        with self.assertRaisesRegex(ValueError,'epoch'):
            metrics.analyze_publications('PIPELINE_PUBLICATION corrected=1 id=4 count=3 time=10\nPIPELINE_PUBLICATION corrected=1 id=1 count=1 time=30','ms')

    def test_counter_gap_does_not_invent_missing_timestamps(self):
        with self.assertRaisesRegex(ValueError,'missing'):
            metrics.analyze_publications('PIPELINE_PUBLICATION corrected=1 id=1 count=1 time=10\nPIPELINE_PUBLICATION corrected=1 id=8 count=3 time=30','ms')

    def test_raw_publications_are_not_corrected_results(self):
        with self.assertRaisesRegex(ValueError,'two'):
            metrics.analyze_publications('PIPELINE_PUBLICATION corrected=0 id=1 count=1 time=10\nPIPELINE_PUBLICATION corrected=0 id=2 count=2 time=30','ms')

    def test_repeated_capture_frames_do_not_create_updates(self):
        rows=[{'time_s':str(n/60),'frame_id':'7','mode':'CORRECTED'} for n in range(61)]
        r=metrics.analyze_display_samples(rows)
        self.assertEqual(r['observed_new_display_events'],0)
        self.assertEqual(r['observed_change_rate_hz'],0)
        self.assertEqual(r['samples'],61)

    def test_sparse_sampling_is_not_sensor_fps_or_true_latency(self):
        rows=[{'time_s':str(t),'frame_id':str(i),'mode':'CORRECTED'} for t,i in [(0,4),(.1,4),(.2,12),(.3,12),(.4,90)]]
        r=metrics.analyze_display_samples(rows)
        self.assertEqual(r['observed_new_display_events'],2)
        self.assertEqual(r['source_id_steps_not_output_frames'],86)
        self.assertAlmostEqual(r['observed_change_rate_hz'],5)
        self.assertIsNone(r['end_to_end_latency_s'])
        self.assertFalse(r['hardware_acceptance'])

    def test_nonmonotonic_sample_time_and_id_rejected(self):
        for pair in [[('1','2'),('1','3')],[('1','5'),('2','4')]]:
            with self.assertRaises(ValueError):metrics.analyze_display_samples([dict(time_s=t,frame_id=i,mode='CORRECTED') for t,i in pair])

if __name__=='__main__':unittest.main()
