from pathlib import Path
import sys,unittest,math
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'lens_model_20261015'))
from lens_golden import Profile,FrameMap
from corner_preparation import undistort_point,fit_ideal_h

class CornerPreparationTests(unittest.TestCase):
 def profile(self,coefficients):return Profile(1920,1080,913.7,901.55,960.25,539.75,*coefficients,'synthetic-inverse-test')
 def test_zero_lens_exact_identity(self):
  p=self.profile([0,0,0,0]);self.assertEqual(undistort_point(p,123.25,456.75),(123.25,456.75))
 def test_each_nonzero_coefficient_and_combination_roundtrip(self):
  for coeffs in ([-.12,0,0,0],[0,.04,0,0],[0,0,.004,0],[0,0,0,-.003],[-.12,.04,.004,-.003]):
   p=self.profile(coeffs)
   for x,y in ((300,200),(1650,200),(1600,880),(280,900),(960,540),(700,400)):
    raw=FrameMap(p).map(x,y);u,v=undistort_point(p,raw.x,raw.y)
    self.assertLess(max(abs(u-x),abs(v-y)),1e-6)
 def test_ideal_corner_H_is_distinct_from_raw_corner_H(self):
  p=self.profile([-.16,.06,.006,-.004])
  ideal=[(300.,150.),(1650.,230.),(1570.,920.),(250.,850.)]
  raw=[(q.x,q.y) for q in [FrameMap(p).map(x,y) for x,y in ideal]]
  h,prepared=fit_ideal_h(p,raw,765,1080)
  for got,want in zip(prepared,ideal):self.assertLess(max(abs(got[0]-want[0]),abs(got[1]-want[1])),1e-6)
  for dst,want in zip([(0,0),(764,0),(764,1079),(0,1079)],raw):
   actual=FrameMap(p,h).map(*dst)
   self.assertLess(max(abs(actual.x-want[0]),abs(actual.y-want[1])),1e-6)
  from brect.golden import homography
  raw_h=tuple(homography(raw,765,1080).ravel())
  wrong=FrameMap(p,raw_h).map(320,600);right=FrameMap(p,h).map(320,600)
  self.assertGreater(math.hypot(wrong.x-right.x,wrong.y-right.y),1.)
 def test_bad_or_singular_inverse_is_rejected(self):
  with self.assertRaises(ValueError):undistort_point(self.profile([0,0,0,0]),float('nan'),0)
  p=Profile(1920,1080,100,100,0,0,-1,0,0,0,'synthetic-singular')
  with self.assertRaises(ValueError):undistort_point(p,100,0)
 def test_invalid_target_geometry_rejected(self):
  with self.assertRaises(ValueError):fit_ideal_h(self.profile([0,0,0,0]),[(1,1)]*4,765,1080)

if __name__=='__main__':unittest.main()
