"""浮点参考：A 旋转；B 四点透视矫正。

坐标：左上像素中心 (0,0)，x 向右、y 向下；正角度在屏幕上逆时针。
逆映射与采样分离；最近邻 floor(v+0.5)，半值向正无穷；越界填黑。
示例：python3 geometry_float.py demo / self-test / rotate --help / rectify --help
"""

import argparse
import csv
import json
import math
from pathlib import Path

import cv2
import numpy as np

BASE = Path(__file__).resolve().parent


def _dimensions(width, height):
    if not isinstance(width, (int, np.integer)) or not isinstance(height, (int, np.integer)):
        raise ValueError("宽高必须是整数")
    if width < 1 or height < 1 or width > 16384 or height > 16384:
        raise ValueError("宽高必须在 1..16384 内")


def rotation_parameters(width, height, angle, canvas="expand"):
    """CPU 参数准备；返回输出大小和输出→输入矩阵，不读取像素。"""
    _dimensions(width, height)
    if not math.isfinite(angle):
        raise ValueError("角度必须是有限数")
    if canvas not in ("expand", "same"):
        raise ValueError("canvas 必须是 expand 或 same")
    theta = angle % 360
    cardinal = {0: (1.0, 0.0), 90: (0.0, 1.0), 180: (-1.0, 0.0), 270: (0.0, -1.0)}
    c, s = cardinal.get(theta, (math.cos(math.radians(theta)), math.sin(math.radians(theta))))
    ow, oh = width, height
    if canvas == "expand":
        ow = math.ceil(width * abs(c) + height * abs(s))
        oh = math.ceil(width * abs(s) + height * abs(c))
    _dimensions(ow, oh)
    cx, cy, ox, oy = (width - 1) / 2, (height - 1) / 2, (ow - 1) / 2, (oh - 1) / 2
    inverse = [[c, -s, cx - c * ox + s * oy], [s, c, cy - s * ox - c * oy], [0., 0., 1.]]
    return {"kind": "rotation", "source_width": int(width), "source_height": int(height),
            "width": ow, "height": oh, "angle": angle, "cos": c, "sin": s,
            "canvas": canvas, "inverse_matrix": inverse}


def map_rotation(x, y, p):
    """独立逆映射：标量或 NumPy 网格 → 原图小数坐标。"""
    dx, dy = x - (p["width"] - 1) / 2, y - (p["height"] - 1) / 2
    return (p["cos"] * dx - p["sin"] * dy + (p["source_width"] - 1) / 2,
            p["sin"] * dx + p["cos"] * dy + (p["source_height"] - 1) / 2)


def _validate_corners(points, width, height):
    pts = np.asarray(points, dtype=np.float64)
    if pts.shape != (4, 2) or not np.all(np.isfinite(pts)):
        raise ValueError("必须给出 4 个有限坐标，按左上、右上、右下、左下排列")
    if np.any(pts[:, 0] < 0) or np.any(pts[:, 0] > width - 1) or np.any(pts[:, 1] < 0) or np.any(pts[:, 1] > height - 1):
        raise ValueError("角点必须位于原图像素中心范围内")
    edges = np.roll(pts, -1, axis=0) - pts
    following = np.roll(edges, -1, axis=0)
    crosses = edges[:, 0] * following[:, 1] - edges[:, 1] * following[:, 0]
    if np.any(crosses <= 1e-9):
        raise ValueError("四角须形成凸四边形，按左上→右上→右下→左下，不能交叉、重复或共线")
    return pts


def _homography(src, dst):
    """用 8 个线性方程解四点单应矩阵；核心算法不调用 OpenCV 变换。"""
    a, b = [], []
    for (x, y), (u, v) in zip(src, dst):
        a.extend([[x, y, 1, 0, 0, 0, -u*x, -u*y], [0, 0, 0, x, y, 1, -v*x, -v*y]])
        b.extend([u, v])
    try:
        coefficients = np.linalg.solve(np.asarray(a, dtype=float), np.asarray(b, dtype=float))
    except np.linalg.LinAlgError as exc:
        raise ValueError("角点退化，不能求透视变换") from exc
    h = np.append(coefficients, 1.0).reshape(3, 3)
    if not np.all(np.isfinite(h)):
        raise ValueError("透视矩阵包含非有限数")
    return h


def perspective_parameters(source_width, source_height, points, size=None):
    """完整平面透视模型；size=(W,H) 指定目标比例，自动尺寸只是估计。"""
    _dimensions(source_width, source_height)
    pts = _validate_corners(points, source_width, source_height)
    if size is None:
        width = int(math.floor(max(np.linalg.norm(pts[1]-pts[0]), np.linalg.norm(pts[2]-pts[3])) + .5)) + 1
        height = int(math.floor(max(np.linalg.norm(pts[3]-pts[0]), np.linalg.norm(pts[2]-pts[1])) + .5)) + 1
    else:
        if len(size) != 2:
            raise ValueError("size 必须包含宽、高")
        width, height = size
    _dimensions(width, height)
    if width < 2 or height < 2:
        raise ValueError("透视输出宽高须至少为 2")
    dst = np.array([[0, 0], [width-1, 0], [width-1, height-1], [0, height-1]], dtype=float)
    inverse = _homography(dst, pts)
    denominators = dst[:, 0]*inverse[2, 0] + dst[:, 1]*inverse[2, 1] + inverse[2, 2]
    if np.min(denominators) <= 1e-12:
        raise ValueError("透视分母在输出范围内趋近零或穿过零，角点过于退化")
    return {"kind": "perspective", "source_width": int(source_width), "source_height": int(source_height),
            "width": int(width), "height": int(height), "points": pts.tolist(),
            "size_inferred": size is None, "inverse_matrix": inverse.tolist()}


def map_perspective(x, y, p):
    """(h00*x+h01*y+h02)/d, (h10*x+h11*y+h12)/d；d 随位置变化。"""
    h = np.asarray(p["inverse_matrix"], dtype=float)
    x, y = np.asarray(x, dtype=float), np.asarray(y, dtype=float)
    d = h[2, 0]*x + h[2, 1]*y + h[2, 2]
    valid = np.isfinite(d) & (np.abs(d) > 1e-12)
    with np.errstate(divide="ignore", invalid="ignore"):
        sx = np.where(valid, (h[0, 0]*x + h[0, 1]*y + h[0, 2])/d, np.nan)
        sy = np.where(valid, (h[1, 0]*x + h[1, 1]*y + h[1, 2])/d, np.nan)
    return sx, sy


def map_grid(p):
    y, x = np.indices((p["height"], p["width"]), dtype=np.float64)
    return (map_rotation if p["kind"] == "rotation" else map_perspective)(x, y, p)


def sample_nearest(image, x_map, y_map):
    """只取整、检查边界、读像素。地址按像素计；越界地址 -1 禁止读。"""
    if image.ndim not in (2, 3) or image.size == 0:
        raise ValueError("输入必须是非空灰度或彩色图片")
    sx, sy = np.asarray(x_map, dtype=float), np.asarray(y_map, dtype=float)
    if sx.shape != sy.shape or sx.ndim != 2:
        raise ValueError("坐标网格必须是同大小二维数组")
    finite = np.isfinite(sx) & np.isfinite(sy) & (np.abs(sx) < 2**62) & (np.abs(sy) < 2**62)
    xi, yi = np.full(sx.shape, -1, dtype=np.int64), np.full(sy.shape, -1, dtype=np.int64)
    xi[finite], yi[finite] = np.floor(sx[finite] + .5).astype(np.int64), np.floor(sy[finite] + .5).astype(np.int64)
    sh, sw = image.shape[:2]
    inside = finite & (xi >= 0) & (xi < sw) & (yi >= 0) & (yi < sh)
    output = np.zeros(sx.shape + image.shape[2:], dtype=image.dtype)
    output[inside] = image[yi[inside], xi[inside]]
    addresses = np.full(sx.shape, -1, dtype=np.int64)
    addresses[inside] = yi[inside]*sw + xi[inside]
    return output, xi, yi, inside, addresses


def render(image, p):
    if image.ndim not in (2, 3) or image.shape[:2] != (p["source_height"], p["source_width"]):
        raise ValueError("图片宽高必须与映射参数中的原图宽高一致")
    sx, sy = map_grid(p)
    output, xi, yi, inside, address = sample_nearest(image, sx, sy)
    return output, sx, sy, xi, yi, inside, address


def read_image(path):
    path = Path(path)
    if not path.is_file():
        raise ValueError(f"找不到图片：{path}")
    data = cv2.imdecode(np.fromfile(str(path), dtype=np.uint8), cv2.IMREAD_COLOR)
    if data is None:
        raise ValueError(f"无法解码图片：{path}")
    return data


def save_image(path, image):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    ok, encoded = cv2.imencode(path.suffix or ".png", image)
    if not ok:
        raise ValueError(f"无法编码图片：{path}")
    encoded.tofile(str(path))


def dump_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")


def export_table(path, x_map, y_map, xi, yi, in_bounds, address, extra=None):
    """每个输出像素一行，按 y 后 x 排列，保留小数坐标与实际读地址。"""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    arrays = {"x_source": x_map, "y_source": y_map, "x_nearest": xi, "y_nearest": yi,
              "in_bounds": in_bounds, "out_of_bounds": ~in_bounds, "address_pixel": address}
    arrays.update(extra or {})
    arrays = {key: np.asarray(value) for key, value in arrays.items()}
    shape = np.asarray(x_map).shape
    if any(a.shape != shape for a in arrays.values()):
        raise ValueError("CSV 所有列必须与坐标网格大小相同")
    with path.open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["x_output", "y_output"] + list(arrays))
        for y in range(shape[0]):
            for x in range(shape[1]):
                values = [int(v) if isinstance(v, (bool, np.bool_, int, np.integer)) else format(float(v), ".17g")
                          for v in (a[y, x] for a in arrays.values())]
                writer.writerow([x, y] + values)


def parse_points(text):
    try:
        points = [[float(v) for v in pair.split(",")] for pair in text.split(";")]
        if np.asarray(points).shape != (4, 2):
            raise ValueError
        return points
    except (ValueError, TypeError) as exc:
        raise ValueError('角点格式："x1,y1;x2,y2;x3,y3;x4,y4"') from exc


def select_corners(image):
    """鼠标选四角；显示缩放后仍导出原图坐标，按逻辑 TL/TR/BR/BL。"""
    height, width = image.shape[:2]
    scale = min(1.0, 1100/width, 750/height)
    display_width, display_height = max(1, round(width*scale)), max(1, round(height*scale))
    preview = cv2.resize(image, (display_width, display_height), interpolation=cv2.INTER_AREA)
    points, labels = [], ["1 TL", "2 TR", "3 BR", "4 BL"]
    title = "Pick TL > TR > BR > BL | Enter confirm | Right undo | R reset | Esc cancel"

    def mouse(event, x, y, flags, userdata):
        if event == cv2.EVENT_LBUTTONDOWN and len(points) < 4 and 0 <= x < display_width and 0 <= y < display_height:
            # Pixel centers stay aligned when the display is scaled.
            points.append([min(width-1, max(0., (x+.5)*width/display_width-.5)),
                           min(height-1, max(0., (y+.5)*height/display_height-.5))])
        elif event == cv2.EVENT_RBUTTONDOWN and points:
            points.pop()

    print("依次点左上、右上、右下、左下；Enter 确认，右键撤销，R 重选，Esc 取消。")
    try:
        cv2.namedWindow(title, cv2.WINDOW_AUTOSIZE)
        cv2.setMouseCallback(title, mouse)
        while True:
            display = preview.copy()
            screen = [(round((x+.5)*display_width/width-.5), round((y+.5)*display_height/height-.5)) for x, y in points]
            for index, pos in enumerate(screen):
                cv2.circle(display, pos, 6, (0, 0, 255), -1)
                cv2.putText(display, labels[index], (max(0, pos[0]-25), max(18, pos[1]-10)), cv2.FONT_HERSHEY_SIMPLEX, .6, (0, 255, 255), 2)
            if len(screen) > 1:
                cv2.polylines(display, [np.asarray(screen, dtype=np.int32)], len(screen) == 4, (0, 255, 255), 2)
            cv2.imshow(title, display)
            key = cv2.waitKey(20) & 0xff
            if key == 27 or cv2.getWindowProperty(title, cv2.WND_PROP_VISIBLE) < 1:
                raise ValueError("已取消选四角")
            if key in (ord("r"), ord("R")):
                points.clear()
            if key in (10, 13) and len(points) == 4:
                try:
                    _validate_corners(points, width, height)
                    return points
                except ValueError as exc:
                    print(exc)
    except cv2.error as exc:
        raise ValueError("图形窗口不可用；安装 opencv-python 或使用 --points 手动输入坐标") from exc
    finally:
        try:
            cv2.destroyWindow(title)
        except cv2.error:
            pass


def _cjk_font(size, explicit=None):
    from PIL import ImageFont
    candidates = [explicit] if explicit else [
        "/System/Library/Fonts/PingFang.ttc", "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "C:/Windows/Fonts/msyh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"]
    for path in candidates:
        if path and Path(path).is_file():
            return ImageFont.truetype(str(path), size)
    raise ValueError("生成中文测试图需要中文字体；请用 generate-tests --font 指定 .ttf/.ttc")


def generate_test_images(directory, font=None):
    """确定性程序绘图；生成已知真值的棋盘透视图，不使用生成式图片。"""
    from PIL import Image, ImageDraw
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    large, small = _cjk_font(26, font), _cjk_font(16, font)
    files = {}

    def put(name, image):
        image.save(directory / name)
        files[Path(name).stem] = name

    direction = Image.new("RGB", (321, 241), (238, 241, 248))
    draw = ImageDraw.Draw(direction)
    colors = [(240, 65, 65), (45, 195, 80), (55, 100, 245), (255, 205, 30)]
    boxes = [(0, 0, 60, 44), (260, 0, 320, 44), (260, 196, 320, 240), (0, 196, 60, 240)]
    for box, color, label in zip(boxes, colors, ["左上", "右上", "右下", "左下"]):
        draw.rectangle(box, fill=color)
        draw.text((box[0]+12, box[1]+13), label, font=small, fill="black")
    for pos, label in [((147, 18), "上"), ((147, 195), "下"), ((14, 105), "左"), ((281, 105), "右")]:
        draw.text(pos, label, font=large, fill=(15, 15, 30))
    draw.line([(160, 161), (160, 72)], fill=(50, 55, 70), width=4)
    draw.polygon([(160, 62), (149, 81), (171, 81)], fill=(50, 55, 70))
    draw.line([(110, 120), (208, 120)], fill=(50, 55, 70), width=3)
    draw.ellipse((157, 117, 163, 123), fill="red")
    draw.rectangle((0, 0, 320, 240), outline=(200, 0, 150), width=1)
    put("directional.png", direction)

    y, x = np.indices((241, 321))
    checker_values = np.where(((x//40 + y//40) % 2) == 0, 240, 35).astype(np.uint8)
    checker = np.repeat(checker_values[:, :, None], 3, axis=2)
    checker[0, :], checker[-1, :], checker[:, 0], checker[:, -1] = (0, 100, 230), (230, 60, 0), (80, 190, 30), (170, 0, 200)
    put("checkerboard.png", Image.fromarray(checker))
    paper = Image.new("RGB", (321, 241), "white")
    draw = ImageDraw.Draw(paper)
    for xx in range(0, 321, 20):
        draw.line((xx, 0, xx, 240), fill=(65, 110, 185) if xx % 40 == 0 else (170, 200, 230), width=1)
    for yy in range(0, 241, 20):
        draw.line((0, yy, 320, yy), fill=(65, 110, 185) if yy % 40 == 0 else (170, 200, 230), width=1)
    draw.rectangle((0, 0, 320, 240), outline="black", width=2)
    put("grid_paper.png", paper)

    rectangle = Image.new("RGB", (401, 181), (25, 45, 65))
    draw = ImageDraw.Draw(rectangle)
    for xx in range(20, 400, 40):
        draw.rectangle((xx, 35, min(xx+20, 390), 145), fill=(80+xx//4, 160, 200))
    draw.text((143, 70), "宽401 高181", font=small, fill="white")
    draw.rectangle((0, 0, 400, 180), outline=(255, 240, 0), width=1)
    draw.rectangle((1, 1, 399, 179), outline=(255, 0, 120), width=1)
    put("rectangle_border.png", rectangle)

    ty, tx = np.indices((6, 8))
    tiny = np.stack([tx*31+7, ty*40+5, (tx+ty)*17+3], axis=-1).astype(np.uint8)
    put("tiny_8x6.png", Image.fromarray(tiny))
    corners = [[80, 45], [370, 65], [425, 285], [30, 285]]
    dst = np.array([[0, 0], [320, 0], [320, 240], [0, 240]], dtype=np.float64)
    forward = _homography(dst, np.asarray(corners, dtype=float))
    # Synthetic capture is an independent OpenCV warp with explicit nearest and black border.
    warped = cv2.warpPerspective(cv2.cvtColor(checker, cv2.COLOR_RGB2BGR), forward, (461, 321),
                                 flags=cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    save_image(directory / "trapezoid_checkerboard.png", warped)
    files["trapezoid_checkerboard"] = "trapezoid_checkerboard.png"
    warped_grid = cv2.warpPerspective(cv2.cvtColor(np.asarray(paper), cv2.COLOR_RGB2BGR), forward, (461, 321),
                                      flags=cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    save_image(directory / "trapezoid_grid_paper.png", warped_grid)
    files["trapezoid_grid_paper"] = "trapezoid_grid_paper.png"
    manifest = {"files": files, "trapezoid": {"image": "trapezoid_checkerboard.png", "points": corners,
                 "output_size": [321, 241], "rectangular_pixel_span_ratio": "320:240 = 4:3"},
                "tiny": {"image": "tiny_8x6.png", "width": 8, "height": 6},
                "angles": [0, 90, 180, 30, -30], "corner_rgb": colors}
    dump_json(directory / "manifest.json", manifest)
    return manifest


def opencv_reference(image, p):
    """独立 OpenCV 几何参数 + 统一取整的 remap；另保留原生 warp 差异。"""
    size = (p["width"], p["height"])
    if p["kind"] == "rotation":
        cx, cy = (p["source_width"]-1)/2, (p["source_height"]-1)/2
        forward = cv2.getRotationMatrix2D((cx, cy), p["angle"] % 360, 1.0)
        forward[:, 2] += [(p["width"]-p["source_width"])/2, (p["height"]-p["source_height"])/2]
        h = np.vstack([cv2.invertAffineTransform(forward), [0, 0, 1]])
        native = cv2.warpAffine(image, h[:2], size, flags=cv2.INTER_NEAREST | cv2.WARP_INVERSE_MAP,
                                borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    else:
        dst = np.array([[0, 0], [size[0]-1, 0], [size[0]-1, size[1]-1], [0, size[1]-1]], dtype=np.float32)
        h = cv2.getPerspectiveTransform(dst, np.asarray(p["points"], dtype=np.float32))
        native = cv2.warpPerspective(image, h, size, flags=cv2.INTER_NEAREST | cv2.WARP_INVERSE_MAP,
                                     borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    yy, xx = np.indices((size[1], size[0]), dtype=float)
    d = h[2, 0]*xx + h[2, 1]*yy + h[2, 2]
    with np.errstate(divide="ignore", invalid="ignore"):
        rx, ry = (h[0, 0]*xx+h[0, 1]*yy+h[0, 2])/d, (h[1, 0]*xx+h[1, 1]*yy+h[1, 2])/d
    # Integer-coordinate remap makes OpenCV's hidden half-value policy irrelevant.
    safe = np.isfinite(rx) & np.isfinite(ry) & (np.abs(rx)<32760) & (np.abs(ry)<32760)
    ix, iy = np.full(rx.shape, -32760, dtype=np.float32), np.full(ry.shape, -32760, dtype=np.float32)
    ix[safe], iy[safe] = np.floor(rx[safe]+.5), np.floor(ry[safe]+.5)
    unified = cv2.remap(image, ix, iy, interpolation=cv2.INTER_NEAREST,
                        borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    return unified, native, rx, ry


def _pixel_changes(a, b):
    return int(np.count_nonzero(np.any(a != b, axis=2) if a.ndim == 3 else a != b))


def process(image, p, output_path, table_path=None, reference=True):
    output_path = Path(output_path)
    output, sx, sy, xi, yi, inside, address = render(image, p)
    save_image(output_path, output)
    table_path = Path(table_path) if table_path else output_path.with_name(output_path.stem+"_coordinates.csv")
    export_table(table_path, sx, sy, xi, yi, inside, address)
    metadata = dict(p, coordinates="pixel centers; origin top-left; +x right; +y down",
                    positive_angle="counterclockwise on screen", nearest="floor(v+0.5), ties to +infinity",
                    border_value=0, address_unit="pixel", invalid_address=-1)
    if reference:
        unified, native, rx, ry = opencv_reference(image, p)
        valid = np.isfinite(sx) & np.isfinite(sy) & np.isfinite(rx) & np.isfinite(ry)
        metadata["opencv_comparison"] = {
            "coordinate_max_abs_error": float(max(np.max(np.abs(sx[valid]-rx[valid]), initial=0), np.max(np.abs(sy[valid]-ry[valid]), initial=0))),
            "unified_nearest_pixel_changes": _pixel_changes(output, unified),
            "native_INTER_NEAREST_pixel_changes": _pixel_changes(output, native),
            "note": "统一取整的对照与原生 warp 分开统计；半像素数值噪声、OpenCV 内部精度可能改变取样地址"}
        save_image(output_path.with_name(output_path.stem+"_opencv_unified.png"), unified)
        save_image(output_path.with_name(output_path.stem+"_opencv_native.png"), native)
    dump_json(output_path.with_name(output_path.stem+"_parameters.json"), metadata)
    print(f"图片：{output_path}\n坐标表：{table_path}")
    return metadata


def demo():
    manifest = generate_test_images(BASE / "test_images")
    out = BASE / "output" / "float"
    reports = []
    for name in ["directional", "checkerboard", "grid_paper", "rectangle_border", "tiny_8x6"]:
        image = read_image(BASE / "test_images" / manifest["files"][name])
        h, w = image.shape[:2]
        for angle in manifest["angles"]:
            tag = str(angle).replace("-", "minus_")
            p = rotation_parameters(w, h, angle)
            report = process(image, p, out / f"{name}_rotate_{tag}.png")
            if angle == 0:
                assert np.array_equal(read_image(out / f"{name}_rotate_{tag}.png"), image), "0° 必须逐像素相等"
            if angle == 90:
                assert (p["width"], p["height"]) == (h, w)
                assert np.array_equal(read_image(out / f"{name}_rotate_{tag}.png"), np.rot90(image)), "90° 方向/宽高错误"
            reports.append({"input": name, "angle": angle, **report["opencv_comparison"]})
    spec = manifest["trapezoid"]
    for name in ["trapezoid_checkerboard", "trapezoid_grid_paper"]:
        image = read_image(BASE / "test_images" / manifest["files"][name])
        h, w = image.shape[:2]
        p = perspective_parameters(w, h, spec["points"], spec["output_size"])
        report = process(image, p, out / f"{name}_rectified.png")
        reports.append({"input": name, "kind": "perspective", **report["opencv_comparison"]})
    dump_json(out / "validation_report.json", {"zero_degree_exact": True, "ninety_degree_swaps_dimensions": True, "cases": reports})
    print(f"共 {len(reports)} 个演示结果；验证报告：{out / 'validation_report.json'}")


def self_test():
    # Catch absent implementations first; then check observable geometry behavior.
    assert callable(globals().get("rotation_parameters")), "rotation mapping is not implemented"
    assert callable(globals().get("render")), "inverse mapping sampler is not implemented"
    image = np.arange(15, dtype=np.uint8).reshape(3, 5)
    for angle, turns in ((0, 0), (90, 1), (180, 2), (-90, -1)):
        actual, *_ = render(image, rotation_parameters(5, 3, angle))
        assert np.array_equal(actual, np.rot90(image, turns)), f"rotation {angle}"
    p = perspective_parameters(21, 21, [[0, 0], [10, 0], [10, 10], [0, 20]], (11, 11))
    assert np.allclose(map_perspective(5, 5, p), (20 / 3, 20 / 3)), "non-affine denominator"
    for height, width in ((3, 5), (4, 8), (1, 7), (7, 1), (2, 3)):
        data = np.arange(width*height, dtype=np.uint8).reshape(height, width)
        for angle, turns in ((0, 0), (90, 1), (180, 2), (270, 3), (-90, -1), (360, 0)):
            actual, *_ = render(data, rotation_parameters(width, height, angle))
            assert np.array_equal(actual, np.rot90(data, turns)), (height, width, angle)
    sx = np.array([[-1., -.5, .49, .5, 4.49, 4.5, np.nan, np.inf]])
    sy = np.zeros(sx.shape)
    result, xi, yi, inside, address = sample_nearest(np.array([[11, 22, 33, 44, 55]], dtype=np.uint8), sx, sy)
    assert result.tolist() == [[0, 11, 11, 22, 55, 0, 0, 0]], "half-values or black border"
    assert address.tolist() == [[-1, 0, 0, 1, 4, -1, -1, -1]], "invalid address must not read cache"
    identity = perspective_parameters(5, 3, [[0, 0], [4, 0], [4, 2], [0, 2]], (5, 3))
    assert np.array_equal(render(image, identity)[0], image), "perspective identity"
    for invalid in ([[0, 0], [4, 2], [4, 0], [0, 2]], [[0, 0], [1, 0], [2, 0], [3, 0]]):
        try:
            perspective_parameters(5, 3, invalid, (5, 3))
        except ValueError:
            pass
        else:
            raise AssertionError("invalid corners accepted")
    p = rotation_parameters(5, 3, 30)
    assert (p["width"], p["height"]) == (6, 6), "expanded rectangular canvas"
    assert np.allclose(map_rotation(2.5, 2.5, p), (2, 1)), "center alignment"
    p = rotation_parameters(5, 3, -30)
    assert np.allclose(map_rotation(3.5, 2.5, p), (2+math.sqrt(3)/2, .5)), "negative rotation sign"
    try:
        render(image, rotation_parameters(6, 3, 0))
    except ValueError:
        pass
    else:
        raise AssertionError("image/parameter dimensions mismatch was accepted")
    print("Float self-test passed: cardinal rotations, odd/even centers, borders/ties, addresses, perspective denominator, invalid corners")


def main():
    parser = argparse.ArgumentParser(description="浮点参考：A 旋转 / B 四点透视矫正，输出图片、坐标与地址表")
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("rotate", "rectify"):
        item = sub.add_parser(command, help="A 输入角度旋转" if command == "rotate" else "B 鼠标选四角矫正")
        item.add_argument("image", type=Path)
        item.add_argument("--output", type=Path, default=BASE / "output" / "float" / (command+".png"))
        item.add_argument("--table", type=Path, help="默认导出输出图片旁的 *_coordinates.csv")
        if command == "rotate":
            item.add_argument("--angle", type=float, help="正角度为逆时针；省略时交互输入")
            item.add_argument("--canvas", choices=["expand", "same"], default="expand", help="expand 完整画布；same 可能裁剪")
        else:
            item.add_argument("--points", help='省略时鼠标选择；格式 "x,y;x,y;x,y;x,y"，左上/右上/右下/左下')
            item.add_argument("--size", type=int, nargs=2, metavar=("W", "H"), help="目标宽高；知道原始比例时应显式给出")
    gen = sub.add_parser("generate-tests", help="创建测试图片")
    gen.add_argument("--directory", type=Path, default=BASE / "test_images")
    gen.add_argument("--font", type=Path, help="指定中文字体 .ttf/.ttc")
    sub.add_parser("demo", help="生成测试图并运行全部角度与透视演示，不弹窗口")
    sub.add_parser("self-test", help="自动验证核心行为")
    args = parser.parse_args()
    try:
        if args.command == "self-test":
            self_test()
        elif args.command == "generate-tests":
            generate_test_images(args.directory, args.font)
            print(f"测试图：{args.directory}")
        elif args.command == "demo":
            self_test()
            demo()
        else:
            image = read_image(args.image)
            height, width = image.shape[:2]
            if args.command == "rotate":
                angle = args.angle if args.angle is not None else float(input("输入逆时针旋转角度（度，可为负）："))
                p = rotation_parameters(width, height, angle, args.canvas)
            else:
                points = parse_points(args.points) if args.points else select_corners(image)
                p = perspective_parameters(width, height, points, args.size)
                if p["size_inferred"]:
                    print("输出尺寸由边长估计；要恢复指定比例，请提供 --size W H。")
            process(image, p, args.output, args.table)
    except (ValueError, OSError, cv2.error, EOFError) as exc:
        parser.exit(2, f"错误：{exc}\n")


if __name__ == "__main__":
    main()
