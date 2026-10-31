"""No-border acceptance uses geometry masks, never the colour of image pixels."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from dataclasses import replace

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'python'))
from brect.calibration import CalibrationProfile, load_calibration
from brect.fixed import map_fixed
from brect.lens import _homography_fixed, _map_hardware, render_lens_float, render_lens_fixed
from brect.viewport import fixed_grid, mapping_mask, plan_viewport


def profile():
    return CalibrationProfile(45., 46., 31., 23., .12, -.04, .015, -.02,
                              64, 48, {'deploy_to_fpga': False})


class ViewportContract(unittest.TestCase):
    def test_integer_grid_matches_scalar_including_wide_products(self):
        rng = np.random.default_rng(1022)
        xx = rng.integers(0, 4096, 180); yy = rng.integers(0, 4096, 180)
        xx[:8] = [0, 1, 31, 63, 64, 1919, 4095, 3]
        yy[:8] = [0, 1, 23, 47, 48, 1079, 4095, 4]
        extreme = CalibrationProfile(16384., 16384., -32767., -32767., 2., 2., 2., 2., 64, 48)
        real=load_calibration(ROOT/'calibration/r50_18mm_hdmi_trial.json')
        for p in [profile(), replace(profile(), k1=0., k2=0., p1=0., p2=0.), extreme, real]:
            for h in [np.eye(3), np.array([[.93,.02,1.],[-.01,.96,2.],[.00003,.00002,1.]]),
                      np.array([[1.,0.,-2.],[0.,1.,0.],[0.,0.,1.]]), np.diag([1.,1.,.0625])]:
                sx, sy, valid = fixed_grid(p, h, xx, yy)
                hw = p.to_hardware(); hh = _homography_fixed(h)
                for index,(x,y) in enumerate(zip(xx,yy)):
                    u,v,good = map_fixed(hh, int(x), int(y))
                    a,b,good = _map_hardware(hw,u,v,in_error=not good)
                    self.assertEqual((int(sx[index]),int(sy[index]),bool(valid[index])),(a,b,good))

    def test_identity_has_no_unnecessary_crop(self):
        p = replace(profile(), k1=0., k2=0., p1=0., p2=0.)
        h, report = plan_viewport(p)
        np.testing.assert_array_equal(h, np.eye(3))
        self.assertEqual(report['zoom'],1.)
        self.assertEqual(report['after']['fixed_outside_pixels'],0)

    def test_cropped_output_is_real_data_for_both_samplers(self):
        p = profile()
        self.assertGreater(int((~mapping_mask(p,np.eye(3))).sum()),0)
        h, report = plan_viewport(p)
        self.assertLess(report['scale'],1.)
        self.assertAlmostEqual(report['viewport'][0][0],report['viewport'][1][1])
        self.assertTrue(mapping_mask(p,h).all())
        self.assertTrue(mapping_mask(p,h,fixed=True).all())
        for method in ['bilinear','nearest']:
            image = np.full((48,64,3),173,np.uint8)
            np.testing.assert_array_equal(render_lens_float(image,p,H=h,method=method),image)
            np.testing.assert_array_equal(render_lens_fixed(image,p,H=h,method=method),image)
        black = np.zeros((48,64,3),np.uint8)
        np.testing.assert_array_equal(render_lens_float(black,p,H=h),black)

    def test_rotated_and_perspective_views_are_verified(self):
        p = profile(); angle=np.deg2rad(20.)
        c,s=np.cos(angle),np.sin(angle);cx,cy=31.5,23.5
        for h in [np.array([[c,-s,cx-c*cx+s*cy],[s,c,cy-s*cx-c*cy],[0.,0.,1.]]),
                  np.array([[.96,.04,-1.],[.02,.98,-1.],[.0003,.0002,1.]])]:
            effective,report=plan_viewport(p,H=h)
            np.testing.assert_allclose(effective,h @ np.asarray(report['viewport']))
            self.assertTrue(mapping_mask(p,effective).all())
            self.assertTrue(mapping_mask(p,effective,fixed=True).all())

    def test_no_usable_region_is_an_explicit_error(self):
        h=np.eye(3);h[0,2]=5000.
        with self.assertRaisesRegex(ValueError,'valid|usable'):plan_viewport(profile(),H=h)
        with self.assertRaises(ValueError):plan_viewport(profile(),output_size=(1,48))
        h[0,0]=np.nan
        with self.assertRaises(ValueError):plan_viewport(profile(),H=h)

    def test_real_1080p_entire_output_has_zero_outside_positions(self):
        p=load_calibration(ROOT/'calibration/r50_18mm_hdmi_trial.json')
        h,report=plan_viewport(p)
        self.assertEqual(report['verified_pixels'],1920*1080)
        self.assertEqual(report['before']['float_outside_pixels'],9735)
        self.assertGreater(report['before']['fixed_outside_pixels'],0)
        self.assertEqual(report['after']['float_outside_pixels'],0)
        self.assertEqual(report['after']['fixed_outside_pixels'],0)
        self.assertFalse(report['calibration_metadata']['deploy_to_fpga'])

    def test_cli_defaults_to_auto_and_exports_matching_hardware(self):
        with tempfile.TemporaryDirectory() as name:
            tmp=Path(name);p=profile()
            document={'video':{'width':64,'height':48}, 'deploy_to_fpga':False,
                      'model':{key:getattr(p,key) for key in ['fx','fy','cx','cy','k1','k2','p1','p2']}}
            document['model']['K']=[[p.fx,0,p.cx],[0,p.fy,p.cy],[0,0,1]]
            document['model']['distortion_opencv_order']=[p.k1,p.k2,p.p1,p.p2,0.]
            (tmp/'cal.json').write_text(json.dumps(document))
            yy,xx=np.indices((48,64))
            image=np.stack([((xx//3+yy//5)%2)*255,
                            np.where(xx>=31,241,17),
                            np.where(yy%7<3,229,(xx*13+yy*19)%256)],axis=-1).astype(np.uint8)
            Image.fromarray(image).save(tmp/'input.png')
            effective,framing=plan_viewport(p)
            self.assertLess(framing['scale'],1.)
            self.assertFalse(np.allclose(effective,np.eye(3)))
            env=dict(os.environ,PYTHONPATH=str(ROOT/'python'),PYTHONDONTWRITEBYTECODE='1')
            command=[sys.executable,'-B','-m','brect.lens_cli',str(tmp/'input.png'),
                     '--calibration',str(tmp/'cal.json'),'--output',str(tmp/'out')]
            result=subprocess.run(command,env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            info=json.loads((tmp/'out/parameters.json').read_text())
            self.assertEqual(info['border_policy'],'auto')
            self.assertEqual(info['framing']['after']['fixed_outside_pixels'],0)
            for kind,renderer in [('float',render_lens_float),('fixed',render_lens_fixed)]:
                expected=renderer(image,p,H=effective,method='bilinear')
                np.testing.assert_array_equal(np.array(Image.open(tmp/f'out/{kind}.png')),expected,
                                              err_msg=f'{kind} CLI must sample the original image once')
            result=subprocess.run(command+['--border','keep'],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            info=json.loads((tmp/'out/parameters.json').read_text())
            self.assertEqual(info['border_policy'],'keep')
            self.assertTrue((np.array(Image.open(tmp/'out/fixed.png'))==0).any())
            result=subprocess.run([sys.executable,'-B',str(ROOT/'scripts/export_lens_viewport.py'),
                                   '--calibration',str(tmp/'cal.json'),'--output-prefix',str(tmp/'safe')],
                                  env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            exported=json.loads((tmp/'safe.json').read_text())
            self.assertEqual(exported['framing']['after']['fixed_outside_pixels'],0)
            header=(tmp/'safe.vh').read_text()
            for key,value in exported['hardware_parameters'].items():
                self.assertIn(f"`define SAFE_{key} 32'sh{value & 0xffffffff:08x}",header)
            for index,value in enumerate(exported['H_q24']):
                self.assertIn(f"`define SAFE_H{index//3}{index%3}_Q24 40'sh{value & ((1<<40)-1):010x}",header)


if __name__=='__main__':unittest.main()
