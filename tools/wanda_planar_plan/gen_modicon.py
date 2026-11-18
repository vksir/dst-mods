#!/usr/bin/env python
"""生成 Mods 列表用图标：mods/<mod>/modicon.png（256×256，官方 autocompiler 编成 tex/xml）。

注意**输出位置是 mod 根目录**，不是 images/ 下（见 OUT 的注释）。

风格沿用三件物品的那套画法（黄铜壳 + 平涂三色 + 暖黑描边），复用 gen_wanda_icons 的图元与配色，
所以图标和物品放一起是一眼的同一套美术。

构图：两块表斜向叠放——后排洋红（减速表）、前排青绿（加速表）；
两块都用「正圆表盘 + 单根针」，缩到 46px 也认得出（v6 的结论）。

用法：
  python tools/wanda_planar_plan/gen_modicon.py
  # 之后编译 tex/xml：
  "D:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/autocompiler.exe" \
      "D:/Code/MyMods/dst-mods/mods/wanda_planar_plan"
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))   # tools/<mod>/
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from PIL import Image  # noqa: E402

import gen_wanda_icons as G  # noqa: E402

MOD_DIR = os.path.join(REPO, "mods", "wanda_planar_plan")
# ★ 必须在 mod **根目录**：引擎按 "MODS_ROOT/<mod>/"..icon_atlas 拼路径（scripts/modindex.lua:543），
#   放到 images/ 下会在加载时被判为 invalid 并静默置 nil（日志只留一行 WARNING）
OUT = os.path.join(MOD_DIR, "modicon.png")

SIZE = 256          # 原版 mod 的 modicon 就是 256×256（解码 modicon.tex 实测）
DESIGN = G.DESIGN   # 64 设计空间，坐标照抄物品图标那套


def draw_modicon():
    # 4 倍超采样对 256 的成品足够（内部 1024 画布），画得也快
    a = G.Art(target=SIZE, ss=4)
    k = SIZE / DESIGN          # 设计单位 -> 输出像素

    # 后排：减速表（洋红），偏右上；前排：加速表（青绿），偏左下。
    # 两块都完整露脸（叠一半会看不清是"两块表"），整体外接框中心落在画布中心。
    G.draw_watch(a, G.SLOW, cx=42.0, cy=26.0, R=15.0,
                 hour=-20.0, hands=1, hand_len=1.5, chain=False, ticks=True)
    G.draw_watch(a, G.HASTE, cx=22.0, cy=37.0, R=16.5,
                 hour=-20.0, hands=1, hand_len=1.5, chain=False, ticks=True)

    img = a.finish(extra_light=0.55, grain=3)
    return img


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img = draw_modicon()
    if img.size != (SIZE, SIZE):
        img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(OUT)
    print("wrote", OUT, img.size, os.path.getsize(OUT), "bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
