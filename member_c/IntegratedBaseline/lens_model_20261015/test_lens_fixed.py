import random
import unittest
from lens_golden import Profile,FrameMap
try:
    from lens_fixed import FixedFrameMap,NumericReject,round_ratio,SCALE
except ImportError:
    FixedFrameMap=NumericReject=round_ratio=SCALE=None


class FixedLensTests(unittest.TestCase):
    def setUp(self):self.assertIsNotNone(FixedFrameMap,'fixed model is not implemented')

    def profile(self,**overrides):
        values=dict(width=1920,height=1080,fx=913.7,fy=901.55,cx=960.25,cy=539.75,
                    k1=0.,k2=0.,p1=0.,p2=0.,profile_id='synthetic-fixed',provenance='synthetic')
        values.update(overrides);return Profile(**values)

    def test_signed_ties_to_even(self):
        for numerator,expected in [(1,0),(3,2),(5,2),(7,4),(-1,0),(-3,-2),(-5,-2),(-7,-4)]:
            self.assertEqual(round_ratio(numerator,2),expected)
            self.assertEqual(round_ratio(-numerator,-2),expected)

    def test_zero_distortion_exact_identity_edges(self):
        frame=FixedFrameMap(self.profile())
        for x,y in [(0,0),(1919,0),(0,1079),(1919,1079),(960,540)]:
            result=frame.map(x,y)
            self.assertEqual((result.x_q,result.y_q,result.inside),(x*SCALE,y*SCALE,True))

    def test_h_before_lens_and_signed_outside(self):
        profile=self.profile(k1=-.2,k2=.04,p1=.003,p2=-.004)
        h=(1.04,.01,-100.,.02,1.01,-50.,.00001,-.00002,1.)
        fixed=FixedFrameMap(profile,h);gold=FrameMap(profile,h)
        for x,y in [(0,0),(1919,1079),(500,300),(1500,800)]:
            got,expected=fixed.map(x,y),gold.map(x,y)
            self.assertLess(abs(got.x_q/SCALE-expected.x),.125)
            self.assertLess(abs(got.y_q/SCALE-expected.y),.125)
            self.assertEqual(got.inside,expected.inside)

    def test_synthetic_operating_set_error(self):
        rng=random.Random(20261015);maximum=0.;checked=0
        for n in range(40):
            profile=self.profile(k1=rng.uniform(-.3,.3),k2=rng.uniform(-.15,.15),p1=rng.uniform(-.01,.01),p2=rng.uniform(-.01,.01))
            h=(rng.uniform(.9,1.1),rng.uniform(-.02,.02),rng.uniform(-20,20),rng.uniform(-.02,.02),rng.uniform(.9,1.1),rng.uniform(-20,20),rng.uniform(-.00002,.00002),rng.uniform(-.00002,.00002),1.)
            fixed=FixedFrameMap(profile,h);gold=FrameMap(profile,h)
            for _ in range(125):
                x,y=rng.randrange(1920),rng.randrange(1080)
                got,expected=fixed.map(x,y),gold.map(x,y)
                error=max(abs(got.x_q/SCALE-expected.x),abs(got.y_q/SCALE-expected.y))
                maximum=max(maximum,error);checked+=1
                self.assertLess(error,.125)
                margin=min(abs(expected.x),abs(expected.y),abs(expected.x-1919),abs(expected.y-1079))
                if margin>error:self.assertEqual(got.inside,expected.inside)
        self.assertEqual(checked,5000)
        print(f'FIXED_SYNTHETIC_ERROR samples={checked} maximum_source_pixel_error={maximum:.12g}')

    def test_numeric_rejection_is_explicit(self):
        frame=FixedFrameMap(self.profile())
        for x,y in [(-1,0),(4096,0),(1.25,0),(True,0)]:
            with self.assertRaises(NumericReject):frame.map(x,y)
        with self.assertRaises(NumericReject):FixedFrameMap(self.profile(),h=(1,0,0,0,1,0,0,0,.01)).map(1,1)
        with self.assertRaises(NumericReject):FixedFrameMap(self.profile(fx=1,fy=1,cx=0,cy=0),h=(65536,0,0,0,65536,0,0,0,1)).map(4095,4095)

    def test_quantization_retains_signed_bounds(self):
        frame=FixedFrameMap(self.profile(),h=(1,0,-.125,0,1,0,0,0,1))
        got=frame.map(0,0)
        self.assertFalse(got.inside);self.assertLess(got.x_q,0)
        self.assertEqual(got.x_q//(1<<22),-32)


if __name__=='__main__':unittest.main()
