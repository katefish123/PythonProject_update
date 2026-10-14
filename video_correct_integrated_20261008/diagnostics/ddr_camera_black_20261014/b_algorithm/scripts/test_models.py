import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
import numpy as np
from brect.golden import CORNERS, homography, map_float, detect_markers, rectify_float
from brect.fixed import solve_fixed,map_fixed,sample_fixed,interpolate,rectify_fixed,addresses,trunc_div,S,T


class Models(unittest.TestCase):
    def test_identity_both_samplers(self):
        im=np.random.default_rng(4).integers(0,256,(12,16,3),dtype=np.uint8)
        p=[(0,0),(15,0),(15,11),(0,11)]
        for method in ("nearest","bilinear"):
            fp,_=rectify_float(im,p,16,12,method);fx,_=rectify_fixed(im,p,16,12,method)
            np.testing.assert_array_equal(fp,im);np.testing.assert_array_equal(fx,im)

    def test_corners_and_interior(self):
        rng=np.random.default_rng(67)
        worst=0.
        for _ in range(80):
            p=[(rng.integers(5,20),rng.integers(5,20)),(rng.integers(90,120),rng.integers(5,25)),
               (rng.integers(85,120),rng.integers(70,90)),(rng.integers(2,25),rng.integers(65,90))]
            hf=homography(p,64,48);hq=solve_fixed(p,64,48,128,96)
            for x,y in [(0,0),(63,0),(63,47),(0,47)]+[(int(rng.integers(64)),int(rng.integers(48))) for _ in range(30)]:
                a,b,v=map_float(hf,x,y);qx,qy,qv=map_fixed(hq,x,y)
                self.assertTrue(v and qv)
                worst=max(worst,abs(a-qx/T),abs(b-qy/T))
            for (x,y),pt in zip([(0,0),(63,0),(63,47),(0,47)],p):
                a,b,_=map_float(hf,x,y);np.testing.assert_allclose([a,b],pt,atol=1e-9)
        self.assertLess(worst,.01)

    def test_hd_corner_precision(self):
        p=[(203,114),(1697,183),(1802,974),(121,1002)]
        hf=homography(p,1280,720);hq=solve_fixed(p,1280,720,1920,1080)
        worst=0.
        for y in range(0,720,19):
            for x in range(0,1280,23):
                a,b,_=map_float(hf,x,y);qx,qy,v=map_fixed(hq,x,y)
                self.assertTrue(v);worst=max(worst,abs(a-qx/T),abs(b-qy/T))
        self.assertLess(worst,.25)

    def test_interpolation_weights(self):
        p=np.asarray([[0,100,255],[255,20,0],[80,255,10],[200,40,120]],np.uint8)
        np.testing.assert_array_equal(interpolate(p,0,0),p[0])
        np.testing.assert_array_equal(interpolate(p,128,128),p.astype(int).sum(axis=0)//4)
        for value in [0,1,128,254,255]:
            self.assertTrue(np.all(interpolate(np.full((4,3),value,np.uint8),255,255)==value))

    def test_border_and_nearest(self):
        im=np.arange(4*5*3,dtype=np.uint8).reshape(4,5,3)
        np.testing.assert_array_equal(sample_fixed(im,4*T,3*T),im[-1,-1])
        self.assertFalse(addresses(4*T+1,0,5,4)[0])
        self.assertTrue(addresses(4*T+127,0,5,4,"nearest")[0])
        self.assertFalse(addresses(4*T+128,0,5,4,"nearest")[0])
        self.assertEqual(addresses(0,0,5,4)[1],[0,1,5,6])

    def test_invalid_geometry(self):
        for p in [[(0,0),(10,0),(0,10),(10,10)],[(0,0)]*4,[(0,0),(1,0),(1,1),(0,1)]]:
            with self.assertRaises(ValueError): solve_fixed(p,8,8)
        with self.assertRaises(ValueError): solve_fixed([(0,0),(10,0),(10,10),(0,10)],1,10)
        with self.assertRaises(ValueError): solve_fixed([(0,0),(10,0),(10,10),(0,10)],10,10,8,8)
        # Highly foreshortened but convex: exceeds allowed g/h envelope.
        with self.assertRaises(ValueError): solve_fixed([(0,0),(4095,0),(2100,100),(2000,100)],100,100)

    def test_bad_denominator_and_ranges(self):
        h=[S,0,0,0,S,0,0,0,S]
        self.assertEqual(map_fixed(h,4095,4095),(4095*T,4095*T,True))
        self.assertFalse(map_fixed(h,4096,0)[2])
        for d in [0,-1,S//16]:
            hh=h[:];hh[8]=d;self.assertFalse(map_fixed(hh,0,0)[2])
        hh=h[:];hh[2]=-1;self.assertFalse(map_fixed(hh,0,0)[2])

    def test_signed_division(self):
        self.assertEqual(trunc_div(-5,2),-2);self.assertEqual(trunc_div(5,-2),-2)
        self.assertEqual(trunc_div(-5,-2),2)

    def test_markers_reject_and_threshold_boundary(self):
        im=np.full((48,64,3),180,np.uint8)
        pts=[(10,8),(52,13),(56,40),(7,38)]
        colors=[(64,0,0),(0,64,0),(0,0,64),(64,64,64)]
        for (x,y),c in zip(pts,colors):im[y-2:y+3,x-2:x+3]=c
        p,_=detect_markers(im);np.testing.assert_array_equal(p,pts)
        im[0:5,0:5]=colors[0]
        self.assertIsNone(detect_markers(im,max_span=10)[0])
        im[:]=180;self.assertIsNone(detect_markers(im)[0])

    def test_invalid_rgb_and_legacy_thresholds(self):
        p=[(0,0),(15,0),(15,11),(0,11)]
        for image in [np.zeros((12,16),np.uint8),np.zeros((12,16,3),float),np.zeros((0,16,3),np.uint8)]:
            for function in (rectify_float,rectify_fixed):
                with self.assertRaises(ValueError):function(image,p,16,12)
        im=np.full((12,16,3),200,np.uint8)
        with self.assertRaises(ValueError):
            detect_markers(im,{"red":((0,0,0),(255,255,255))})

    def marker_scene(self, shape=(48,64), points=None, color=0):
        points=points or [(10,8),(52,13),(56,40),(7,38)]
        image=np.full((*shape,3),180,np.uint8)
        for x,y in points:image[y-2:y+3,x-2:x+3]=color
        return image,points

    def test_black_markers_and_statistics(self):
        image,points=self.marker_scene()
        found,stats=detect_markers(image)
        np.testing.assert_array_equal(found,points)
        self.assertEqual(list(stats),["TL","TR","BR","BL"])
        for name in stats:
            self.assertEqual(stats[name]["count"],25)
            self.assertEqual(stats[name]["span"],(4,4))

    def test_black_single_channel_above_threshold(self):
        for channel in range(3):
            image,_=self.marker_scene()
            color=[0,0,0];color[channel]=65
            image[6:11,8:13]=color
            self.assertIsNone(detect_markers(image)[0])

    def test_colored_markers_are_rejected(self):
        image,points=self.marker_scene()
        for (x,y),color in zip(points,[(160,0,0),(0,140,0),(160,140,0),(0,0,160)]):
            image[y-2:y+3,x-2:x+3]=color
        self.assertIsNone(detect_markers(image)[0])

    def test_custom_rois_exclude_black_text(self):
        image,points=self.marker_scene()
        image[20:28,20:44]=0
        rois={name:[[x-3,y-3],[x+3,y+3]] for name,(x,y) in zip(CORNERS,points)}
        self.assertIsNone(detect_markers(image,max_span=10)[0])
        np.testing.assert_array_equal(detect_markers(image,rois=rois)[0],points)

    def test_roi_inclusive_edges_odd_dimensions(self):
        image,points=self.marker_scene((49,65),[(2,2),(62,2),(62,46),(2,46)])
        # The marker blocks include the first/last source pixel.
        np.testing.assert_array_equal(detect_markers(image)[0],points)
        rois={name:[[x-2,y-2],[x+2,y+2]] for name,(x,y) in zip(CORNERS,points)}
        np.testing.assert_array_equal(detect_markers(image,rois=rois)[0],points)

    def test_marker_area_limits_and_rounding(self):
        image,_=self.marker_scene()
        self.assertIsNone(detect_markers(image,max_pixels=24)[0])
        self.assertIsNone(detect_markers(image,min_pixels=26)[0])
        image[:]=180
        for x,y in [(4,4),(52,4),(52,36),(4,36)]:image[y:y+4,x:x+4]=0
        np.testing.assert_array_equal(detect_markers(image)[0],[(6,6),(54,6),(54,38),(6,38)])

    def test_invalid_black_configuration(self):
        image,points=self.marker_scene()
        for thresholds in [{}, {"black":[[-1,0,0],[64,64,64]]},
                           {"black":[[0,0,0],[256,64,64]]}, {"black":[[65,0,0],[64,64,64]]},
                           {"black":[[0.0,0,0],[64,64,64]]}]:
            with self.assertRaises(ValueError):detect_markers(image,thresholds)
        rois={name:[[x-3,y-3],[x+3,y+3]] for name,(x,y) in zip(CORNERS,points)}
        for invalid in [{},dict(rois,TR=rois["TL"]),dict(rois,TL=[[-1,0],[10,10]]),
                        dict(rois,TL=[[5,5],[4,10]]),dict(rois,BR=[[50,30],[64,47]])]:
            with self.assertRaises(ValueError):detect_markers(image,rois=invalid)
        for kwargs in [{"min_pixels":0},{"max_pixels":15},{"max_span":-1}]:
            with self.assertRaises(ValueError):detect_markers(image,**kwargs)


if __name__=="__main__": unittest.main()
