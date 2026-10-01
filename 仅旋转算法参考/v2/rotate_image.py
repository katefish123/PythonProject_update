import math
from pathlib import Path

import cv2
import numpy as np

def rotate_bilinear(image, angle):
    height, width = image.shape[:2]

    cx = (width - 1) / 2.0
    cy = (height - 1) / 2.0
    theta = math.radians(angle)
    cos_theta = math.cos(theta)
    sin_theta = math.sin(theta)

    new_width = max(1, int(abs(width * cos_theta) + abs(height * sin_theta)))
    new_height = max(1, int(abs(height * cos_theta) + abs(width * sin_theta)))

    new_cx = (new_width - 1) / 2.0
    new_cy = (new_height - 1) / 2.0

    rotated = np.zeros((new_height, new_width, *image.shape[2:]), dtype=image.dtype)

    for y_dst in range(new_height):
        for x_dst in range(new_width):

            x = x_dst - new_cx
            y = y_dst - new_cy
            x_src = cos_theta * x + sin_theta * y + cx
            y_src = -sin_theta * x + cos_theta * y + cy

            if 0 <= x_src <= width - 1 and 0 <= y_src <= height - 1:
                x0 = int(math.floor(x_src))
                y0 = int(math.floor(y_src))
                x1 = min(x0 + 1, width - 1)
                y1 = min(y0 + 1, height - 1)
                dx = x_src - x0
                dy = y_src - y0

                p00 = image[y0, x0].astype(np.float32)
                p10 = image[y0, x1].astype(np.float32)
                p01 = image[y1, x0].astype(np.float32)
                p11 = image[y1, x1].astype(np.float32)
                pixel = (
                    (1 - dx) * (1 - dy) * p00
                    + dx * (1 - dy) * p10
                    + (1 - dx) * dy * p01
                    + dx * dy * p11
                )
                rotated[y_dst, x_dst] = np.clip(pixel, 0, 255).astype(np.uint8)

    return rotated

def main():
    input_text = input("请输入图片路径: ").strip().strip('"')
    input_path = Path(input_text).expanduser()
    if not input_path.is_absolute() and not input_path.exists():
        input_path = Path(__file__).parent / input_path

    image = cv2.imread(str(input_path))
    if image is None:
        print(f"图片读取失败，请检查路径：{input_text}")
        return

    try:
        angle = float(input("请输入旋转角度（度）: "))
    except ValueError:
        print("旋转角度请输入数字。")
        return

    if not math.isfinite(angle):
        print("旋转角度请输入有限的数字。")
        return

    rotated = rotate_bilinear(image, angle)
    output_path = "rotated_output.jpg"
    if not cv2.imwrite(output_path, rotated):
        print(f"图片保存失败：{output_path}")
        return

    height, width = image.shape[:2]
    new_height, new_width = rotated.shape[:2]
    print("处理完成")
    print(f"原图尺寸: {width} x {height}")
    print(f"输出尺寸: {new_width} x {new_height}")
    print(f"旋转角度: {angle}°")
    print(f"输出文件: {output_path}")

if __name__ == "__main__":
    main()
