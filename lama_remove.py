# -*- coding: utf-8 -*-
"""
LaMa (big-lama) ONNX 水印去除 —— 专业图像修复，非裁剪、非简单涂抹。
用法:
  python lama_remove.py detect  <图片...>   # 自动检测水印文字并修复
  python lama_remove.py rect    <图片...>   # 修复整个右下角水印矩形区域（用于修复之前的涂抹痕迹）
"""
import sys, os, glob
import cv2
import numpy as np
import onnxruntime as ort

MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "lama_fp32.onnx")
WM_W, WM_H = 280, 120  # 水印固定在右下角


def imread_u(path):
    data = np.fromfile(path, dtype=np.uint8)
    return cv2.imdecode(data, cv2.IMREAD_COLOR)


def imwrite_u(path, img):
    ext = os.path.splitext(path)[1]
    ok, buf = cv2.imencode(ext, img)
    if ok:
        buf.tofile(path)
    return ok


_sess = None


def get_session():
    global _sess
    if _sess is None:
        _sess = ort.InferenceSession(MODEL, providers=["CPUExecutionProvider"])
    return _sess


def build_mask_detect(img):
    """背景差分检测水印文字（右下角ROI）"""
    h, w = img.shape[:2]
    x0, y0 = max(0, w - WM_W), max(0, h - WM_H)
    roi = img[y0:, x0:]
    bg = cv2.medianBlur(roi, 31)
    diff = cv2.subtract(roi, bg)
    gray = cv2.cvtColor(diff, cv2.COLOR_BGR2GRAY)
    _, m = cv2.threshold(gray, 9, 255, cv2.THRESH_BINARY)
    n, labels, stats, _ = cv2.connectedComponentsWithStats(m)
    clean = np.zeros_like(m)
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] >= 5:
            clean[labels == i] = 255
    clean = cv2.dilate(clean, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11)))
    full = np.zeros((h, w), np.uint8)
    full[y0:, x0:] = clean
    return full


def build_mask_rect(img):
    """整个水印矩形区域（用于修复涂抹痕迹）"""
    h, w = img.shape[:2]
    x0, y0 = max(0, w - 340), max(0, h - 150)
    full = np.zeros((h, w), np.uint8)
    full[y0:, x0:] = 255
    return full


def lama_inpaint(img, mask):
    """LaMa修复（模型固定512x512输入：裁剪掩膜周边512x512窗口推理后贴回）。"""
    sess = get_session()
    h, w = img.shape[:2]
    ys, xs = np.where(mask > 127)
    if len(ys) == 0:
        return img
    # 以掩膜包围盒为中心取512x512窗口（贴边裁剪）
    y1, y2 = ys.min(), ys.max()
    x1, x2 = xs.min(), xs.max()
    cy, cx = (y1 + y2) // 2, (x1 + x2) // 2
    t = 512
    ty1 = min(max(0, cy - t // 2), max(0, h - t))
    tx1 = min(max(0, cx - t // 2), max(0, w - t))
    ty2, tx2 = min(h, ty1 + t), min(w, tx1 + t)
    ty1, tx1 = ty2 - t, tx2 - t

    tile = img[ty1:ty2, tx1:tx2]
    m = (mask[ty1:ty2, tx1:tx2] > 127).astype(np.float32)

    image = tile[:, :, ::-1].astype(np.float32) / 255.0  # BGR->RGB, 0..1
    image = image.transpose(2, 0, 1)[None]               # 1,3,512,512
    mm = m[None, None]                                    # 1,1,512,512, 1=待修复

    out = sess.run(None, {"image": image, "mask": mm})[0]
    out = out[0].transpose(1, 2, 0)  # H,W,3
    if out.max() <= 1.01:            # 兼容0..1输出
        out = out * 255
    out = np.clip(out, 0, 255).astype(np.uint8)
    out = cv2.cvtColor(out, cv2.COLOR_RGB2BGR)

    img = img.copy()
    region = mask[ty1:ty2, tx1:tx2] > 127
    tile_fixed = np.where(region[:, :, None], out, tile)
    img[ty1:ty2, tx1:tx2] = tile_fixed
    return img


def main():
    mode = sys.argv[1]
    paths = []
    for t in sys.argv[2:]:
        if os.path.isdir(t):
            paths += sorted(glob.glob(os.path.join(t, "*.png")) + glob.glob(os.path.join(t, "*.jpg")))
        else:
            paths.append(t)
    for p in paths:
        img = imread_u(p)
        if img is None:
            print(f"[SKIP] 无法读取: {p}")
            continue
        mask = build_mask_detect(img) if mode == "detect" else build_mask_rect(img)
        if mask.sum() == 0:
            print(f"[OK] 无水印: {os.path.basename(p)}")
            continue
        result = lama_inpaint(img, mask)
        imwrite_u(p, result)
        print(f"[OK] LaMa修复完成 ({int(mask.sum()/255)} px): {os.path.basename(p)}")


if __name__ == "__main__":
    main()
