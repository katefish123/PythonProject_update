import dataclasses
import json
import math
from pathlib import Path
import random
import tempfile
import unittest

try:
    from lens_golden import Profile, FrameMap, load_profile
except ImportError:
    Profile = FrameMap = load_profile = None

class LensTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(Profile, "lens golden implementation is missing")

    def profile(self, **kw):
        values=dict(width=640,height=480,fx=200.,fy=100.,cx=300.,cy=200.,k1=0.,k2=0.,p1=0.,p2=0.,profile_id="synthetic-test", provenance="synthetic")
        values.update(kw)
        return Profile(**values)

    def test_identity_and_source_boundary(self):
        f=FrameMap(self.profile())
        for u,v in [(0,0),(639,479),(300,200),(20.25,400.5)]:
            r=f.map(u,v);self.assertAlmostEqual(r.x,u);self.assertAlmostEqual(r.y,v);self.assertTrue(r.inside)
        self.assertFalse(f.map(640,200).inside)

    def test_radial_k1_analytic_sign(self):
        for k,expected in [(.1,520.),(-.1,480.)]:
            r=FrameMap(self.profile(k1=k)).map(500,200)
            self.assertAlmostEqual(r.x,expected);self.assertEqual(r.y,200.)

    def test_radial_k2_analytic(self):
        r=FrameMap(self.profile(k2=.2)).map(400,250)
        self.assertAlmostEqual(r.x,405.);self.assertAlmostEqual(r.y,252.5)

    def test_tangent_p1_axes_and_sign(self):
        for p in [.1,-.1]:
            r=FrameMap(self.profile(p1=p)).map(500,200)
            self.assertAlmostEqual(r.x,500.);self.assertAlmostEqual(r.y,200+100*p)
            r=FrameMap(self.profile(p1=p)).map(300,300)
            self.assertAlmostEqual(r.x,300.);self.assertAlmostEqual(r.y,300+300*p)

    def test_tangent_p2_axes_and_sign(self):
        for p in [.1,-.1]:
            r=FrameMap(self.profile(p2=p)).map(500,200)
            self.assertAlmostEqual(r.x,500+600*p);self.assertAlmostEqual(r.y,200.)
            r=FrameMap(self.profile(p2=p)).map(300,300)
            self.assertAlmostEqual(r.x,300+200*p);self.assertAlmostEqual(r.y,300.)

    def test_independently_expanded_polynomial(self):
        p=self.profile(k1=-.13,k2=.04,p1=.017,p2=-.009);f=FrameMap(p)
        rng=random.Random(1015)
        for _ in range(600):
            u=rng.uniform(0,639);v=rng.uniform(0,399);x=(u-p.cx)/p.fx;y=(v-p.cy)/p.fy
            # Expanded monomials, without calling the production polynomial.
            xd=x+p.k1*(x**3+x*y*y)+p.k2*(x**5+2*x**3*y*y+x*y**4)+2*p.p1*x*y+p.p2*(3*x*x+y*y)
            yd=y+p.k1*(y**3+y*x*x)+p.k2*(y**5+2*y**3*x*x+y*x**4)+p.p1*(x*x+3*y*y)+2*p.p2*x*y
            r=f.map(u,v);self.assertAlmostEqual(r.x,p.fx*xd+p.cx,places=10);self.assertAlmostEqual(r.y,p.fy*yd+p.cy,places=10)

    def test_h_composition_order(self):
        p=self.profile(k1=.1)
        f=FrameMap(p,[1,0,100,0,1,0,0,0,1])
        self.assertAlmostEqual(f.map(400,200).x,520.)
        # Translation after lens would instead yield 502.5.
        g=FrameMap(p,[2,0,0,0,2,0,0,0,2])
        self.assertEqual(g.map(500,200),FrameMap(p).map(500,200))

    def test_frame_snapshot_immutable(self):
        p=self.profile();h=[1,0,0,0,1,0,0,0,1];f=FrameMap(p,h);before=f.map(500,200)
        h[2]=100
        self.assertEqual(f.map(500,200),before)
        with self.assertRaises(dataclasses.FrozenInstanceError):p.k1=.1
        with self.assertRaises(dataclasses.FrozenInstanceError):f.profile=self.profile(k1=.1)
        self.assertNotEqual(FrameMap(self.profile(k1=.1)).map(500,200),before)

    def test_profile_rejection(self):
        for kw in [dict(width=0),dict(width=4097),dict(width=640.5),dict(width=True),dict(fx=0),dict(fy=-1),dict(cx=-1),dict(cy=480),dict(k1=1.1),dict(k2=-1.1),dict(p1=.3),dict(p2=float("nan")),dict(fx=float("inf")),dict(provenance="measured"),dict(profile_id="")]:
            with self.subTest(kw=kw),self.assertRaises(ValueError):self.profile(**kw)

    def test_coordinate_and_h_rejection(self):
        f=FrameMap(self.profile())
        for xy in [(math.nan,0),(0,math.inf),(10000,0),(True,0)]:
            with self.subTest(xy=xy),self.assertRaises(ValueError):f.map(*xy)
        for h in [[1], [math.nan]*9,[1,0,0,0,1,0,0,0,0],[1,0,0,0,1,0,0,0,-1]]:
            with self.subTest(h=h),self.assertRaises(ValueError):FrameMap(self.profile(),h).map(1,1)

    def test_load_synthetic_profile_and_size_match(self):
        p=self.profile()
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"p.json";path.write_text(json.dumps(dataclasses.asdict(p)))
            self.assertEqual(load_profile(path,(640,480)),p)
            with self.assertRaises(ValueError):load_profile(path,(320,240))
            data=dataclasses.asdict(p);data["unknown"]=1;path.write_text(json.dumps(data))
            with self.assertRaises(ValueError):load_profile(path,(640,480))

if __name__ == "__main__":unittest.main()
