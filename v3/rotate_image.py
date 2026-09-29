import argparse
import math
import sys
from pathlib import Path

import cv2
import numpy as np


FRACTION_BITS = 16
SCALE = 1 << FRACTION_BITS
MAX_DIMENSION = 4096


class ChineseArgumentParser(argparse.ArgumentParser):
    def format_usage(self):
        return super().format_usage().replace("usage: ", "用法：", 1)

    def format_help(self):
        return super().format_help().replace("usage: ", "用法：", 1)

    def error(self, message):
        if message.startswith("unrecognized arguments: "):
            message = "无法识别的参数：" + message[len("unrecognized arguments: "):]
        elif "invalid float value:" in message:
            message = "旋转角度必须是有效数字"
        elif message.startswith("argument "):
            message = "选项缺少参数值" if message.endswith("expected one argument") else "命令行参数无效"
        elif not any("\u4e00" <= char <= "\u9fff" for char in message):
            message = "命令行参数无效"
        self.print_usage(sys.stderr)
        self.exit(2, f"{self.prog}: 错误：{message}\n")


def coefficients_from_degrees(angle):
    if not math.isfinite(angle):
        raise ValueError("角度必须是有限数值")
    theta = math.radians(angle)
    return round(math.cos(theta) * SCALE), round(math.sin(theta) * SCALE)


def _validate_image(image):
    if not isinstance(image, np.ndarray) or image.ndim not in (2, 3):
        raise ValueError("图像必须是二维或三维 NumPy 数组")
    if image.dtype != np.uint8 or not all(image.shape):
        raise ValueError("图像不能为空，且数据类型必须是 uint8")
    if image.shape[0] > MAX_DIMENSION or image.shape[1] > MAX_DIMENSION:
        raise ValueError(f"图像的宽度和高度不能超过 {MAX_DIMENSION}")


def sample_bilinear_q(image, x_q, y_q):
    height, width = image.shape[:2]
    if not (0 <= x_q <= (width - 1) * SCALE and
            0 <= y_q <= (height - 1) * SCALE):
        return 0 if image.ndim == 2 else np.zeros(image.shape[2], dtype=np.uint8)

    x0, dx = divmod(x_q, SCALE)
    y0, dy = divmod(y_q, SCALE)
    x1 = min(x0 + 1, width - 1)
    y1 = min(y0 + 1, height - 1)
    wx0 = SCALE - dx
    wy0 = SCALE - dy

    def blend(channel=None):
        if channel is None:
            p00, p10 = int(image[y0, x0]), int(image[y0, x1])
            p01, p11 = int(image[y1, x0]), int(image[y1, x1])
        else:
            p00, p10 = int(image[y0, x0, channel]), int(image[y0, x1, channel])
            p01, p11 = int(image[y1, x0, channel]), int(image[y1, x1, channel])
        top = p00 * wx0 + p10 * dx
        bottom = p01 * wx0 + p11 * dx
        return (top * wy0 + bottom * dy) >> (2 * FRACTION_BITS)

    if image.ndim == 2:
        return blend()
    return np.array([blend(c) for c in range(image.shape[2])], dtype=np.uint8)


def rotate_bilinear_q(image, cos_q, sin_q):
    _validate_image(image)
    if not all(isinstance(v, (int, np.integer)) and -SCALE <= v <= SCALE
               for v in (cos_q, sin_q)):
        raise ValueError("系数必须是有符号 Q1.16 整数")

    height, width = image.shape[:2]
    new_width = max(1, (width * abs(cos_q) + height * abs(sin_q)) >> FRACTION_BITS)
    new_height = max(1, (height * abs(cos_q) + width * abs(sin_q)) >> FRACTION_BITS)
    rotated = np.zeros((new_height, new_width, *image.shape[2:]), dtype=np.uint8)

    x2_first = 1 - new_width
    y2_first = 1 - new_height
    row_x_num = x2_first * cos_q + y2_first * sin_q + (width - 1) * SCALE
    row_y_num = -x2_first * sin_q + y2_first * cos_q + (height - 1) * SCALE

    for y_dst in range(new_height):
        x_num = row_x_num
        y_num = row_y_num
        for x_dst in range(new_width):
            rotated[y_dst, x_dst] = sample_bilinear_q(image, x_num >> 1, y_num >> 1)
            x_num += 2 * cos_q
            y_num -= 2 * sin_q
        row_x_num += 2 * sin_q
        row_y_num += 2 * cos_q
    return rotated


def rotate_bilinear_fixed(image, angle):
    cos_q, sin_q = coefficients_from_degrees(angle)
    return rotate_bilinear_q(image, cos_q, sin_q)


def main():
    parser = ChineseArgumentParser(description="使用 Q16.16 定点数旋转图像", add_help=False)
    parser._positionals.title = "位置参数"
    parser._optionals.title = "选项"
    parser.add_argument("-h", "--help", action="help", help="显示帮助信息并退出")
    parser.add_argument("input_path", nargs="?", metavar="输入图片路径", help="输入图片路径")
    parser.add_argument("angle", nargs="?", type=float, metavar="旋转角度", help="旋转角度（度）")
    parser.add_argument("-o", "--output", default="rotated_output.png", metavar="输出图片路径",
                        help="输出图片路径")
    args = parser.parse_args()

    input_text = args.input_path or input("请输入图片路径: ").strip().strip('"')
    input_path = Path(input_text).expanduser()
    if not input_path.is_absolute() and not input_path.exists():
        input_path = Path(__file__).parent / input_path
    image = cv2.imread(str(input_path), cv2.IMREAD_UNCHANGED)
    if image is None:
        parser.error(f"图片读取失败：{input_path}")

    try:
        angle = args.angle if args.angle is not None else float(input("请输入旋转角度（度）: "))
        rotated = rotate_bilinear_fixed(image, angle)
    except ValueError as exc:
        parser.error(str(exc))

    output_path = Path(args.output)
    if not cv2.imwrite(str(output_path), rotated):
        parser.error(f"图片保存失败：{output_path}")
    print(f"处理完成：{image.shape[1]} x {image.shape[0]} -> "
          f"{rotated.shape[1]} x {rotated.shape[0]}；角度 {angle}°；{output_path}")


if __name__ == "__main__":
    main()
