"""在屏幕上按图片模板定位元素（零第三方依赖：只用 numpy + Pillow）。

用途：游戏/桌面 UI 自动化里"这个东西在屏幕哪个位置"——避免靠猜坐标点击。

实现：FFT 加速的归一化互相关（NCC），等价于 OpenCV 的 TM_CCOEFF_NORMED。
  NCC(u,v) = (ΣXT - ΣX·mean_T) / (sqrt(ΣX² - ΣX²/N) · sqrt(N·var_T))
  分子用 FFT 互相关算，Σ 与 ΣX² 用积分图（cumsum）算，因此整屏搜索也只需百毫秒级。

命令行：
  python tools/uilook.py shot out.png
  python tools/uilook.py crop screen.png 100,200,64,64 tpl.png
  python tools/uilook.py find tpl.png [--screen shot.png] [--threshold 0.9]
                                     [--scales 1.0,0.9,0.8] [--region x,y,w,h] [--max 5]
  （不传 --screen 时现场截屏）

库调用：
  from uilook import grab, find_template, crop
  m = find_template("tpl.png", screen=grab(), threshold=0.9)   # 最高分
  for m in find_all("tpl.png", threshold=0.85): ...
"""

import argparse
import json
import sys

import numpy as np
from PIL import Image, ImageGrab


# ---------------------------------------------------------------- 截图 / 裁剪

def grab(bbox=None):
    """截屏 -> numpy uint8 (H, W, 3) RGB。bbox=(left, top, right, bottom)。"""
    im = ImageGrab.grab(bbox=bbox, all_screens=True)
    return np.asarray(im.convert("RGB"))


def load_image(path):
    if isinstance(path, np.ndarray):
        return path
    return np.asarray(Image.open(path).convert("RGB"))


def save_image(arr, path):
    Image.fromarray(arr).save(path)


def crop(screen, box):
    """box=(x, y, w, h) -> 裁剪结果"""
    x, y, w, h = box
    return screen[y:y + h, x:x + w].copy()


def _to_gray(arr):
    # 只用亮度：快 3 倍，且对 UI 抗锯齿/色差更宽容
    return (arr[..., 0] * 0.299 + arr[..., 1] * 0.587 + arr[..., 2] * 0.114).astype(np.float32)


# ---------------------------------------------------------------- 核心匹配

def _box_sum(a, h, w):
    """滑动窗口求和：返回 (H-h+1, W-w+1)，对应每个窗口内部之和。"""
    ii = np.zeros((a.shape[0] + 1, a.shape[1] + 1), dtype=np.float64)
    np.cumsum(a, axis=0, out=ii[1:, 1:])
    np.cumsum(ii[1:, 1:], axis=1, out=ii[1:, 1:])
    return (ii[h:, w:] - ii[:-h, w:] - ii[h:, :-w] + ii[:-h, :-w])


def _ncc_map(img, tpl):
    """归一化互相关图，形状 = (H-h+1, W-w+1)。"""
    H, W = img.shape
    h, w = tpl.shape
    if h > H or w > W:
        return None

    n = float(h * w)
    tpl_mean = tpl.mean()
    tpl_var = tpl.var()
    if tpl_var <= 1e-9:
        return None

    # 分子：ΣXT（互相关，用 FFT 做，避免 O(N·M) 的滑动乘加）
    fh, fw = H, W
    fimg = np.fft.rfft2(img, s=(fh, fw))
    ftpl = np.fft.rfft2(tpl[::-1, ::-1], s=(fh, fw))
    xt = np.fft.irfft2(fimg * ftpl, s=(fh, fw))
    # irfft 结果的 [h-1:, w-1:] 才是"模板左上角对齐"的有效区域
    xt = xt[h - 1:, w - 1:]

    sum_x = _box_sum(img.astype(np.float64), h, w)
    sum_x2 = _box_sum((img.astype(np.float64)) ** 2, h, w)

    var_x = sum_x2 - (sum_x ** 2) / n
    var_x[var_x < 1e-9] = 1e-9

    num = xt - sum_x * tpl_mean
    den = np.sqrt(var_x) * np.sqrt(n * tpl_var)
    return num / den


def _peaks(score, threshold, max_results, min_dist):
    """取所有超过阈值的位置，做简单非极大值抑制。"""
    out = []
    s = score.copy()
    for _ in range(max_results):
        idx = int(np.argmax(s))
        y, x = divmod(idx, s.shape[1])
        v = float(s[y, x])
        if v < threshold:
            break
        out.append((x, y, v))
        y0, y1 = max(0, y - min_dist), min(s.shape[0], y + min_dist + 1)
        x0, x1 = max(0, x - min_dist), min(s.shape[1], x + min_dist + 1)
        s[y0:y1, x0:x1] = -1.0
    return out


def find_all(template, screen=None, threshold=0.9, scales=(1.0,), region=None,
             max_results=20, min_dist=None):
    """返回 [{'x','y','w','h','cx','cy','score'}]，按 score 降序。

    template: 图片路径或 ndarray
    region:   (x, y, w, h) 限定搜索区域（相对整屏坐标）
    scales:   模板缩放系数列表（应对 DPI/分辨率差异），如 (1.0, 0.8, 1.25)
    """
    if screen is None:
        screen = grab()
    screen = load_image(screen)
    tpl_rgb = load_image(template)

    off_x, off_y = 0, 0
    if region is not None:
        rx, ry, rw, rh = region
        screen = screen[ry:ry + rh, rx:rx + rw]
        off_x, off_y = rx, ry
        # 小区域没必要走 FFT，直接切片更快
        pass

    img = _to_gray(screen)
    results = []

    for sc in scales:
        if abs(sc - 1.0) < 1e-6:
            tpl_rgb_s = tpl_rgb
        else:
            new_size = (max(1, int(round(tpl_rgb.shape[1] * sc))),
                        max(1, int(round(tpl_rgb.shape[0] * sc))))
            tpl_rgb_s = np.asarray(
                Image.fromarray(tpl_rgb).resize(new_size, Image.LANCZOS))

        tpl = _to_gray(tpl_rgb_s)
        h, w = tpl.shape
        score = _ncc_map(img, tpl)
        if score is None:
            continue

        d = min_dist if min_dist is not None else max(h, w) // 2
        for (x, y, v) in _peaks(score, threshold, max_results, d):
            results.append({
                "x": x + off_x, "y": y + off_y,
                "w": w, "h": h,
                "cx": x + off_x + w // 2, "cy": y + off_y + h // 2,
                "score": round(v, 4), "scale": sc,
            })

    # 跨尺度去重：同一位置只留最高分
    results.sort(key=lambda r: -r["score"])
    dedup = []
    for r in results:
        if all(abs(r["cx"] - q["cx"]) > r["w"] // 2 or abs(r["cy"] - q["cy"]) > r["h"] // 2
               for q in dedup):
            dedup.append(r)
    return dedup[:max_results]


def find_template(template, screen=None, threshold=0.9, scales=(1.0,), region=None):
    """返回最高分匹配或 None。"""
    hits = find_all(template, screen=screen, threshold=threshold,
                    scales=scales, region=region, max_results=1)
    return hits[0] if hits else None


# ---------------------------------------------------------------- CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description="屏幕模板定位（numpy + Pillow）")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_shot = sub.add_parser("shot", help="截屏")
    p_shot.add_argument("out")

    p_crop = sub.add_parser("crop", help="裁剪并保存")
    p_crop.add_argument("screen")
    p_crop.add_argument("box", help="x,y,w,h")
    p_crop.add_argument("out")

    p_find = sub.add_parser("find", help="查找模板")
    p_find.add_argument("template")
    p_find.add_argument("--screen", default=None, help="用已有截图，否则现场截屏")
    p_find.add_argument("--threshold", type=float, default=0.9)
    p_find.add_argument("--scales", default="1.0")
    p_find.add_argument("--region", default=None, help="x,y,w,h")
    p_find.add_argument("--max", type=int, default=5)

    args = ap.parse_args(argv)

    if args.cmd == "shot":
        save_image(grab(), args.out)
        print(json.dumps({"ok": True, "path": args.out}, ensure_ascii=False))
        return 0

    if args.cmd == "crop":
        x, y, w, h = [int(v) for v in args.box.split(",")]
        save_image(crop(load_image(args.screen), (x, y, w, h)), args.out)
        print(json.dumps({"ok": True, "path": args.out}, ensure_ascii=False))
        return 0

    scales = tuple(float(s) for s in args.scales.split(","))
    region = tuple(int(v) for v in args.region.split(",")) if args.region else None
    screen = load_image(args.screen) if args.screen else None
    hits = find_all(args.template, screen=screen, threshold=args.threshold,
                    scales=scales, region=region, max_results=args.max)
    print(json.dumps({"ok": True, "matches": hits}, ensure_ascii=False))
    return 0 if hits else 1


if __name__ == "__main__":
    sys.exit(main())
