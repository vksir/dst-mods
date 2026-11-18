#!/usr/bin/env python
"""生成创意工坊用的 preview.jpg（268×268，ModUploader 读取 mod 目录下的这张图）。

画面取 anim/*.zip 里的 atlas-0.tex（128px 地面精灵，比 46px 物品栏图标清晰），
解码后缩小排列，底部压上 mod 名。产物覆盖 mods/<mod>/preview.jpg。

用法：
  python tools/wanda_planar_plan/gen_workshop_preview.py
  python tools/wanda_planar_plan/gen_workshop_preview.py --preview-only

为什么用地面精灵而不是物品栏图标：工坊缩略图会被系统缩到 ~120px 显示，
64px 图标放大会糊；128px 精灵缩到 72px 仍在清晰区间。
"""
import argparse
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))   # tools/<mod>/
REPO = os.path.dirname(os.path.dirname(HERE))
COMMON = os.path.join(REPO, "tools", "common")      # 通用工具目录
sys.path.insert(0, COMMON)

from PIL import Image, ImageDraw, ImageFilter, ImageFont  # noqa: E402

import ktex2png  # noqa: E402

MOD_DIR = os.path.join(REPO, "mods", "wanda_planar_plan")
OUT = os.path.join(MOD_DIR, "preview.jpg")

SIZE = 268                      # 工坊预览图基准尺寸（原版 mod 也都用 268×268）
ITEMS = ["wanda_haste_watch", "wanda_slow_watch", "wanda_watch_bag"]
TITLE_CN = "旺达位面计划"
TITLE_EN = "Wanda Planar Plan"


def decode_sprite(prefab, tmp_dir):
    """从 anim/<prefab>.zip 取 atlas-0.tex 解码成 RGBA 精灵。"""
    zpath = os.path.join(MOD_DIR, "anim", prefab + ".zip")
    with zipfile.ZipFile(zpath) as z:
        tex = next(n for n in z.namelist() if n.endswith(".tex"))
        tmp_tex = os.path.join(tmp_dir, prefab + ".tex")
        with open(tmp_tex, "wb") as f:
            f.write(z.read(tex))
    im = ktex2png.ktex_to_image(tmp_tex)
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    # DST 图集行序翻转存储：解码结果是倒的，翻正才是游戏里看到的方向
    im = im.transpose(Image.FLIP_TOP_BOTTOM)
    # 裁掉全透明边缘，便于统一摆放
    bbox = im.split()[-1].getbbox()
    return im.crop(bbox) if bbox else im


def background():
    """深色皮革底色 + 中心微亮 + 细边框，贴合原版 mod 缩略图风格。"""
    bg = Image.new("RGB", (SIZE, SIZE), (22, 16, 12))
    d = ImageDraw.Draw(bg)
    # 径向渐变（由中心向外压暗）
    cx = cy = SIZE // 2
    for r in range(SIZE, 0, -2):
        t = r / SIZE
        c = (int(74 - 46 * t), int(52 - 34 * t), int(36 - 24 * t))
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=c)
    bg = bg.filter(ImageFilter.GaussianBlur(6))
    d = ImageDraw.Draw(bg)
    # 边框（双线，像贴纸）
    d.rectangle((3, 3, SIZE - 4, SIZE - 4), outline=(18, 12, 8), width=3)
    d.rectangle((7, 7, SIZE - 8, SIZE - 8), outline=(120, 88, 52), width=1)
    return bg


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


def build(tmp_dir):
    bg = background().convert("RGBA")

    # 三件物品：底层先画，间隔均匀
    target = 78                                     # 每件物品的显示边长
    gap = 6
    total = target * len(ITEMS) + gap * (len(ITEMS) - 1)
    x = (SIZE - total) // 2
    top = 42
    for prefab in ITEMS:
        sp = decode_sprite(prefab, tmp_dir)
        k = min(target / sp.width, target / sp.height)
        w, h = max(1, int(sp.width * k)), max(1, int(sp.height * k))
        sp = sp.resize((w, h), Image.LANCZOS)
        # 投影，让贴纸浮起来
        shadow = Image.new("RGBA", (w + 8, h + 8), (0, 0, 0, 0))
        shadow.paste(Image.new("RGBA", (w, h), (0, 0, 0, 130)), (4, 5), sp.split()[-1])
        shadow = shadow.filter(ImageFilter.GaussianBlur(3))
        bg.alpha_composite(shadow, (x - 4, top + (target - h) // 2 - 4))
        bg.alpha_composite(sp, (x, top + (target - h) // 2))
        x += target + gap

    d = ImageDraw.Draw(bg)
    f_cn = font("C:/Windows/Fonts/msyh.ttc", 26)
    f_en = font("C:/Windows/Fonts/msyh.ttc", 13)
    # 中文名：描边保证在亮底上也清楚
    cn_box = d.textbbox((0, 0), TITLE_CN, font=f_cn)
    cn_x = (SIZE - (cn_box[2] - cn_box[0])) // 2
    cn_y = 168
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        d.text((cn_x + dx, cn_y + dy), TITLE_CN, font=f_cn, fill=(16, 11, 7))
    d.text((cn_x, cn_y), TITLE_CN, font=f_cn, fill=(248, 232, 196))
    en_box = d.textbbox((0, 0), TITLE_EN, font=f_en)
    d.text(((SIZE - (en_box[2] - en_box[0])) // 2, cn_y + 34), TITLE_EN, font=f_en,
           fill=(206, 176, 126))

    return bg.convert("RGB")


def main(argv=None):
    ap = argparse.ArgumentParser(description="生成工坊 preview.jpg")
    ap.add_argument("--tmp", default=os.path.join(REPO, ".scratch", "wanda-planar-plan", "tmp"))
    ap.add_argument("--preview-only", action="store_true", help="兼容其它生成器的开关（无作用）")
    a = ap.parse_args(argv)
    os.makedirs(a.tmp, exist_ok=True)

    img = build(a.tmp)
    img.save(OUT, "JPEG", quality=92, subsampling=0)
    print("wrote", OUT, img.size, os.path.getsize(OUT), "bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
