"""wanda_planar_plan 全部美术资源的绘制核心（物品栏图标 + 地面/手持外观共用一个函数）。

为什么要重写（v5 需求 7 "图标要能发布"）：
  v4 的图标是"几何矢量"画法——正圆 + 均匀描边 + 单色填充，和原版图标并排一眼假：
  原版怀表图标是 3/4 侧视（倾斜的椭圆表盘）、带表链、大量墨线排线（hatch）和双色明暗。
  本文件因此改成"贴纸/手绘"画法：
    1. 所有圆都是 96 边形 + 轻微半径抖动（不用 ImageDraw.ellipse，避免完美几何圆）；
    2. 每个部件三层色：底色 / 暗部月牙 / 高光月牙（光源固定左上）；
    3. 金属面刷向心细排线（brush），皮革面撒短促墨线 + 针脚，都是低透明度叠色；
    4. 整张图最后叠一层左上亮右下暗的软光，统一氛围；
    5. 8 倍超采样 + 预乘 alpha 的 LANCZOS 缩小 + 透明边缘颜色扩散（防 mipmap 黑边）。

尺寸约定：全部坐标写在 64×64 的"设计空间"里（1 单位 = 64px 图标上的 1px）。
  物品栏图标 = 设计空间 1:1；地面/手持精灵 = 设计空间 2:1（128px）。同一套画法，
  所以图标和地上看到的是同一个东西，只是像素密度不同。

用法：
  python tools/wanda_planar_plan/gen_wanda_icons.py                  # 重出三张 64x64 PNG + 预览拼图
  python tools/wanda_planar_plan/gen_wanda_icons.py --preview-only   # 只重出预览（tex 编译完后用）
  # 然后删旧 .tex/.xml 再跑官方 autocompiler（按时间戳跳过，必须先删）：
  rm -f mods/wanda_planar_plan/images/inventoryimages/wanda_*.{tex,xml}
  "D:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/autocompiler.exe" \
      "D:/Code/MyMods/dst-mods/mods/wanda_planar_plan"

地面外观走 tools/wanda_planar_plan/gen_item_build.py（它 import 本文件的 render_item）。
"""

import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))   # tools/<mod>/
REPO = os.path.dirname(os.path.dirname(HERE))
COMMON = os.path.join(REPO, "tools", "common")   # 通用工具目录
sys.path.insert(0, COMMON)
OUT_DIR = os.path.join(REPO, "mods", "wanda_planar_plan", "images", "inventoryimages")
ART_DIR = os.path.join(REPO, ".scratch", "wanda-planar-plan", "v5", "art")
PREVIEW_PATH = os.path.join(ART_DIR, "preview-4x.png")

DESIGN = 64.0        # 设计空间边长（1 单位 = 图标上的 1px）
SS = 8               # 超采样倍数（图标画布 512，地面画布 1024）
ICON_SIZE = 64
GROUND_SIZE = 128
# 每件物品在设计空间里的微调（单位=设计格）。都是为了留出 2~4px 边距：
#   表：表链顶到 y=1 太空、下面还空 9px，整体下移 1.5
#   袋：袋身画得靠下，下沿会贴到画布边（被切平），整体上提 2.4
ITEM_OFFSET = {
    "wanda_haste_watch": (0.0, 1.5),
    "wanda_slow_watch": (0.0, 1.5),
    "wanda_watch_bag": (0.0, -2.4),
}
ALPHA_FLOOR = 6      # 低于这个不透明度当作透明（防预乘往返产生的彩色噪点）

TAU = math.tau

# ---------------------------------------------------------------- 配色
# 定稿见 .scratch/wanda-planar-plan/v4/palette.md §3。每个部件给 底/亮/暗 三档，
# 是 DST 贴纸风的关键（单色会显得很平）。
OUTLINE = (30, 24, 20, 255)      # 统一描边：暖黑（原版描边是 #1c1c1c 偏暖，不用纯黑）
CREAM = (250, 244, 226)
INK = (34, 28, 24)               # 指针/刻度的"墨色"

# 表壳统一用黄铜——原版怀表就是金壳 + 白盘 + 黑描边，这套"值结构"
# （黑描边 < 中间调黄铜 < 亮表盘）才是它一眼是怀表的原因，靠表盘颜色做区分。
HASTE = dict(
    rim=(58, 42, 18),            # 表壳外圈（压暗的黄铜）
    metal=(190, 156, 74),        # 黄铜壳
    metal_hi=(246, 222, 150),    # 金属高光
    metal_lo=(118, 88, 30),      # 金属暗部
    dial=(88, 208, 176),         # 表盘：薄荷青绿
    dial_hi=(170, 246, 220),     # 表盘高光
    dial_lo=(16, 92, 82),        # 表盘暗部
    glyph=CREAM,                 # 加速符号
)

SLOW = dict(
    rim=(44, 26, 18),
    metal=(164, 124, 66),        # 旧黄铜，比加速表旧一档
    metal_hi=(228, 188, 110),
    metal_lo=(94, 62, 22),
    dial=(206, 44, 140),         # 表盘：洋红
    dial_hi=(252, 150, 204),
    dial_lo=(92, 8, 64),
    glyph=CREAM,
)

LEATHER = dict(
    body=(150, 94, 52),          # 皮革棕
    hi=(186, 128, 70),           # 翻盖/受光面
    mid=(120, 70, 38),
    lo=(92, 52, 26),
    deep=(64, 34, 16),
    stitch=(238, 210, 164),
)

COPPER = dict(
    body=(206, 142, 70),
    hi=(248, 206, 136),
    lo=(124, 74, 28),
)

SAND = (238, 194, 104)           # 沙漏里的金砂
GLASS = (226, 232, 226)          # 沙漏玻璃

# 预览用的暗草地色，模拟图标在物品栏/地上的观感
GRASS = (56, 70, 40)


# ---------------------------------------------------------------- 几何工具

def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def lerp_c(c0, c1, t):
    return tuple(int(round(c0[i] + (c1[i] - c0[i]) * t)) for i in range(3))


def ell_pts(cx, cy, rx, ry=None, n=96, jitter=0.0, seed=0):
    """用多边形近似椭圆（不用 ImageDraw.ellipse），可加半径抖动做手绘感。"""
    ry = rx if ry is None else ry
    rng = random.Random(seed)
    pts = []
    for i in range(n):
        t = TAU * i / n
        j = 1.0 + (rng.uniform(-jitter, jitter) if jitter else 0.0)
        pts.append((cx + math.cos(t) * rx * j, cy + math.sin(t) * ry * j))
    return pts


def warp(pts, cx, cy, tilt=0.0, squash=1.0):
    """绕 (cx,cy) 先压扁 y 再旋转——3/4 侧视怀表就是这么来的。"""
    ca, sa = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
    out = []
    for x, y in pts:
        dx, dy = (x - cx), (y - cy) * squash
        out.append((cx + dx * ca - dy * sa, cy + dx * sa + dy * ca))
    return out


def catmull(ctrl, closed=True, subdiv=12):
    """Catmull-Rom 样条：给少量控制点，得到手绘感的平滑曲线。"""
    pts = list(ctrl)
    if closed:
        ext = [pts[-1]] + pts + [pts[0], pts[1]]
    else:
        ext = [pts[0]] + pts + [pts[-1]]
    out = []
    for i in range(len(ext) - 3):
        p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
        for s in range(subdiv):
            t = s / subdiv
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    if not closed:
        out.append(pts[-1])
    return out


def shift(pts, dx, dy):
    return [(x + dx, y + dy) for x, y in pts]


def polyline_lengths(pts):
    acc = [0.0]
    for i in range(1, len(pts)):
        acc.append(acc[-1] + math.dist(pts[i - 1], pts[i]))
    return acc


def point_at(pts, acc, dist):
    for i in range(1, len(acc)):
        if acc[i] >= dist:
            seg = acc[i] - acc[i - 1]
            t = 0.0 if seg <= 0 else (dist - acc[i - 1]) / seg
            x = pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * t
            y = pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * t
            dx = pts[i][0] - pts[i - 1][0]
            dy = pts[i][1] - pts[i - 1][1]
            ln = math.hypot(dx, dy) or 1.0
            return (x, y), (dx / ln, dy / ln)
    return pts[-1], (1.0, 0.0)


# ---------------------------------------------------------------- 画布

class Art:
    """超采样画布：坐标一律用 64 设计空间，内部乘 self.k 放大到画布像素。"""

    def __init__(self, target=ICON_SIZE, ss=SS, ox=0.0, oy=0.0):
        self.target = target
        self.k = (target * ss) / DESIGN
        self.size = int(round(DESIGN * self.k))
        self.ox, self.oy = ox, oy        # 整件物品在设计空间里的平移（构图微调用）
        self.img = Image.new("RGBA", (self.size, self.size), (0, 0, 0, 0))

    # ---------- 基础 ----------
    def q(self, pts):
        k, ox, oy = self.k, self.ox, self.oy
        return [((x + ox) * k, (y + oy) * k) for x, y in pts]

    def p1(self, x, y):
        """单个点的设计空间 -> 画布像素（spot/hatch/stitch/capsule 用）。"""
        return ((x + self.ox) * self.k, (y + self.oy) * self.k)

    def wpx(self, w):
        return max(1, int(round(w * self.k)))

    def sub(self):
        """新建一张同尺寸的空图层（用于需要 mask 裁剪的部件，例如被袋身裁掉的束带）。"""
        layer = Art(target=self.target)
        layer.k, layer.size = self.k, self.size
        layer.img = Image.new("RGBA", (self.size, self.size), (0, 0, 0, 0))
        return layer

    def mask(self, pts):
        m = Image.new("L", (self.size, self.size), 0)
        ImageDraw.Draw(m).polygon(self.q(pts), fill=255)
        return m

    def alpha(self):
        return self.img.getchannel("A")

    def clip(self, m):
        """把掩罩裁到"已经画上的像素"上，避免阴影糊到透明背景里。"""
        return ImageChops.multiply(m, self.alpha())

    def over(self, layer, mask=None):
        """alpha 合成（叠加半透明层，不会破坏原有 alpha）。"""
        if mask is not None:
            layer = layer.copy()
            layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
        self.img = Image.alpha_composite(self.img, layer)

    # ---------- 图元 ----------
    def poly(self, pts, fill=None, ol=None, w=1.9):
        q = self.q(pts)
        d = ImageDraw.Draw(self.img)
        if fill is not None:
            d.polygon(q, fill=fill)
        if ol is not None:
            d.line(q + [q[0], q[1]], fill=ol, width=self.wpx(w), joint="curve")

    def stroke(self, pts, color, w=1.0, closed=False):
        q = self.q(pts)
        if len(q) < 2:
            return
        if closed:
            q = q + [q[0], q[1]]
        ImageDraw.Draw(self.img).line(q, fill=color, width=self.wpx(w), joint="curve")

    def capsule(self, p0, p1, w, fill=None, ol=None, ow=0.9):
        def draw(width, color):
            x0, y0 = self.p1(p0[0], p0[1])
            x1, y1 = self.p1(p1[0], p1[1])
            ww = max(1, int(round(width * self.k)))
            d = ImageDraw.Draw(self.img)
            d.line([(x0, y0), (x1, y1)], fill=color, width=ww)
            r = ww / 2.0
            for x, y in ((x0, y0), (x1, y1)):
                d.ellipse([x - r, y - r, x + r, y + r], fill=color)

        if ol is not None:
            draw(w + 2 * ow, ol)
        if fill is not None:
            draw(w, fill)

    def dot(self, cx, cy, r, fill, ol=None, w=0.8):
        self.poly(ell_pts(cx, cy, r, r, n=40), fill=fill, ol=ol, w=w)

    # ---------- 明暗 ----------
    def tint(self, m, color, alpha=255):
        """在 mask 内盖一层纯色（低 alpha = 柔和洗色）。"""
        layer = Image.new("RGBA", (self.size, self.size), rgba(color, alpha))
        self.over(layer, self.clip(m))

    def crescent(self, outer_pts, inner_pts):
        return ImageChops.subtract(self.mask(outer_pts), self.mask(inner_pts))

    def spot(self, cx, cy, r, color, alpha=90, mask=None, soft=0.6):
        """软光斑：画实心圆再高斯模糊，模拟散射高光/体积暗部。"""
        layer = Image.new("RGBA", (self.size, self.size), (0, 0, 0, 0))
        px, py = self.p1(cx, cy)
        rr = r * self.k
        ImageDraw.Draw(layer).ellipse([px - rr, py - rr, px + rr, py + rr],
                                      fill=rgba(color, alpha))
        layer = layer.filter(ImageFilter.GaussianBlur(max(1.0, soft * r * self.k)))
        self.over(layer, mask if mask is not None else self.alpha())

    def hatch(self, mask, color, bbox, n=90, length=(1.4, 3.4), width=0.75,
              alpha=52, seed=3, angle=None, spread=0.35):
        """墨线排线：手绘感的来源。angle 给 None 则随机方向，给了则近似平行。"""
        rng = random.Random(seed)
        layer = Image.new("RGBA", (self.size, self.size), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        x0, y0, x1, y1 = bbox
        for _ in range(n):
            x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
            a = rng.uniform(0, TAU) if angle is None else \
                math.radians(angle) + rng.uniform(-spread, spread)
            ln = rng.uniform(*length)
            d.line([self.p1(x, y),
                    self.p1(x + math.cos(a) * ln, y + math.sin(a) * ln)],
                   fill=rgba(color, alpha), width=self.wpx(width))
        self.over(layer, self.clip(mask))

    def stitch(self, path, color, step=2.6, length=1.5, w=0.75, alpha=235, along=0.0):
        """沿路径打垂直于走向的小针脚（皮革缝线）。"""
        acc = polyline_lengths(path)
        total = acc[-1]
        d = ImageDraw.Draw(self.img)
        dist = step * 0.5
        while dist < total - 0.2:
            (x, y), (dx, dy) = point_at(path, acc, dist)
            nx, ny = -dy, dx
            x += dx * along
            y += dy * along
            d.line([self.p1(x - nx * length / 2, y - ny * length / 2),
                    self.p1(x + nx * length / 2, y + ny * length / 2)],
                   fill=rgba(color, alpha), width=self.wpx(w))
            dist += step

    # ---------- 收尾 ----------
    def light(self, strength=1.0):
        """左上亮右下暗的全局软光，把散的部件压成一个整体。"""
        w = self.size
        g = Image.linear_gradient("L").resize((w, w), Image.BILINEAR)  # 上黑下白
        g = g.rotate(-35, resample=Image.BILINEAR, expand=False)
        bright = Image.new("RGBA", (w, w), rgba((255, 250, 238), 0))
        bright.putalpha(g.point(lambda v: int(max(0, 140 - v) * 0.22 * strength)))
        self.over(bright, self.alpha())
        dark = Image.new("RGBA", (w, w), rgba((26, 16, 12), 0))
        dark.putalpha(g.point(lambda v: int(max(0, v - 118) * 0.26 * strength)))
        self.over(dark, self.alpha())

    def finish(self, extra_light=1.0, grain=7):
        if extra_light:
            self.light(extra_light)
        small = self.img.convert("RGBa").resize((self.target, self.target), Image.LANCZOS)
        small = small.convert("RGBA")
        if grain:
            small = add_grain(small, grain)
        return bleed_transparent(small)


def add_grain(img, amount=7, seed=17):
    """最后一道"纸张颗粒"：整图乘一层极轻的噪声（±amount 色阶）。

    DST 的贴图都带纸张/颜料颗粒感，纯平滑渐变的图标放在原版旁边会显得"塑料"。
    噪声必须加在**缩小之后**，超采样阶段加会被 LANCZOS 抹平。
    """
    w, h = img.size
    rnd = random.Random(seed)
    noise = Image.new("L", (w, h))
    noise.putdata([max(0, min(255, 255 - int(rnd.gauss(0, amount)))) for _ in range(w * h)])
    rgb = ImageChops.multiply(img.convert("RGB"), noise.convert("RGB"))
    out = img.copy()
    out.paste(rgb, (0, 0), img.getchannel("A"))
    return out


def bleed_transparent(img, passes=12):
    """把不透明像素的颜色向透明区扩散几圈（alpha 保持 0）。

    缩放后透明像素 RGB 是黑的，DXT5 + mipmap 会把它渗进边缘，游戏里看起来像一圈黑边。
    """
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            if px[x, y][3] < ALPHA_FLOOR:
                px[x, y] = (0, 0, 0, 0)
    colored = [[px[x, y][3] > 0 for x in range(w)] for y in range(h)]
    for _ in range(passes):
        snap = [[px[x, y] for x in range(w)] for y in range(h)]
        added = False
        for y in range(h):
            for x in range(w):
                if colored[y][x]:
                    continue
                acc, n = [0, 0, 0], 0
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and colored[ny][nx]:
                        c = snap[ny][nx]
                        acc[0] += c[0]
                        acc[1] += c[1]
                        acc[2] += c[2]
                        n += 1
                if n:
                    px[x, y] = (acc[0] // n, acc[1] // n, acc[2] // n, 0)
                    colored[y][x] = True
                    added = True
        if not added:
            break
    return img


# ---------------------------------------------------------------- 怀表

def arc(cx, cy, r, a0, a1, n=32, ry=None):
    """角度弧（度，0=右、90=下）。用来画贴外沿的高光/反光弧。"""
    ry = r if ry is None else ry
    return [(cx + math.cos(math.radians(a0 + (a1 - a0) * i / max(1, n - 1))) * r,
             cy + math.sin(math.radians(a0 + (a1 - a0) * i / max(1, n - 1))) * ry)
            for i in range(n)]


def draw_watch(a, pal, cx=31.6, cy=34.4, R=20.4,
               hour=-118.0, minute=-30.0, chain=None, bail=True, seed=11,
               ticks=True, dial_ratio=0.775, hands=2, hand_len=1.0,
               hand_scale=1.0, needle=False):
    """**正圆**怀表（v6 需求 1）。

    v5 是 3/4 侧视（squash 0.79 + tilt -17°），缩到 46px 就是一颗鸡蛋，用户看得出来。
    原版 pocketwatch 图标是正圆表盘 + 粗黑描边 + 平涂三色，所以这里改回正圆，
    并且把 v5 那些"细排线 / 纸颗粒"全部去掉——那些在 46px 上只会糊成一层灰。
    立体感只靠三样东西：外沿一道高光弧、右下月牙暗部、盘沿内阴影。
    """
    ink = rgba(INK)
    dr = R * dial_ratio            # 表盘半径
    ring = R - dr                  # 表圈宽度
    if chain is None:
        # 只在 128px 的地面/手持精灵上挂链子：46px 的图标上链环会糊成一串珠子
        chain = a.target > ICON_SIZE

    # --- 表链：三个链环串成一条（先画，会被表壳压住一截）---
    if chain:
        # v6：三个独立链环缩到 46px 就是"一串珠子"（用户说图标奇怪的一部分）。
        # 改成**一条链绳**：墨色描边 + 金属芯 + 斜向链节刻度，大尺寸看是链子，
        # 小尺寸看是一条挂绳，两种尺寸都不脏。绳子从吊环往下垂到表壳左侧。
        cord = catmull([(cx - 2.2, cy - R - 1.8), (cx - R - 2.4, cy - R + 3.4),
                        (cx - R - 2.0, cy - R + 9.0), (cx - R + 0.4, cy - R + 13.4)],
                       closed=False, subdiv=8)
        a.stroke(cord, rgba(OUTLINE), w=2.9)
        a.stroke(cord, rgba(pal["metal"]), w=1.5)
        a.stitch(cord, INK, step=3.0, length=1.7, w=0.8, alpha=160)
        # 链尾的挂钩
        a.dot(cx - R + 0.8, cy - R + 14.8, 1.45, rgba(pal["metal_hi"]), ol=OUTLINE, w=1.1)

    # --- 吊环（真透的孔）+ 表冠 ---
    by = cy - R - 3.4
    if bail:
        a.poly(ell_pts(cx, by, 3.7, 3.4, n=48, jitter=0.018, seed=seed + 20),
               fill=rgba(pal["metal"]), ol=OUTLINE, w=1.95)
        a.poly(ell_pts(cx, by, 1.85, 1.62, n=40), fill=(0, 0, 0, 0))
        a.stroke(arc(cx - 0.5, by - 0.5, 3.0, 192, 248, n=14),
                 rgba(pal["metal_hi"], 230), w=1.15)
    crown = [(cx - 3.4, cy - R + 1.4), (cx + 3.4, cy - R + 1.4),
             (cx + 2.7, cy - R - 2.3), (cx - 2.7, cy - R - 2.3)]
    a.poly(crown, fill=rgba(pal["metal"]), ol=OUTLINE, w=1.6)
    a.poly([(cx - 2.8, cy - R + 0.6), (cx - 1.1, cy - R + 0.6),
            (cx - 1.1, cy - R - 1.7), (cx - 2.4, cy - R - 1.7)],
           fill=rgba(pal["metal_hi"], 215))

    # --- 表壳：平涂 + 右下月牙暗部 + 外沿高光弧 ---
    outer = ell_pts(cx, cy, R, R, n=120, jitter=0.006, seed=seed)
    a.poly(outer, fill=rgba(pal["metal"]), ol=OUTLINE, w=2.3)
    a.tint(a.crescent(outer, ell_pts(cx - ring * 0.6, cy - ring * 0.65, R, R, n=120)),
           pal["metal_lo"], 135)
    a.stroke(arc(cx - 0.35, cy - 0.45, R - 0.95, 190, 246, n=28),
             rgba(pal["metal_hi"], 230), w=1.3)
    a.stroke(arc(cx - 0.55, cy - 0.7, R - 1.9, 194, 230, n=16),
             rgba((255, 252, 236), 175), w=0.9)
    a.stroke(arc(cx + 0.3, cy + 0.5, R - 1.15, 18, 76, n=20),
             rgba(pal["metal_hi"], 110), w=0.95)

    # --- 表盘 ---
    dial = ell_pts(cx, cy, dr, dr, n=120, jitter=0.004, seed=seed + 2)
    a.poly(dial, fill=rgba(pal["dial"]))
    dm = a.mask(dial)
    a.tint(ImageChops.subtract(dm, a.mask(ell_pts(cx - 1.5, cy - 1.8, dr, dr, n=120))),
           lerp_c(pal["dial_lo"], (0, 0, 0), 0.25), 100)
    a.spot(cx - dr * 0.30, cy - dr * 0.38, dr * 0.70, pal["dial_hi"], 62,
           mask=dm, soft=0.85)
    # 表圈与表盘之间的分界墨线（原版就是靠这一圈把金壳和表盘切开）
    a.stroke(ell_pts(cx, cy, dr + 0.35, dr + 0.35, n=120),
             rgba(lerp_c(pal["rim"], (0, 0, 0), 0.5), 235), w=1.4)

    # --- 时标：4 个长点 + 8 个微点（再多就成噪点了）---
    if ticks:
        tc = rgba(lerp_c(pal["dial_lo"], INK, 0.45), 235)
        for i in range(12):
            ang = math.radians(i * 30)
            major = (i % 3 == 0)
            rr = dr * (0.795 if major else 0.845)
            a.dot(cx + math.sin(ang) * rr, cy - math.cos(ang) * rr,
                  0.95 if major else 0.52, tc)

    # --- 指针：带尖的锥形，先投影再墨色本体 ---
    def hand(deg, length, wbase, wtip, tail=0.0):
        ang = math.radians(deg)
        ux, uy = math.sin(ang), -math.cos(ang)
        nx, ny = -uy, ux
        tip = (cx + ux * length, cy + uy * length)
        base = (cx - ux * tail, cy - uy * tail)
        pts = [(base[0] + nx * wbase, base[1] + ny * wbase),
               (tip[0] + nx * wtip, tip[1] + ny * wtip),
               (tip[0] - nx * wtip, tip[1] - ny * wtip),
               (base[0] - nx * wbase, base[1] - ny * wbase)]
        a.poly(shift(pts, 0.5, 0.55),
               fill=rgba(lerp_c(pal["dial_lo"], (0, 0, 0), 0.30), 95))
        a.poly(pts, fill=ink)

    if needle:
        # 徽记太小（表盘 13px），指针画细了就糊——直接一根实心三角针
        a.poly([(cx - dr * 0.66, cy - dr * 0.52), (cx - dr * 0.10, cy - dr * 0.20),
                (cx + dr * 0.10, cy + dr * 0.14), (cx - dr * 0.34, cy - dr * 0.02)],
               fill=ink)
    else:
        hand(hour, dr * 0.46 * hand_len, 1.75 * hand_scale, 0.55 * hand_scale,
             tail=0.30 * hand_len)
        if hands > 1:
            hand(minute, dr * 0.70 * hand_len, 0.95 * hand_scale, 0.26 * hand_scale,
                 tail=1.30 * hand_len)
    cap_r = max(1.15, R * 0.085)
    a.dot(cx, cy, cap_r, ink)
    a.dot(cx - cap_r * 0.32, cy - cap_r * 0.36, max(0.45, cap_r * 0.42),
          rgba(pal["metal_hi"]))

    # --- 玻璃上的一道弧光（压在指针上=指针在玻璃下面）---
    a.stroke(arc(cx - 0.6, cy - 0.9, dr * 0.70, 206, 238, n=14),
             rgba((255, 255, 255), 55), w=0.9)


# ---------------------------------------------------------------- 加速符号（双箭头）

def glyph_arrows(a, color=INK, x=31.6, y=44.4, step=6.6, w=5.0, h=4.6, thick=2.7):
    """两个向右的**实心**箭头（»）。

    v6 的定稿：整块多边形，不是描边线。46px 的图标上只有"实心块"能活下来，
    2px 的描边会被 LANCZOS 缩成一团灰（v6 试过 4 个版本才确认这一点）。
    """
    for k in range(2):
        ox = x + (k - 0.5) * step
        outer = [(ox - w * 0.55, y - h), (ox + w * 0.60, y), (ox - w * 0.55, y + h)]
        inner = [(ox - w * 0.55 + thick, y + h - thick * 0.60),
                 (ox + w * 0.60 - thick * 1.5, y),
                 (ox - w * 0.55 + thick, y - h + thick * 0.60)]
        a.poly(outer + inner, fill=rgba(color))


# ---------------------------------------------------------------- 减速符号（沙漏）

def glyph_hourglass(a, x=31.6, y=44.0, w=10.4, h=9.8, sand=SAND):
    """沙漏**实心剪影**：上下横梁 + 两个实心三角 + 下斗金砂。"""
    hw = w * 0.5
    top, bot = y - h * 0.5, y + h * 0.5
    for yy in (top, bot - 1.7):
        a.poly([(x - hw - 0.6, yy), (x + hw + 0.6, yy),
                (x + hw + 0.6, yy + 1.7), (x - hw - 0.6, yy + 1.7)], fill=rgba(INK))
    a.poly([(x - hw + 0.1, top + 1.6), (x + hw - 0.1, top + 1.6), (x, y - 0.3)],
           fill=rgba(INK))
    a.poly([(x - hw + 0.1, bot - 1.6), (x + hw - 0.1, bot - 1.6), (x, y + 0.3)],
           fill=rgba(INK))
    # 下斗的金砂（也是"砂正在往下漏"的信号）
    a.poly([(x - hw * 0.60, bot - 2.2), (x + hw * 0.60, bot - 2.2), (x, y + 1.6)],
           fill=rgba(sand))


# ---------------------------------------------------------------- 配色微调

def pal_slow_shadow():
    return lerp_c(SLOW["dial_lo"], (40, 40, 60), 0.6)


# ---------------------------------------------------------------- 钟表袋

def draw_bag(a, leather=LEATHER, copper=COPPER, seed=23):
    """皮革钟表袋：平涂分块 + 针脚 + 铜扣 + 怀表徽记。

    v6 去掉了 v5 的皮革颗粒排线和多层软光斑——46px 上那些只会让袋子显脏；
    体积感改成"大月牙暗部 + 顶部亮带 + 粗墨描边"三件套。
    """
    rng = random.Random(seed)

    # --- 袋身（上窄下宽，控制点带微抖动）---
    body_ctrl = [(12.4, 24.4), (11.6, 34.8), (12.8, 45.4), (15.6, 54.0),
                 (21.2, 60.0), (31.4, 61.4), (42.0, 60.4), (48.8, 54.2),
                 (51.8, 45.0), (52.6, 34.4), (51.6, 24.2)]
    body_ctrl = [(x + rng.uniform(-0.35, 0.35), y + rng.uniform(-0.3, 0.3))
                 for x, y in body_ctrl]
    body = catmull(body_ctrl, closed=True, subdiv=8)
    a.poly(body, fill=rgba(leather["body"]), ol=OUTLINE, w=2.3)
    body_mask = a.mask(body)
    # 体积：右下月牙压暗 + 顶部亮带 + 底部最暗
    a.tint(ImageChops.subtract(body_mask, a.mask(shift(body, -4.6, -2.4))),
           leather["lo"], 120)
    a.tint(ImageChops.subtract(body_mask, a.mask(shift(body, 0.0, 2.6))),
           leather["hi"], 70)
    a.spot(31.0, 61.0, 19.0, leather["deep"], 120, mask=body_mask, soft=0.7)

    # 底部两道折痕（皮革被压出来的体积）
    a.stroke(catmull([(17.4, 47.4), (19.2, 53.0), (23.2, 56.6)], closed=False, subdiv=6),
             rgba(leather["deep"], 115), w=0.8)
    a.stroke(catmull([(46.0, 47.8), (44.4, 53.4), (40.6, 56.9)], closed=False, subdiv=6),
             rgba(leather["deep"], 100), w=0.75)

    # 侧面竖缝（针脚）
    a.stitch(catmull([(15.6, 29.0), (15.0, 41.0), (17.0, 51.0)], closed=False, subdiv=6),
             leather["stitch"], step=3.1, length=1.7, w=0.95, alpha=235)
    a.stitch(catmull([(48.0, 29.0), (48.6, 41.0), (46.4, 51.0)], closed=False, subdiv=6),
             leather["stitch"], step=3.1, length=1.7, w=0.95, alpha=195)

    # --- 袋口翻盖 ---
    flap = catmull([(11.6, 17.8), (21.0, 15.6), (32.0, 15.1), (43.0, 15.6),
                    (52.4, 17.8), (51.4, 25.6), (44.8, 31.4), (32.0, 33.8),
                    (19.2, 31.4), (12.6, 25.6)], closed=True, subdiv=8)
    a.poly(flap, fill=rgba(leather["hi"]), ol=OUTLINE, w=2.15)
    flap_mask = a.mask(flap)
    a.tint(ImageChops.subtract(flap_mask, a.mask(shift(flap, -1.6, -3.0))),
           leather["mid"], 155)
    a.tint(ImageChops.subtract(flap_mask, a.mask(shift(flap, 1.2, 3.0))),
           (255, 230, 184), 30)
    # 翻盖压在袋身上的影子
    a.tint(a.mask(catmull([(13.6, 26.4), (32.0, 35.2), (50.6, 26.4), (49.8, 31.6),
                           (32.0, 39.4), (14.4, 31.6)], closed=True, subdiv=8)),
           leather["deep"], 100)
    # 翻盖下缘缝线
    seam = catmull([(15.2, 24.4), (32.0, 31.0), (48.8, 24.2)], closed=False, subdiv=10)
    a.stitch(shift(seam, 0.0, 1.0), leather["deep"], step=3.2, length=1.6, w=1.0, alpha=150)
    a.stitch(seam, leather["stitch"], step=3.0, length=1.2, w=0.85, alpha=180)
    # 翻盖上沿亮边
    a.stroke(catmull([(13.6, 18.9), (24.0, 17.0), (32.0, 16.6), (41.0, 17.0),
                      (50.6, 18.9)], closed=False, subdiv=8),
             rgba((255, 236, 198), 140), w=0.9)

    # --- 束带 ---
    strap_poly = catmull([(12.6, 34.2), (20.0, 33.6), (32.0, 34.4), (44.4, 33.6),
                          (51.4, 34.2), (51.8, 41.6), (44.4, 42.4), (32.0, 43.0),
                          (20.0, 42.2), (12.4, 41.6)], closed=True, subdiv=6)
    strap = a.sub()
    strap.poly(strap_poly, fill=rgba(lerp_c(leather["mid"], leather["deep"], 0.5)),
               ol=OUTLINE, w=1.7)
    strap.tint(ImageChops.subtract(strap.mask(strap_poly),
                                  strap.mask(shift(strap_poly, -1.0, -1.6))),
               (255, 214, 160), 80)
    a.over(strap.img, body_mask)

    # --- 铜扣：方框 + 方孔 + 扣针 ---
    buckle = catmull([(25.8, 31.0), (38.4, 31.0), (38.8, 43.8), (25.4, 43.8)],
                     closed=True, subdiv=4)
    a.poly(buckle, fill=rgba(copper["body"]), ol=OUTLINE, w=1.8)
    a.poly([(29.2, 34.4), (34.8, 34.4), (35.0, 40.4), (29.0, 40.4)],
           fill=rgba(lerp_c(leather["deep"], (0, 0, 0), 0.35)))
    a.capsule((31.9, 32.4), (31.9, 42.2), 1.7, fill=rgba(copper["hi"]), ol=OUTLINE, ow=0.65)
    a.tint(a.crescent(buckle, shift(buckle, 2.0, 2.4)), copper["hi"], 170)
    a.spot(28.2, 33.4, 3.2, copper["hi"], 130, mask=a.mask(buckle), soft=0.9)

    # --- 袋口铆钉 ---
    for rx in (16.2, 47.8):
        a.dot(rx, 19.2, 1.35, rgba(copper["body"]), ol=OUTLINE, w=0.7)
        a.dot(rx - 0.35, 18.8, 0.5, rgba(copper["hi"]))

    # --- 右下角怀表徽记（正圆，同主表画法）---
    badge_pal = dict(rim=(58, 40, 24), metal=copper["body"], metal_hi=copper["hi"],
                     metal_lo=copper["lo"], dial=(238, 226, 198),
                     dial_hi=(252, 248, 230), dial_lo=(120, 92, 52))
    draw_watch(a, badge_pal, cx=44.6, cy=49.6, R=8.7,
               hour=-96.0, minute=-18.0, chain=False, seed=seed + 31,
               ticks=False, dial_ratio=0.72, needle=True)


# ---------------------------------------------------------------- 三个物品

def _compose(name, a):
    """把一件物品画到给定画布上（图标和地面共用的唯一入口）。

    v6 构图（试了 5 个版本定的）：单根指针指向上方 + 下半盘留给区分符号。
    两根指针斜插时，46px 上和符号挤成一团黑（用户说"图标还是有点奇怪"就是这个）。
    """
    if name == "wanda_haste_watch":
        draw_watch(a, HASTE, hour=-20.0, hands=1, hand_len=1.5)
        glyph_arrows(a)
    elif name == "wanda_slow_watch":
        draw_watch(a, SLOW, hour=-20.0, hands=1, hand_len=1.5)
        glyph_hourglass(a)
    elif name == "wanda_watch_bag":
        draw_bag(a)
    else:
        raise KeyError(name)


def render_item(name, target=ICON_SIZE):
    """渲染一件物品：target=64 出物品栏图标，target=128 出地面/手持精灵。

    两个尺寸走的是同一个 `_compose`，所以图标和地上看到的是同一张画，
    只是像素密度不同（设计空间 64 单位映射到 64 或 128 px）。
    """
    ox, oy = ITEM_OFFSET.get(name, (0.0, 0.0))
    a = Art(target=target, ox=ox, oy=oy)
    _compose(name, a)
    return a.finish(extra_light=0.55, grain=4)


ICON_NAMES = ("wanda_haste_watch", "wanda_slow_watch", "wanda_watch_bag")


# ---------------------------------------------------------------- 输出

def write_icons():
    os.makedirs(OUT_DIR, exist_ok=True)
    out = []
    for name in ICON_NAMES:
        path = os.path.join(OUT_DIR, name + ".png")
        render_item(name, ICON_SIZE).save(path)
        out.append(path)
        print("wrote", path)
    return out


def _preview_font(size=15):
    """预览图上的标注：优先系统中文黑体（默认位图字体没有汉字，会画成方框）。"""
    for path in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf",
                 "/System/Library/Fonts/PingFang.ttc", "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def _load_tex(tex_path):
    try:
        import ktex2png
    except Exception:
        sys.path.insert(0, HERE)
        import ktex2png
    return ktex2png.ktex_to_image(tex_path)


def write_preview(png_paths):
    """对比图：每列一件物品 = 图标 4× / 地面精灵 4× / 解码 tex 4×，底部一条原版图标参照。"""
    os.makedirs(ART_DIR, exist_ok=True)
    font = _preview_font(15)

    labels = ["haste", "slow", "bag"]
    pad, lab, zoom = 12, 22, 4
    cell = GROUND_SIZE * zoom                    # 512
    W = pad + len(png_paths) * (cell + pad)
    ref_h = 64 * 4 + lab + pad
    H = pad + 3 * (cell + lab + pad) + ref_h
    sheet = Image.new("RGBA", (W, H), GRASS)
    d = ImageDraw.Draw(sheet)

    for c, path in enumerate(png_paths):
        name = os.path.basename(path)[:-4]
        x = pad + c * (cell + pad)
        y = pad

        icon = Image.open(path).convert("RGBA")
        ic = icon.resize((ICON_SIZE * zoom, ICON_SIZE * zoom), Image.NEAREST)
        # 图标只占一格的四分之一，居中放，对比图才不会左重右轻
        sheet.alpha_composite(ic, (x + (cell - ic.size[0]) // 2, y))
        d.text((x + (cell - ic.size[0]) // 2, y + ic.size[1] + 3), labels[c] + " 图标 4x",
               fill=(238, 238, 232, 255), font=font)
        y += cell + lab + pad

        gp = os.path.join(REPO, ".scratch", "wanda-planar-plan", "v5", "builds",
                          name, "spr", "sprite-0.png")
        if os.path.exists(gp):
            ground = Image.open(gp).convert("RGBA")
            sheet.alpha_composite(ground.resize((cell, cell), Image.LANCZOS), (x, y))
        d.text((x, y + cell + 3), labels[c] + " 地面 4x",
               fill=(238, 238, 232, 255), font=font)
        y += cell + lab + pad

        tex = path[:-4] + ".tex"
        if os.path.exists(tex):
            dec = _load_tex(tex).transpose(Image.FLIP_TOP_BOTTOM)
            dc = dec.resize((ICON_SIZE * zoom, ICON_SIZE * zoom), Image.NEAREST)
            sheet.alpha_composite(dc, (x + (cell - dc.size[0]) // 2, y))
            d.text((x + (cell - dc.size[0]) // 2, y + dc.size[1] + 3), labels[c] + " 解码 tex 4x（已翻正）",
                   fill=(200, 235, 200, 255), font=font)

    # 底部：原版怀表图标（风格参照）
    ref = os.path.join(ART_DIR, "ref", "orig-watch-icons-6x.png")
    if os.path.exists(ref):
        r = Image.open(ref).convert("RGBA")
        r = r.resize((int(r.size[0] * 4 / 6), int(r.size[1] * 4 / 6)), Image.LANCZOS)
        sheet.alpha_composite(r, (pad, H - ref_h + lab // 2))
        d.text((pad, H - ref_h + 2), "原版 pocketwatch 图标（风格参照）",
               fill=(255, 240, 180, 255), font=font)

    sheet.convert("RGB").save(PREVIEW_PATH)
    print("wrote", PREVIEW_PATH)
    return PREVIEW_PATH


def main():
    if "--preview-only" in sys.argv[1:]:
        write_preview([os.path.join(OUT_DIR, name + ".png") for name in ICON_NAMES])
        return
    pngs = write_icons()
    write_preview(pngs)
    print("\n下一步：删旧 .tex/.xml，再用 autocompiler 重编（见文件头注释）")


if __name__ == "__main__":
    main()
