import cv2
import numpy as np
import math

def rotate_image(input_path, angle_deg, output_path):
    img = cv2.imread(input_path)

    if img is None:
        print("图片读取失败，请检查路径。")
        return

    h, w = img.shape[:2]    #h = img.shape[0]
                            #w = img.shape[1]
    theta = math.radians(angle_deg)

    cos_t = math.cos(theta)
    sin_t = math.sin(theta)

    cx = (w - 1) / 2.0
    cy = (h - 1) / 2.0

    new_w = int(abs(w * cos_t) + abs(h * sin_t))
    new_h = int(abs(h * cos_t) + abs(w * sin_t))

    new_cx = (new_w - 1) / 2.0
    new_cy = (new_h - 1) / 2.0

    output = np.zeros((new_h, new_w, 3), dtype=np.uint8)

    for y_out in range(new_h):
        for x_out in range(new_w):

            x = x_out - new_cx
            y = y_out - new_cy

            src_x = x * cos_t + y * sin_t
            src_y = -x * sin_t + y * cos_t

            src_x += cx
            src_y += cy

            src_x_int = int(round(src_x))
            src_y_int = int(round(src_y))

            if 0 <= src_x_int < w and 0 <= src_y_int < h:
                output[y_out, x_out] = img[src_y_int, src_x_int]

    cv2.imwrite(output_path, output)

    print("处理完成")
    print(f"原图尺寸: {w} x {h}")
    print(f"输出尺寸: {new_w} x {new_h}")
    print(f"旋转角度: {angle_deg}°")
    print(f"输出文件: {output_path}")


if __name__ == "__main__":
    input_path = input("请输入图片路径: ")

    angle = float(input("请输入旋转角度（度）: "))

    output_path = "rotated_output.jpg"

    rotate_image(
        input_path,
        angle,
        output_path
    )
