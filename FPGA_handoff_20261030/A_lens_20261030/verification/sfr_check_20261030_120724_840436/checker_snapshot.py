"""Analytic synthetic self-checks; these images are NOT camera measurements."""
from __future__ import annotations

import datetime
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import traceback

import cv2
import numpy as np

import slanted_edge_sfr as sfr


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def gaussian_edge(sigma, angle, *, transpose=False, falling=False):
    """Continuous isotropic Gaussian PSF, sampled at pixel centers, no aperture."""
    yy, xx = np.mgrid[:256, :256]
    slope = math.tan(math.radians(angle))
    distance = (xx - 127.37 - slope * (yy - 127.5)) / math.sqrt(1 + slope * slope)
    cdf = np.fromiter((0.5 * (1 + math.erf(v / (math.sqrt(2) * sigma)))
                       for v in distance.flat), dtype=float, count=distance.size).reshape(distance.shape)
    if falling:
        cdf = 1 - cdf
    if transpose:
        cdf = cdf.T
    return 0.15 + 0.60 * cdf


def main():
    base = Path(__file__).resolve().parent.parent
    source = Path(sfr.__file__).resolve()
    checker = Path(__file__).resolve()
    out = base / 'verification' / ('sfr_check_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir(parents=True)
    print('SFR_SELF_CHECK ' + str(out), flush=True)
    shutil.copyfile(checker, out / 'checker_snapshot.py')
    shutil.copyfile(source, out / 'slanted_edge_sfr_snapshot.py')
    cases, errors, files = [], [], []
    log_lines = []
    tolerance = 0.04

    def log(message):
        log_lines.append(message)

    def png(name, image, bits=16):
        path = out / (name + '.png')
        limit = 2 ** bits - 1
        dtype = np.uint16 if bits == 16 else np.uint8
        samples = np.rint(np.clip(image, 0, 1) * limit).astype(dtype)
        ok, data = cv2.imencode('.png', samples)
        assert ok
        path.write_bytes(data.tobytes())
        files.append(path)
        return path

    def accept(name, path, sigma, orientation, transfer='linear'):
        result = sfr.analyze_png(path, [24, 24, 208, 208], orientation=orientation, transfer=transfer)
        measured = result['mtf50_cycles_per_pixel']
        expected = math.sqrt(math.log(2)) / (math.sqrt(2) * math.pi * sigma)
        relative = abs(measured / expected - 1)
        assert result['sfr_dc_normalized'][0] == 1.0
        assert result['oversampling'] == 4 and result['iso_certified'] is False
        assert result['input_sha256'] == sha(path)
        assert max(result['derivative_correction']) > 1.10
        assert relative <= tolerance, (name, measured, expected, relative)
        record = {'name': name, 'kind': 'analytic_synthetic_gaussian', 'passed': True,
                  'input_file': str(path), 'orientation': orientation, 'transfer': transfer,
                  'sigma_normal_pixels': sigma, 'expected_mtf50_cycles_per_pixel': expected,
                  'estimated_mtf50_cycles_per_pixel': measured, 'relative_error': relative,
                  'relative_tolerance': tolerance, 'quality': result['quality']}
        cases.append(record)
        log(f'PASS {name} expected={expected:.8f} estimated={measured:.8f} relative_error={relative:.6f}')
        return result

    def reject(name, path, roi, orientation='vertical', transfer='linear', codes=None):
        try:
            sfr.analyze_png(path, roi, orientation=orientation, transfer=transfer)
        except sfr.SfrError as error:
            if codes:
                assert error.code in codes, (name, error.code, codes)
            cases.append({'name': name, 'kind': 'expected_rejection', 'passed': True,
                          'input_file': str(path), 'roi': roi, 'error_code': error.code, 'reason': str(error)})
            log(f'PASS rejection {name}: {error.code}')
        else:
            raise AssertionError(name + ' must be rejected')

    try:
        reference_images = []
        for i, (sigma, angle) in enumerate([(0.7, 3.2), (1.2, -5.7), (2.0, 8.1), (3.0, -10.2)]):
            for horizontal in [False, True]:
                name = f'gaussian_s{sigma}_' + ('horizontal' if horizontal else 'vertical')
                image = gaussian_edge(sigma, angle, transpose=horizontal, falling=(i % 2 == 1))
                path = png(name, image)
                accept(name, path, sigma, 'horizontal' if horizontal else 'vertical')
                reference_images.append(path)
        # Non-identical RGB channels test decoding BEFORE linear-luminance mixing.
        edge = (gaussian_edge(1.2, 5.3, transpose=True) - 0.15) / 0.60
        rgb = np.stack([0.10 + 0.60 * edge, 0.20 + 0.60 * edge, 0.12 + 0.53 * edge], axis=2)
        encoded_rgb = np.where(rgb <= 0.0031308, 12.92 * rgb, 1.055 * rgb ** (1 / 2.4) - 0.055)
        encoded_path = png('gaussian_srgb_rgb', encoded_rgb[:, :, ::-1], bits=8)
        srgb_result = accept('srgb_rgb_decode', encoded_path, 1.2, 'horizontal', 'srgb')
        # The CLI must preserve a useful result/rejection and fail closed.
        for name, extra, expected_status in [
            ('cli_accept', ['--roi', '24', '24', '208', '208', '--orientation', 'horizontal', '--transfer', 'srgb'], 0),
            ('cli_bad_roi', ['--roi', '-1', '0', '64', '64', '--orientation', 'vertical', '--transfer', 'linear'], 2),
            ('cli_missing_transfer', ['--roi', '24', '24', '208', '208', '--orientation', 'horizontal'], 2),
        ]:
            process = subprocess.run([sys.executable, str(source), str(encoded_path), *extra],
                                     capture_output=True, text=True)
            assert process.returncode == expected_status, (name, process.stderr)
            if name == 'cli_accept':
                parsed = json.loads(process.stdout)
                assert parsed['mtf50_cycles_per_pixel'] == srgb_result['mtf50_cycles_per_pixel']
            elif name == 'cli_bad_roi':
                assert json.loads(process.stdout)['accepted'] is False
                assert 'mtf50_cycles_per_pixel' not in json.loads(process.stdout)
            cases.append({'name': name, 'kind': 'cli_contract', 'passed': True, 'return_code': process.returncode})
            log('PASS ' + name)
        flat = png('reject_blank', np.full((256, 256), 0.4))
        yy, xx = np.mgrid[:256, :256]
        d = xx - 127.4 - math.tan(math.radians(5)) * (yy - 127.5)
        stripe = png('reject_multiple_edges', 0.15 + 0.60 * ((d > -25) & (d < 25)))
        corner = png('reject_checkerboard_corner', 0.15 + 0.60 * ((d >= 0) == (yy >= 127)))
        axis = png('reject_axis_aligned', gaussian_edge(1.2, 0))
        excessive = png('reject_large_angle', gaussian_edge(1.2, 25))
        reject('blank', flat, [24, 24, 208, 208], codes={'contrast'})
        reject('multiple_edges', stripe, [24, 24, 208, 208], codes={'contrast', 'multiple_edges'})
        reject('checkerboard_corner', corner, [24, 24, 208, 208], codes={'edge_polarity', 'contrast', 'multiple_edges'})
        reject('axis_aligned', axis, [24, 24, 208, 208], codes={'edge_angle'})
        reject('too_large_angle', excessive, [24, 24, 208, 208], codes={'edge_angle'})
        good = reference_images[0]
        reject('out_of_bounds', good, [200, 20, 100, 100], codes={'roi'})
        reject('negative_roi', good, [-1, 24, 100, 100], codes={'roi'})
        reject('too_small_roi', good, [100, 100, 32, 32], codes={'roi_size'})
        reject('wrong_roi_no_edge', good, [0, 24, 64, 208], codes={'contrast'})
        reject('wrong_orientation', good, [24, 24, 208, 208], orientation='horizontal')
        reject('unspecified_transfer', good, [24, 24, 208, 208], transfer='unknown', codes={'transfer'})
        log('SFR_SELF_CHECK_PASS synthetic_only=1 hardware_accessed=0')
    except Exception:
        errors.append(traceback.format_exc())
        log(errors[-1])
    log_path = out / 'check.log'
    log_path.write_text('\n'.join(log_lines) + '\n', encoding='utf-8')
    inputs = {'scope': 'Analytic synthetic images only; NOT hardware/camera measurement or ISO certification.',
              'target_source': str(source), 'target_source_sha256': sha(source),
              'checker_sha256': sha(checker),
              'input_sha256': {str(p): sha(p) for p in [source, checker, *files]},
              'environment': {'python': sys.version, 'numpy': np.__version__, 'opencv': cv2.__version__},
              'gaussian_mtf': 'exp(-2*pi^2*sigma^2*f^2)',
              'gaussian_mtf50': 'sqrt(log(2))/(sqrt(2)*pi*sigma)',
              'synthetic_sampling': 'continuous Gaussian-blurred ideal step at pixel centers; no pixel aperture integration',
              'relative_mtf50_tolerance': tolerance}
    manifest = out / 'inputs.json'
    manifest.write_text(json.dumps(inputs, indent=2), encoding='utf-8')
    assert sha(checker) == sha(out / 'checker_snapshot.py')
    assert sha(source) == sha(out / 'slanted_edge_sfr_snapshot.py')
    result = {'passed': not errors, 'synthetic_only': True, 'hardware_accessed': False, 'iso_certified': False,
              'input_manifest_sha256': sha(manifest), 'log_sha256': sha(log_path),
              'cases': cases, 'failures': errors}
    (out / 'verification.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'directory': str(out), 'passed': result['passed'], 'cases': len(cases),
                      'failures': errors, 'maximum_relative_mtf50_error': max((x.get('relative_error', 0) for x in cases), default=None)}, indent=2))
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
