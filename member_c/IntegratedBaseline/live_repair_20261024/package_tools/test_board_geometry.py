import unittest
import numpy as np
import board_geometry as geometry

class BoardGeometryTests(unittest.TestCase):
    def grid(self):
        x,y=np.meshgrid(np.arange(9)*20.0,np.arange(6)*20.0)
        return np.stack([x,y],axis=-1)+[300,200]

    def test_perspective_of_planar_grid_preserves_straight_lines(self):
        p=self.grid();h=np.array([[1,.2,5],[.1,1,8],[.0008,.0004,1]])
        q=np.concatenate([p,np.ones((6,9,1))],axis=2)@h.T
        r=geometry.measure_grid(q[:,:,:2]/q[:,:,2:])
        self.assertLess(r['worst_line_rms_px'],1e-10)

    def test_bowed_lines_are_detected(self):
        p=self.grid();p[:,:,1]+=.002*(p[:,:,0]-380)**2
        self.assertGreater(geometry.measure_grid(p)['worst_line_rms_px'],1)

    def test_scale_independent_score_is_unchanged(self):
        p=self.grid();p[:,:,1]+=.002*(p[:,:,0]-380)**2
        a=geometry.measure_grid(p);b=geometry.measure_grid(p*2)
        self.assertAlmostEqual(b['worst_line_rms_px'],2*a['worst_line_rms_px'])
        self.assertAlmostEqual(a['normalized_worst_line_rms'],b['normalized_worst_line_rms'])

    def test_invalid_or_collapsed_board_is_rejected(self):
        for points in [np.zeros((6,9,2)),np.full((6,9,2),np.nan),np.zeros((1,9,2))]:
            with self.assertRaises(ValueError):geometry.measure_grid(points)

if __name__=='__main__':unittest.main()
