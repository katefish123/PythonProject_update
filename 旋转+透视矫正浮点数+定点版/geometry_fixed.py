#!/usr/bin/env python3
"""Integer coordinate model for rotation and four-corner perspective mapping."""

import argparse
import importlib
import json
import math
import numbers
from pathlib import Path
import sys
import unittest

import cv2
import numpy as np


class FixedOverflowError(OverflowError):
    """An explicit failure of a declared signed hardware word width."""


def _checked(value, bits, operation):
    """Python integers provide exact intermediates; reject before any narrowing."""
    if not isinstance(value, numbers.Integral):
        raise TypeError(f'{operation} requires integer data, got {type(value).__name__}')
    value = int(value)
    if not -(1 << (bits - 1)) <= value < (1 << (bits - 1)):
        raise FixedOverflowError(f'{operation}: {value} does not fit signed {bits} bits')
    return value


def _add(left, right, operation):
    return _checked(left + right, 64, operation)


def _sub(left, right, operation):
    return _checked(left - right, 64, operation)


def _mul(left, right, operation):
    return _checked(left * right, 64, operation)


def round_half_up_div(numerator, denominator):
    """Round an integer ratio to nearest, with every exact tie toward +infinity.

    This also works for a negative denominator. Comparing r with d-r avoids
    doubling an int64 remainder and therefore does not introduce hidden overflow.
    """
    numerator = _checked(numerator, 64, 'division numerator')
    denominator = _checked(denominator, 64, 'division denominator')
    if denominator == 0:
        raise ZeroDivisionError('fixed-point denominator is zero')
    quotient, remainder = divmod(numerator, denominator)
    quotient = _checked(quotient, 64, 'division quotient')
    complement = _sub(denominator, remainder, 'division remainder complement')
    up = remainder >= complement if denominator > 0 else remainder <= complement
    return _add(quotient, 1, 'rounded division') if up else quotient


def _float_helpers():
    """Only setup, floating reference, image I/O and presentation use this module."""
    if __package__:
        return importlib.import_module('.geometry_float', package=__package__)
    return importlib.import_module('geometry_float')


def quantize_parameters(parameters, frac_bits=16):
    """PC-side setup: quantize floating coefficients once, before pixel processing."""
    if not isinstance(frac_bits, numbers.Integral) or not 10 <= frac_bits <= 20:
        raise ValueError('frac_bits must be an integer from 10 through 20')
    scale = 1 << int(frac_bits)
    result = dict(parameters)
    for name in ('width', 'height', 'source_width', 'source_height'):
        result[name] = _checked(parameters[name], 32, name)
        if result[name] < 1:
            raise ValueError(f'{name} must be positive')

    def coefficient(value, label):
        value = float(value)
        if not math.isfinite(value):
            raise ValueError(f'{label} must be finite')
        return _checked(math.floor(value * scale + 0.5), 32, label)

    result.update(frac_bits=int(frac_bits), scale=scale)
    kind = parameters['kind']
    if kind == 'rotation':
        result['cos_q'] = coefficient(parameters['cos'], 'cos coefficient')
        result['sin_q'] = coefficient(parameters['sin'], 'sin coefficient')
    elif kind == 'perspective':
        matrix = parameters['inverse_matrix']
        if np.asarray(matrix).shape != (3, 3):
            raise ValueError('inverse_matrix must be 3 by 3')
        result['inverse_matrix_q'] = [[coefficient(matrix[row][column], f'h{row}{column}')
                                       for column in range(3)] for row in range(3)]
    else:
        raise ValueError(f'unknown transform kind: {kind}')
    result['fixed_format'] = {
        'coefficient_bits': 32, 'coefficient_fractional_bits': int(frac_bits),
        'coordinate_bits': 32, 'coordinate_fractional_bits': int(frac_bits),
        'product_bits': 64, 'accumulator_bits': 64, 'signed': True,
        'coordinate_input': 'signed int32 pixel indices; rotation doubles centered indices',
        'rounding': 'nearest, exact halves toward positive infinity',
        'out_of_bounds': 'black; source address -1',
        'zero_denominator': 'invalid mapping; black; source address -1',
        'overflow': 'raise FixedOverflowError before narrowing; no wrap or saturation',
        'rotation': 'dx2=2*x-(Wout-1); sx_q=round((cq*dx2-sq*dy2+(Win-1)*S)/2)',
        'rotation_y': 'dy2=2*y-(Hout-1); sy_q=round((sq*dx2+cq*dy2+(Hin-1)*S)/2)',
        'perspective': 'nx=sum(h0j_q*[x,y,1]); d=sum(h2j_q*[x,y,1]); sx_q=round(nx*S/d)',
        'nearest': '(coordinate_q + S//2)//S; source_address=yi*Win+xi',
        'denominator_raw_format': {'rotation': 'literal integer 2, unscaled',
                                   'perspective': 'signed int64 homogeneous denominator in coefficient Q format'},
        'coordinate_pixel_range': f'[-{(1 << 31) // scale}, {(1 << 31) // scale})',
        'precision_note': 'direct coefficient quantization; perspective division can amplify denominator error',
        'per_pixel': 'integer multiplication, addition, subtraction and division only',
    }
    return result


def _pixel_inputs(x, y, parameters):
    return (_checked(x, 32, 'output x'), _checked(y, 32, 'output y'),
            _checked(parameters['scale'], 32, 'fixed scale'))


def map_rotation(x, y, parameters):
    """Return (source_x_q, source_y_q, valid) with integer-only pixel arithmetic."""
    x, y, scale = _pixel_inputs(x, y, parameters)
    cq = _checked(parameters['cos_q'], 32, 'cos coefficient')
    sq = _checked(parameters['sin_q'], 32, 'sin coefficient')
    dx2 = _checked(_sub(_mul(2, x, '2*x'), parameters['width'] - 1,
                       'doubled centered x'), 32, 'doubled centered x narrowing')
    dy2 = _checked(_sub(_mul(2, y, '2*y'), parameters['height'] - 1,
                       'doubled centered y'), 32, 'doubled centered y narrowing')
    xx = _sub(_mul(cq, dx2, 'cos*dx2'), _mul(sq, dy2, 'sin*dy2'), 'rotation x sum')
    yy = _add(_mul(sq, dx2, 'sin*dx2'), _mul(cq, dy2, 'cos*dy2'), 'rotation y sum')
    xx = _add(xx, _mul(parameters['source_width'] - 1, scale, 'x center scaled'),
              'rotation x center addition')
    yy = _add(yy, _mul(parameters['source_height'] - 1, scale, 'y center scaled'),
              'rotation y center addition')
    return (_checked(round_half_up_div(xx, 2), 32, 'source x_q narrowing'),
            _checked(round_half_up_div(yy, 2), 32, 'source y_q narrowing'), True)


def _perspective_pixel(x, y, parameters):
    x, y, scale = _pixel_inputs(x, y, parameters)
    matrix = parameters['inverse_matrix_q']
    values = []
    for row in range(3):
        a, b, c = [_checked(matrix[row][col], 32, f'h{row}{col} coefficient')
                   for col in range(3)]
        partial = _add(_mul(a, x, f'h{row}0*x'), _mul(b, y, f'h{row}1*y'),
                       f'h{row} row product sum')
        values.append(_add(partial, c, f'h{row} row translation'))
    nx, ny, denominator = values
    if denominator == 0:
        return 0, 0, False, 0
    sxq = round_half_up_div(_mul(nx, scale, 'perspective x numerator scaling'), denominator)
    syq = round_half_up_div(_mul(ny, scale, 'perspective y numerator scaling'), denominator)
    return (_checked(sxq, 32, 'perspective x_q narrowing'),
            _checked(syq, 32, 'perspective y_q narrowing'), True, denominator)


def map_perspective(x, y, parameters):
    """Return integer Q coordinates; a zero homogeneous denominator is invalid."""
    sxq, syq, valid, _ = _perspective_pixel(x, y, parameters)
    return sxq, syq, valid


def map_grid(parameters):
    """Compute every output coordinate with scalar, checked integer operations."""
    shape = (parameters['height'], parameters['width'])
    xq = np.empty(shape, dtype=np.int64)
    yq = np.empty(shape, dtype=np.int64)
    valid = np.empty(shape, dtype=bool)
    denominator = np.empty(shape, dtype=np.int64)
    perspective = parameters['kind'] == 'perspective'
    for y in range(shape[0]):
        for x in range(shape[1]):
            if perspective:
                values = _perspective_pixel(x, y, parameters)
            else:
                sxq, syq, good = map_rotation(x, y, parameters)
                values = sxq, syq, good, 2
            xq[y, x], yq[y, x], valid[y, x], denominator[y, x] = values
    return xq, yq, valid, denominator


def nearest_index(coordinate_q, scale):
    coordinate_q = _checked(coordinate_q, 32, 'nearest coordinate_q')
    scale = _checked(scale, 32, 'nearest scale')
    if scale <= 0 or scale & (scale - 1):
        raise ValueError('nearest scale must be a positive power of two')
    shifted = _add(coordinate_q, scale // 2, 'nearest half pixel addition')
    return _checked(shifted // scale, 32, 'nearest pixel index')


def sample_fixed(image, xq, yq, valid, parameters):
    """Nearest-neighbor sampling and row-major address generation use integers."""
    if xq.shape != yq.shape or xq.shape != valid.shape:
        raise ValueError('coordinate and valid arrays must have identical shapes')
    source_height, source_width = image.shape[:2]
    if (source_width, source_height) != (parameters['source_width'], parameters['source_height']):
        raise ValueError('image dimensions do not match prepared parameters')
    output = np.zeros(xq.shape + image.shape[2:], dtype=image.dtype)
    xi = np.full(xq.shape, -1, dtype=np.int64)
    yi = np.full(xq.shape, -1, dtype=np.int64)
    in_bounds = np.zeros(xq.shape, dtype=bool)
    address = np.full(xq.shape, -1, dtype=np.int64)
    for y in range(xq.shape[0]):
        for x in range(xq.shape[1]):
            if not valid[y, x]:
                continue
            xx = nearest_index(xq[y, x], parameters['scale'])
            yy = nearest_index(yq[y, x], parameters['scale'])
            xi[y, x], yi[y, x] = xx, yy
            if 0 <= xx < source_width and 0 <= yy < source_height:
                in_bounds[y, x] = True
                address[y, x] = _add(_mul(yy, source_width, 'row-major row offset'),
                                     xx, 'row-major address')
                output[y, x] = image[yy, xx]
    return output, xi, yi, in_bounds, address


def render(image, parameters):
    """Separate coordinate mapping from nearest-neighbor sampling."""
    xq, yq, valid, denominator = map_grid(parameters)
    output, xi, yi, in_bounds, address = sample_fixed(image, xq, yq, valid, parameters)
    return output, xq, yq, xi, yi, in_bounds, address, valid, denominator


def _reference_maps(parameters):
    return _float_helpers().map_grid(parameters)


def compare_to_float(image, floating_parameters, fixed_parameters, result=None):
    """Floating conversions are exclusively post-processing for comparison/display."""
    floating = _float_helpers()
    if result is None:
        result = render(image, fixed_parameters)
    output, xq, yq, xi, yi, in_bounds, address, valid, denominator = result
    fx, fy = _reference_maps(floating_parameters)
    reference, fxi, fyi, finside, faddress = floating.sample_nearest(image, fx, fy)
    sx = xq.astype(np.float64) / fixed_parameters['scale']
    sy = yq.astype(np.float64) / fixed_parameters['scale']
    comparable = valid & np.isfinite(fx) & np.isfinite(fy)
    error_x = np.full(fx.shape, np.nan)
    error_y = np.full(fy.shape, np.nan)
    error_x[comparable] = sx[comparable] - fx[comparable]
    error_y[comparable] = sy[comparable] - fy[comparable]
    errors = np.maximum(np.abs(error_x[comparable]), np.abs(error_y[comparable]))
    pixel_changed = output != reference
    if output.ndim > 2:
        pixel_changed = np.any(pixel_changed, axis=tuple(range(2, output.ndim)))
    report = {
        'kind': floating_parameters['kind'], 'frac_bits': fixed_parameters['frac_bits'],
        'output_width': fixed_parameters['width'], 'output_height': fixed_parameters['height'],
        'max_coordinate_error_pixels': float(errors.max()) if errors.size else None,
        'mean_coordinate_error_pixels': float(errors.mean()) if errors.size else None,
        'source_address_changed_count': int(np.count_nonzero(address != faddress)),
        'sampled_pixel_changed_count': int(np.count_nonzero(pixel_changed)),
        'in_bounds_changed_count': int(np.count_nonzero(in_bounds != finside)),
        'fixed_invalid_mapping_count': int(np.count_nonzero(~valid)),
        'compared_coordinate_count': int(np.count_nonzero(comparable)),
        'total_output_pixels': int(valid.size),
        'overflow_count': 0,
        'coordinate_error_definition': 'max(abs(fixed_x-float_x), abs(fixed_y-float_y))',
        'address_changes_include_black': 'out-of-bounds and invalid have address -1',
        'interpretation': 'zero pixel differences can coexist with changed addresses on repeated colors',
    }
    extra = {
        'x_source_q': xq, 'y_source_q': yq, 'denominator_raw': denominator,
        'fixed_mapping_valid': valid, 'float_x_source': fx, 'float_y_source': fy,
        'float_x_index': fxi, 'float_y_index': fyi, 'float_in_bounds': finside,
        'float_source_address': faddress, 'x_coordinate_error': error_x,
        'y_coordinate_error': error_y, 'source_address_changed': address != faddress,
        'sampled_pixel_changed': pixel_changed,
    }
    difference = np.abs(output.astype(np.int16) - reference.astype(np.int16)).astype(np.uint8)
    return report, extra, reference, difference


def run_transform(image, floating_parameters, output_path, frac_bits=16, table_path=None,
                  comparison_table=None):
    """Save a transform, its exact configuration, and a floating reference comparison."""
    floating = _float_helpers()
    parameters = quantize_parameters(floating_parameters, frac_bits)
    result = render(image, parameters)
    report, extra, reference, difference = compare_to_float(image, floating_parameters, parameters, result)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output, xq, yq, xi, yi, in_bounds, address, valid, denominator = result
    floating.save_image(output_path, output)
    floating.save_image(output_path.with_name(output_path.stem + '_float_reference.png'), reference)
    floating.save_image(output_path.with_name(output_path.stem + '_pixel_difference.png'), difference)
    floating.dump_json(output_path.with_name(output_path.stem + '_params.json'), parameters)
    floating.dump_json(output_path.with_name(output_path.stem + '_comparison.json'), report)
    # These divisions are for CSV display, after all integer mapping and sampling.
    xdisplay = xq.astype(np.float64) / parameters['scale']
    ydisplay = yq.astype(np.float64) / parameters['scale']
    xdisplay[~valid] = np.nan
    ydisplay[~valid] = np.nan
    if table_path is not None:
        floating.export_table(table_path, xdisplay, ydisplay, xi, yi, in_bounds, address,
                              {'x_source_q': xq, 'y_source_q': yq,
                               'denominator_raw': denominator, 'fixed_mapping_valid': valid})
    if comparison_table is not None:
        floating.export_table(comparison_table, xdisplay, ydisplay, xi, yi, in_bounds, address, extra)
    return report


def demo(directory=None, frac_bits=16):
    floating = _float_helpers()
    base = Path(__file__).resolve().parent
    directory = Path(directory or base / 'output' / 'fixed')
    directory.mkdir(parents=True, exist_ok=True)
    images = base / 'test_images'
    if (images / 'manifest.json').exists():
        manifest = json.loads((images / 'manifest.json').read_text(encoding='utf-8'))
    else:
        manifest = floating.generate_test_images(images)
    reports = {}
    for name in ('directional', 'checkerboard', 'grid_paper', 'rectangle_border', 'tiny_8x6'):
        image = floating.read_image(images / manifest['files'][name])
        for angle in manifest['angles']:
            tag = str(angle).replace('-', 'minus_')
            case = f'{name}_rotate_{tag}'
            output_path = directory / f'{case}.png'
            p = floating.rotation_parameters(image.shape[1], image.shape[0], angle)
            tiny_example = name == 'tiny_8x6' and angle == 30
            reports[case] = run_transform(
                image, p, output_path, frac_bits,
                directory / 'tiny_rotation_30_coords.csv' if tiny_example else None,
                directory / 'tiny_rotation_30_comparison.csv' if tiny_example else None)
            # Validate the saved pixels, including dimensions, rather than inferring
            # identity/quarter-turn correctness from coordinate error statistics.
            saved = floating.read_image(output_path)
            if angle == 0:
                np.testing.assert_array_equal(saved, image)
            if angle == 90:
                assert saved.shape[:2] == (image.shape[1], image.shape[0]), '90-degree dimensions must swap'
                np.testing.assert_array_equal(saved, np.rot90(image))
            if tiny_example:
                floating.save_image(directory / 'tiny_rotation_30.png', saved)
            print(f'已验证：{case}', flush=True)
    trapezoid = manifest['trapezoid']
    for name in ('trapezoid_checkerboard', 'trapezoid_grid_paper'):
        image = floating.read_image(images / manifest['files'][name])
        p = floating.perspective_parameters(image.shape[1], image.shape[0],
                                            trapezoid['points'], tuple(trapezoid['output_size']))
        case = f'{name}_rectified'
        output_path = directory / f'{case}.png'
        reports[case] = run_transform(image, p, output_path, frac_bits)
        if name == 'trapezoid_checkerboard':
            floating.save_image(directory / 'trapezoid_rectified.png', floating.read_image(output_path))
        print(f'已验证：{case}', flush=True)
        if frac_bits != 20:
            f20case = f'{case}_f20'
            f20path = directory / ('trapezoid_rectified_f20.png' if name == 'trapezoid_checkerboard'
                                    else f'{f20case}.png')
            reports[f20case] = run_transform(image, p, f20path, 20)
            print(f'已验证：{f20case}', flush=True)
    floating.dump_json(directory / 'comparison_summary.json', reports)
    print(json.dumps({'output_directory': str(directory.resolve()), 'comparisons': reports},
                     ensure_ascii=False, indent=2))
    return reports


def self_test():
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(FixedGeometryTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    print(f'Fixed self-test passed: {result.testsRun} tests; signed int32/Q16 -> int64 arithmetic')


def main(argv=None):
    parser = argparse.ArgumentParser(description='定点模型：A 旋转 / B 四点完整透视矫正（逆映射 + 最近邻）')
    subparsers = parser.add_subparsers(dest='command', required=True)
    defaults = Path(__file__).resolve().parent / 'output' / 'fixed'
    for command in ('rotate', 'rectify'):
        sub = subparsers.add_parser(command)
        sub.add_argument('input', type=Path, help='输入图片')
        sub.add_argument('--output', type=Path, default=defaults / ('rotation.png' if command == 'rotate' else 'rectified.png'))
        sub.add_argument('--frac-bits', type=int, choices=range(10, 21), default=16)
        sub.add_argument('--table', nargs='?', const='auto', default='auto', help='CSV 路径；默认输出同名坐标表')
        sub.add_argument('--comparison-table', nargs='?', const='auto', help='可选浮点/定点逐点比较 CSV')
        if command == 'rotate':
            sub.add_argument('--angle', type=float, help='正值为视觉逆时针，单位度；省略则交互输入')
            sub.add_argument('--canvas', choices=('expand', 'same'), default='expand')
        else:
            sub.add_argument('--points', help='左上;右上;右下;左下，例如 "80,45;370,65;425,285;30,285"；省略则手选')
            sub.add_argument('--size', nargs=2, type=int, metavar=('W', 'H'))
    demo_parser = subparsers.add_parser('demo')
    demo_parser.add_argument('--output-dir', type=Path, default=defaults)
    demo_parser.add_argument('--frac-bits', type=int, choices=range(10, 21), default=16)
    subparsers.add_parser('self-test')
    args = parser.parse_args(argv)
    if args.command == 'self-test':
        self_test()
        return
    if args.command == 'demo':
        demo(args.output_dir, args.frac_bits)
        return
    floating = _float_helpers()
    image = floating.read_image(args.input)
    if args.command == 'rotate':
        if args.angle is None:
            args.angle = float(input('请输入旋转角度（度，正值逆时针）：'))
        p = floating.rotation_parameters(image.shape[1], image.shape[0], args.angle, args.canvas)
    else:
        points = floating.parse_points(args.points) if args.points else floating.select_corners(image)
        if points is None:
            raise ValueError('corner selection cancelled')
        p = floating.perspective_parameters(image.shape[1], image.shape[0], points, args.size)
        if p.get('size_inferred'):
            print('输出尺寸由边长估计；要恢复指定比例，请提供 --size W H。')
    table = args.output.with_name(args.output.stem + '_coords.csv') if args.table == 'auto' else Path(args.table)
    comparison = None
    if args.comparison_table:
        comparison = (args.output.with_name(args.output.stem + '_comparison.csv')
                      if args.comparison_table == 'auto' else Path(args.comparison_table))
    report = run_transform(image, p, args.output, args.frac_bits, table, comparison)
    print(json.dumps({'output': str(args.output.resolve()), 'coordinates': str(table.resolve()),
                      'comparison': report}, ensure_ascii=False, indent=2))


class FixedGeometryTests(unittest.TestCase):
    def test_half_ties_are_toward_positive_infinity(self):
        cases = ((1, 2, 1), (-1, 2, 0), (-3, 2, -1),
                 (1, -2, 0), (3, -2, -1), (-1, -2, 1))
        for numerator, denominator, expected in cases:
            with self.subTest(numerator=numerator, denominator=denominator):
                self.assertEqual(round_half_up_div(numerator, denominator), expected)

    def test_division_with_no_half_tie(self):
        for numerator, denominator, expected in ((1, 3, 0), (2, 3, 1),
                                                (-1, 3, 0), (-2, 3, -1)):
            self.assertEqual(round_half_up_div(numerator, denominator), expected)

    def test_zero_division_and_signed_division_overflow_rejected(self):
        with self.assertRaises(ZeroDivisionError):
            round_half_up_div(3, 0)
        with self.assertRaises(FixedOverflowError):
            round_half_up_div(-(1 << 63), -1)
        self.assertEqual(round_half_up_div(-(1 << 63), -(1 << 63)), 1)

    def test_nearest_negative_half_ties_and_border(self):
        scale = 1 << 16
        self.assertEqual(nearest_index(-scale // 2, scale), 0)
        self.assertEqual(nearest_index(-3 * scale // 2, scale), -1)
        self.assertEqual(nearest_index(scale // 2, scale), 1)
        image = (np.arange(6, dtype=np.uint8) + 7).reshape(2, 3)
        p = self._rotation(3, 2, 0)
        qx = np.array([[-scale // 2, 5 * scale // 2, -scale // 2 - 1]])
        qy = np.zeros((1, 3), dtype=np.int64)
        output, xi, _, inside, address = sample_fixed(image, qx, qy, np.ones((1, 3), bool), p)
        np.testing.assert_array_equal(xi, [[0, 3, -1]])
        np.testing.assert_array_equal(inside, [[True, False, False]])
        np.testing.assert_array_equal(address, [[0, -1, -1]])
        np.testing.assert_array_equal(output, [[7, 0, 0]])

    @staticmethod
    def _rotation(width, height, angle):
        radians = math.radians(angle)
        swap = angle % 180 == 90
        return quantize_parameters({'kind': 'rotation', 'source_width': width,
                                    'source_height': height, 'width': height if swap else width,
                                    'height': width if swap else height, 'angle': angle,
                                    'cos': math.cos(radians), 'sin': math.sin(radians),
                                    'inverse_matrix': [[1, 0, 0], [0, 1, 0], [0, 0, 1]]})

    def test_identity_and_quarter_turns_match_literal_numpy_rotation(self):
        for width, height in ((8, 6), (7, 5), (8, 5), (7, 6), (1, 5)):
            image = np.arange(width * height, dtype=np.uint8).reshape(height, width)
            for angle in (0, 90, 180, 270):
                with self.subTest(width=width, height=height, angle=angle):
                    p = self._rotation(width, height, angle)
                    xq, yq, valid, _ = map_grid(p)
                    output, _, _, inside, _ = sample_fixed(image, xq, yq, valid, p)
                    np.testing.assert_array_equal(output, np.rot90(image, angle // 90))
                    self.assertTrue(inside.all())

    def test_identity_perspective_and_non_affine_denominator(self):
        p = quantize_parameters({'kind': 'perspective', 'width': 8, 'height': 6,
                                  'source_width': 8, 'source_height': 6,
                                  'inverse_matrix': [[1, 0, 0], [0, 1, 0], [0, 0, 1]]})
        self.assertEqual(map_perspective(7, 5, p), (7 * 65536, 5 * 65536, True))
        image = np.arange(48, dtype=np.uint8).reshape(6, 8)
        xq, yq, valid, _ = map_grid(p)
        np.testing.assert_array_equal(sample_fixed(image, xq, yq, valid, p)[0], image)
        p['inverse_matrix_q'][2] = [32768, 0, 65536]
        # At x=2 the denominator is 2, so (2,4) maps exactly to (1,2).
        self.assertEqual(map_perspective(2, 4, p), (65536, 131072, True))
        self.assertEqual(_perspective_pixel(2, 4, p)[3], 131072)
        p['inverse_matrix_q'][2] = [32768, 0, 0]
        self.assertEqual(map_perspective(0, 4, p), (0, 0, False))
        p['inverse_matrix_q'] = [[-65536, 0, 0], [0, -65536, 0], [0, 0, -65536]]
        self.assertEqual(map_perspective(7, 5, p), (7 * 65536, 5 * 65536, True))

    def test_pc_prepared_analytic_perspective_fixture(self):
        floating = _float_helpers()
        fp = floating.perspective_parameters(6, 9, [[1, 2], [4.5, 1], [4.5, 4], [1, 8]], (5, 3))
        p = quantize_parameters(fp)
        self.assertEqual(p['inverse_matrix_q'], [[131072, 0, 65536], [0, 196608, 131072], [16384, 0, 65536]])
        qx, qy, valid = map_perspective(2, 1, p)
        self.assertTrue(valid)
        self.assertEqual((qx, qy), (218453, 218453))
        self.assertEqual((nearest_index(qx, 65536), nearest_index(qy, 65536)), (3, 3))
        image = np.arange(54, dtype=np.uint8).reshape(9, 6)
        result = render(image, p)
        self.assertEqual(result[6][1, 2], 21)
        self.assertEqual(map_perspective(4, 2, p), (294912, 262144, True))
        self.assertEqual(result[6][2, 4], 29)

    def test_fractional_word_settings_and_pc_validation(self):
        fp = _float_helpers().rotation_parameters(8, 5, 90)
        image = np.arange(40, dtype=np.uint8).reshape(5, 8)
        for fraction in (10, 16, 20):
            p = quantize_parameters(fp, fraction)
            self.assertEqual(p['scale'], 1 << fraction)
            np.testing.assert_array_equal(render(image, p)[0], np.rot90(image))
        for bad in (9, 21, 16.5):
            with self.assertRaises(ValueError):
                quantize_parameters(fp, bad)
        bad = dict(fp, cos=32768)
        with self.assertRaises(FixedOverflowError):
            quantize_parameters(bad)

    def test_coefficient_coordinate_product_accumulator_overflow_rejected(self):
        p = self._rotation(8, 6, 0)
        with self.assertRaises(FixedOverflowError):
            map_rotation(1 << 31, 0, p)
        p['cos_q'] = 1 << 31
        with self.assertRaises(FixedOverflowError):
            map_rotation(0, 0, p)
        with self.assertRaises(FixedOverflowError):
            _mul((1 << 63) - 1, 2, 'test product')
        with self.assertRaises(FixedOverflowError):
            _add((1 << 63) - 1, 1, 'test accumulator')
        p = quantize_parameters({'kind': 'perspective', 'width': 2, 'height': 2,
                                  'source_width': 2, 'source_height': 2,
                                  'inverse_matrix': [[1, 0, 0], [0, 1, 0], [0, 0, 1]]})
        with self.assertRaises(FixedOverflowError):
            map_perspective(32768, 0, p)
        p['inverse_matrix_q'][0][0] = (1 << 31) - 1
        with self.assertRaises(FixedOverflowError):
            map_perspective((1 << 31) - 1, 0, p)

    def test_pixel_mapper_rejects_float_inputs(self):
        with self.assertRaises(TypeError):
            map_rotation(0.0, 0, self._rotation(8, 6, 0))

    def test_zero_denominator_is_black_with_invalid_address(self):
        p = quantize_parameters({'kind': 'perspective', 'width': 2, 'height': 2,
                                  'source_width': 2, 'source_height': 2,
                                  'inverse_matrix': [[1, 0, 0], [0, 1, 0], [0, 0, 0]]})
        image = np.full((2, 2, 3), 255, dtype=np.uint8)
        output, _, _, xi, yi, inside, address, valid, denominator = render(image, p)
        self.assertTrue(np.all(output == 0))
        self.assertTrue(np.all(address == -1))
        self.assertTrue(np.all(xi == -1) and np.all(yi == -1))
        self.assertFalse(valid.any() or inside.any() or denominator.any())

    def test_cli_unsupported_output_format_has_concise_error(self):
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'input.png'
            _float_helpers().save_image(source, np.arange(6, dtype=np.uint8).reshape(2, 3))
            command = [sys.executable, str(Path(__file__).resolve()), 'rotate', str(source),
                       '--angle', '0', '--output', str(Path(folder) / 'output.unsupported')]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn('Traceback', result.stderr)


if __name__ == '__main__':
    try:
        main()
    except (FixedOverflowError, ValueError, OSError, TypeError, ZeroDivisionError, EOFError, cv2.error) as error:
        print(f'Error: {error}', file=sys.stderr)
        raise SystemExit(2)
    except KeyboardInterrupt:
        print('操作已取消。', file=sys.stderr)
        raise SystemExit(130)
