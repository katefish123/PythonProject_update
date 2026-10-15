import unittest
import numpy as np
from generate import solve_h, rectify
class GoldenTests(unittest.TestCase):
 def test_translation_integer_solver(self):
  self.assertEqual(solve_h([(2,3),(8,3),(8,9),(2,9)],7,7,16,16),[1<<24,0,2<<24,0,1<<24,3<<24,0,0,1<<24])
 def test_identity_padding_and_exact_pixels(self):
  image=np.arange(6*8*3,dtype=np.uint8).reshape(6,8,3)
  h=[1<<24,0,0,0,1<<24,0,0,0,1<<24]
  actual=rectify(image,h,8,6,11,1,'bilinear')
  np.testing.assert_array_equal(actual[:,1:9],image)
  self.assertTrue((actual[:,0]==0).all() and (actual[:,9:]==0).all())
 def test_fractional_bilinear_final_truncation(self):
  image=np.repeat(np.array([[0,100],[200,240]],np.uint8)[...,None],3,axis=2)
  h=[1<<23,0,1<<23,0,1<<23,1<<23,0,0,1<<24]
  actual=rectify(image,h,2,2,5,1,'bilinear')
  self.assertEqual(actual[0,1].tolist(),[135]*3)
  self.assertEqual(actual[1,2].tolist(),[240]*3)
 def test_nearest_half_up(self):
  image=np.repeat(np.array([[0,100],[200,240]],np.uint8)[...,None],3,axis=2)
  h=[1<<23,0,1<<23,0,1<<23,1<<23,0,0,1<<24]
  actual=rectify(image,h,2,2,5,1,'nearest')
  self.assertEqual(actual[0,1].tolist(),[240]*3)
 def test_bad_denominator_black(self):
  image=np.full((2,2,3),255,np.uint8)
  h=[1<<24,0,0,0,1<<24,0,0,0,1<<20]
  self.assertFalse(rectify(image,h,2,2,5,1,'bilinear').any())
 def test_negative_signed_division_truncates_zero(self):
  from generate import trunc_div
  self.assertEqual(trunc_div(-7,3),-2)
  self.assertEqual(trunc_div(7,-3),-2)
 def test_degenerate_solver_rejected(self):
  with self.assertRaises(ValueError):solve_h([(2,2)]*4,7,7,16,16)
if __name__=='__main__':unittest.main()

