"""Focused lens contract checks; OpenCV is used only as an optional oracle."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from brect.calibration import load_calibration
from brect.lens import map_lens_float, map_lens_fixed, render_lens_float, render_lens_fixed
from brect.fixed import sample_fixed


def document(width=16, height=12, distortion=(0., 0., 0., 0.)):
    fx, fy, cx, cy = 20., 21., 7., 5.
    model = dict(zip(("fx", "fy", "cx", "cy"), (fx, fy, cx, cy)))
    model.update(zip(("k1", "k2", "p1", "p2"), distortion))
    model.update(K=[[fx, 0., cx], [0., fy, cy], [0., 0., 1.]],
                 distortion_opencv_order=list(distortion) + [0.], k3_fixed=0.)
    return {"video": {"width": width, "height": height}, "model": model,
            "deploy_to_fpga": False, "status": "trial", "limitations": ["test profile"]}


class LensContract(unittest.TestCase):
    def profile(self, doc=None):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "profile.json"
            path.write_text(json.dumps(document() if doc is None else doc))
            return load_calibration(path)

    def test_real_profile_and_metadata(self):
        profile = load_calibration(ROOT / "calibration/r50_18mm_hdmi_trial.json", (1920, 1080))
        self.assertEqual((profile.width, profile.height), (1920, 1080))
        self.assertFalse(profile.metadata["deploy_to_fpga"])
        self.assertEqual(set(profile.to_hardware()), {
            "FX_Q16", "FY_Q16", "CX_Q16", "CY_Q16", "INV_FX_Q30", "INV_FY_Q30",
            "K1_Q26", "K2_Q26", "P1_Q26", "P2_Q26"})

    def test_parser_rejects_inconsistent_and_unsupported(self):
        mutations = [lambda d: d["model"].update(fx=23.),
                     lambda d: d["model"]["K"][0].__setitem__(1, .1),
                     lambda d: d["model"]["K"][2].__setitem__(0, .1),
                     lambda d: d["model"].update(k1=float("nan")),
                     lambda d: d["model"]["distortion_opencv_order"].__setitem__(4, .01),
                     lambda d: d["model"].update(k3_fixed=.1),
                     lambda d: d["video"].update(width=16.5),
                     lambda d: d["video"].update(width=True)]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                data = document(); mutate(data)
                with self.assertRaises(ValueError): self.profile(data)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "profile.json"; path.write_text(json.dumps(document()))
            with self.assertRaises(ValueError): load_calibration(path, (12, 16))
            path.write_text('{"video": {}, "video": {}}')
            with self.assertRaises(ValueError): load_calibration(path)

    def test_hardware_ties_and_limits(self):
        data = document(distortion=(.5 / (1 << 26), -.5 / (1 << 26), 0., 0.))
        hardware = self.profile(data).to_hardware()
        self.assertEqual((hardware["K1_Q26"], hardware["K2_Q26"]), (1, -1))
        with self.assertRaises(ValueError): self.profile(document(distortion=(2.001, 0, 0, 0))).to_hardware()
        data = document(); data["model"]["K"][0][0] = data["model"]["fx"] = 40000.
        with self.assertRaises(ValueError): self.profile(data).to_hardware()

    def test_zero_exact_identity_and_error_propagation(self):
        profile = self.profile()
        for x, y in [(0, 0), (4095 * 256 + 255, 13), (-17, 256)]:
            self.assertEqual(map_lens_fixed(profile, x, y), (x, y, True))
        with self.assertRaises(ValueError): map_lens_fixed(profile, 1.5, 2)
        self.assertEqual(map_lens_fixed(profile, 31, 64, in_error=True), (0, 0, False))
        image = np.random.default_rng(18).integers(0, 256, (12, 16, 3), dtype=np.uint8)
        for method in ("nearest", "bilinear"):
            np.testing.assert_array_equal(render_lens_fixed(image, profile, method=method), image)
            np.testing.assert_array_equal(render_lens_float(image, profile, method=method), image)

    def test_float_opencv_oracle(self):
        try:
            import cv2
        except ImportError:
            self.skipTest("Optional OpenCV oracle unavailable")
        profile = self.profile(document(distortion=(.1, -.04, .01, -.02)))
        u, v = np.meshgrid(np.linspace(0, 15, 9), np.linspace(0, 11, 7))
        sx, sy, valid = map_lens_float(profile, u, v)
        points = np.stack(((u - profile.cx) / profile.fx,
                           (v - profile.cy) / profile.fy, np.ones_like(u)), axis=-1).reshape(-1, 3)
        k = np.array([[profile.fx, 0, profile.cx], [0, profile.fy, profile.cy], [0, 0, 1.]])
        expected, _ = cv2.projectPoints(points, np.zeros(3), np.zeros(3), k,
                                        np.array([profile.k1, profile.k2, profile.p1, profile.p2, 0.]))
        np.testing.assert_allclose(np.stack((sx, sy), axis=-1).reshape(-1, 2), expected[:, 0], atol=1e-11)
        self.assertTrue(valid.all())

    def test_float_fixed_accuracy(self):
        profile = self.profile(document(distortion=(.1, -.04, .01, -.02)))
        for x, y in [(i * 213, j * 217) for i in range(19) for j in range(14)]:
            a, b, good = map_lens_float(profile, x / 256., y / 256.)
            qx, qy, qgood = map_lens_fixed(profile, x, y)
            self.assertEqual(good, qgood)
            self.assertLess(max(abs(a - qx / 256.), abs(b - qy / 256.)), .004)

    def test_domain_bypass_negative_border_and_combined_single_sample(self):
        profile = self.profile(document(distortion=(.1, -.04, .01, -.02)))
        self.assertEqual(map_lens_fixed(profile, 1000000, 0), (0, 0, False))
        self.assertEqual(map_lens_fixed(profile, 1000000, 0, enabled=False), (1000000, 0, True))
        sx, sy, valid = map_lens_fixed(profile, 0, 0)
        self.assertTrue(valid)
        self.assertLess(min(sx, sy), 0)  # Valid geometry outside the frame is not an error.
        self.assertFalse(map_lens_float(profile, float("nan"), 0)[2])
        image = np.arange(12 * 16 * 3, dtype=np.uint8).reshape(12, 16, 3)
        h = np.array([[.75, 0., 1.25], [0., .75, 1.5], [0., 0., 1.]])
        output = render_lens_fixed(image, profile, H=h, output_size=(8, 6))
        for y in range(6):
            for x in range(8):
                qx, qy, good = map_lens_fixed(profile, int((.75 * x + 1.25) * 256),
                                            int((.75 * y + 1.5) * 256))
                expected = sample_fixed(image, qx, qy) if good else np.zeros(3, np.uint8)
                np.testing.assert_array_equal(output[y, x], expected)
        zero = self.profile()
        for method in ("nearest", "bilinear"):
            h = np.array([[1, 0, -1], [0, 1, 0], [0, 0, 1.]])
            np.testing.assert_array_equal(render_lens_float(image, zero, H=h, method=method)[:, 0], 0)
            bad = np.eye(3); bad[2, 2] = 0
            np.testing.assert_array_equal(render_lens_fixed(image, zero, H=bad), 0)
        with self.assertRaises(ValueError): render_lens_float(image[:10], zero)
        with self.assertRaises(ValueError): render_lens_fixed(image, zero, method="cubic")

    def test_cli_and_export_preserve_provisional_status(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            calibration, source = tmp / "profile.json", tmp / "source.png"
            calibration.write_text(json.dumps(document()))
            image = np.arange(12 * 16 * 3, dtype=np.uint8).reshape(12, 16, 3)
            Image.fromarray(image).save(source)
            environment = dict(os.environ, PYTHONPATH=str(ROOT / "python"), PYTHONDONTWRITEBYTECODE="1")
            process = subprocess.run([sys.executable, "-B", "-m", "brect.lens_cli", str(source),
                                      "--calibration", str(calibration), "--output", str(tmp / "result")],
                                     env=environment, capture_output=True, text=True)
            self.assertEqual(process.returncode, 0, process.stderr)
            for name in ("float.png", "fixed.png"):
                np.testing.assert_array_equal(np.array(Image.open(tmp / "result" / name)), image)
            report = json.loads((tmp / "result/parameters.json").read_text())
            self.assertFalse(report["calibration_metadata"]["deploy_to_fpga"])
            process = subprocess.run([sys.executable, "-B", str(ROOT / "scripts/export_calibration.py"),
                                      "--calibration", str(calibration), "--output-prefix", str(tmp / "config/lens")],
                                     env=environment, capture_output=True, text=True)
            self.assertEqual(process.returncode, 0, process.stderr)
            hardware = json.loads((tmp / "config/lens.hardware.json").read_text())
            self.assertFalse(hardware["calibration_metadata"]["deploy_to_fpga"])
            include = (tmp / "config/lens.vh").read_text()
            for key in self.profile().to_hardware():
                self.assertIn(f"`define LENS_{key} ", include)


if __name__ == "__main__": unittest.main()
