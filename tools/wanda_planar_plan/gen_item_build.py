"""为新物品生成"专属地面外观"（自定义 anim build）。

背景：物品丢在地上显示的是 AnimState 的 bank/build，不是物品栏图片。
v4 之前三项复用了原版怀表/克劳斯袋的 build，只能靠 SetMultColour 区分。
本脚本用官方 scml 编译器生成真正独立的 build，画面来自 tools/wanda_planar_plan/gen_wanda_icons.py
里那个**和物品栏图标完全共用**的绘制函数（只是目标尺寸 128 而不是 64），
所以地上的东西和物品栏里的图标是同一张画，风格不会分裂。

管线（全是官方 Mod Tools 自带，无需额外安装）：
  1. 复用 gen_wanda_icons.render_item(name, 128) 画 128x128 精灵图（8 倍超采样 + 抗锯齿 + 描边）
  2. 生成 .scml（Spriter 工程格式，纯 XML，可脚本生成）
  3. scml.exe <in.scml> <outdir>  ->  <outdir>/anim/<name>.zip (anim.bin/build.bin/atlas-0.tex)
  4. 把 zip 拷进 mod 的 anim/ 目录

用法：
  python tools/wanda_planar_plan/gen_item_build.py            # 画图 + 编译 + 拷贝
  python tools/wanda_planar_plan/gen_item_build.py --no-compile   # 只画图 + 生成 scml（推荐：再用 bash 调 scml.exe）
"""

import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))   # tools/<mod>/
sys.path.insert(0, HERE)

from gen_wanda_icons import GROUND_SIZE, render_item  # noqa: E402  同一套画法

REPO = os.path.dirname(os.path.dirname(HERE))
COMMON = os.path.join(REPO, "tools", "common")   # 通用工具目录
sys.path.insert(0, COMMON)
# scml.exe：默认按常见安装位置猜，可用环境变量 DST_MOD_TOOLS 覆盖（别把本机路径写死进仓库）
def _find_scml():
    env = os.environ.get("DST_MOD_TOOLS")
    candidates = []
    if env:
        candidates.append(os.path.join(env, "scml.exe"))
    candidates += [
        "D:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/scml.exe",
        "C:/Program Files (x86)/Steam/steamapps/common/Don't Starve Mod Tools/mod_tools/scml.exe",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return candidates[-1]


BUILD_TOOLS = _find_scml()
OUT_ANIM = os.path.join(REPO, "mods", "wanda_planar_plan", "anim")
SCRATCH = os.path.join(REPO, ".scratch", "wanda-planar-plan", "v5", "builds")

S = GROUND_SIZE  # 精灵边长（= gen_wanda_icons 的设计空间 2 倍）

ITEMS = ("wanda_haste_watch", "wanda_slow_watch", "wanda_watch_bag")

# 三不要（看 docs/dst-modding-pitfalls.md §5.3）：
#   - 动画名必须含 idle / idle_loop / anim / cooldown_long / cooldown_short / swap
#   - object/timeline 名必须是 watchprop（怀表类会 OverrideSymbol("watchprop", ...)）
#   - entity 名 = build 名
ANIMS = ["idle", "idle_loop", "cooldown_long", "cooldown_short", "swap", "anim"]

_ANIM_TPL = """		<animation id="{aid}" length="1000" name="{anim}">
			<mainline>
				<key id="0">
					<object_ref abs_a="1" abs_angle="360" abs_pivot_x="0.5" abs_pivot_y="0.5" abs_scale_x="1" abs_scale_y="1" abs_x="0" abs_y="0" file="0" folder="0" id="0" key="0" name="watchprop" timeline="0" z_index="0"/>
				</key>
			</mainline>
			<timeline id="0" name="watchprop">
				<key id="0" spin="0">
					<object angle="0.0" file="0" folder="0" id="0" scale_x="1.0" scale_y="1.0" x="0" y="0"/>
				</key>
			</timeline>
		</animation>
"""

SCML_HEAD = """<?xml version="1.0" ?>
<spriter_data generator="BrashMonkey Spriter" generator_version="b5" scml_version="1.0">
	<folder id="0" name="spr">
		<file height="{h}" id="0" name="spr/sprite-0.png" pivot_x="0.5" pivot_y="0.5" width="{w}"/>
	</folder>
	<entity id="0" name="{name}">
"""

SCML_TAIL = """	</entity>
</spriter_data>
"""


def build_scml(name):
    body = "".join(_ANIM_TPL.format(aid=i, anim=a) for i, a in enumerate(ANIMS))
    return SCML_HEAD.format(h=S, w=S, name=name) + body + SCML_TAIL


def gen_one(name, compile_it=True):
    work = os.path.join(SCRATCH, name)
    spr = os.path.join(work, "spr")
    os.makedirs(spr, exist_ok=True)

    # 和物品栏图标同一套画法，只是画布 128（设计空间 2 倍）
    render_item(name, target=S).save(os.path.join(spr, "sprite-0.png"))

    scml_path = os.path.join(work, name + ".scml")
    with open(scml_path, "w", encoding="utf-8") as f:
        f.write(build_scml(name))

    if not compile_it:
        print("画好:", os.path.join(spr, "sprite-0.png"))
        return None

    # scml.exe 会去 PATH 里找 python.exe 来跑它的编译脚本。
    # 从 bash 启动的 python 继承的是 POSIX 风格 PATH（/c/...），Windows 程序读不懂，
    # 于是报 "Unable to find python!"；这里显式塞入解释器目录的 Windows 路径。
    env = os.environ.copy()
    env["PATH"] = os.path.dirname(sys.executable) + ";" + env.get("PATH", "")
    proc = subprocess.run([BUILD_TOOLS, scml_path, work],
                          capture_output=True, text=True, env=env)
    zip_path = os.path.join(work, "anim", name + ".zip")
    if not os.path.exists(zip_path):
        print("编译失败:", name, proc.stdout[-500:], proc.stderr[-500:])
        return None

    os.makedirs(OUT_ANIM, exist_ok=True)
    dst = os.path.join(OUT_ANIM, name + ".zip")
    shutil.copyfile(zip_path, dst)
    print("编译成功:", dst, os.path.getsize(dst), "字节")
    return dst


def main():
    compile_it = "--no-compile" not in sys.argv
    for name in ITEMS:
        gen_one(name, compile_it)


if __name__ == "__main__":
    main()
