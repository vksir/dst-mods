# tools/wanda_planar_plan —— 「旺达位面计划」专用生成器

只服务 `mods/wanda_planar_plan/`。两个脚本分工：

| 脚本 | 负责 | 产物 |
|---|---|---|
| `gen_wanda_icons.py` | **2D 图标**（64×64 png）+ 4 倍预览拼图 | `images/inventoryimages/wanda_{haste,slow}_watch,wanda_watch_bag.png` |
| `gen_item_build.py` | **地面精灵**（128×128）+ 生成 scml + 调 `scml.exe` | `anim/wanda_*.zip` |
| `gen_workshop_preview.py` | **工坊预览图**：解 anim 里的 128px 精灵，三件横排 + 标题 | `preview.jpg`（268×268，上传器读取） |
| `gen_modicon.py` | **Mods 列表图标**：两块表斜叠（洋红后 / 青绿前），复用物品图标那套画法 | `modicon.png`（256×256，**mod 根目录**）+ autocompiler 出的 tex/xml |

`gen_item_build.py` 从 `gen_wanda_icons.py` import `render_item()`，保证 2D 图标与 3D 精灵同一套画法。

## 用法

```bash
# 1) 重画图标（png）+ 预览
python tools/wanda_planar_plan/gen_wanda_icons.py
python tools/wanda_planar_plan/gen_wanda_icons.py --preview-only   # tex 编译完后只重出预览

# 2) 重画地面精灵 + 生成 scml（生成后手动/脚本调 scml.exe）
python tools/wanda_planar_plan/gen_item_build.py --no-compile

# 3) 工坊预览图（改了美术后重跑；产物直接覆盖 mod 目录下的 preview.jpg）
python tools/wanda_planar_plan/gen_workshop_preview.py

# 3b) Mods 列表图标（产物 mod 根目录的 modicon.png；之后跑一次 autocompiler 编 tex/xml）
#     ★ 不能放 images/ 下：引擎按 "MODS_ROOT/<mod>/"..icon_atlas 拼路径，放子目录会静默失效
python tools/wanda_planar_plan/gen_modicon.py

# 4) 编译 anim.zip（bash 直调，别走 Python subprocess：PATH 会被改成 POSIX 风格）
scml.exe .scratch/wanda-planar-plan/v5/builds/wanda_haste_watch/build.scml \
         .scratch/wanda-planar-plan/v5/builds/wanda_haste_watch

# 5) 编译 tex（先删旧产物，否则 autocompiler 按时间戳跳过）
rm -f mods/wanda_planar_plan/images/inventoryimages/wanda_*.{tex,xml}
"D:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/autocompiler.exe" \
  "D:/Code/MyMods/dst-mods/mods/wanda_planar_plan"
```

## 设计约束（v6 定案）

- 物品栏实际只有 **46px**：只用「正圆 + 平涂 + 实心块」，细线条/渐变/暗纹全糊掉；
- 表链、齿轮、月牙阴影等细节**只放在 128px 地面精灵**里；
- 三张图标同源几何（表盘圆心 `cx=31.6, cy=34.4, R=20.4`），单针 / 双箭头 / 沙漏区分功能；
- 画完必须回读产物核对：`python tools/common/ktex2png.py <x.tex> out.png`
  （DST 图集上下翻转，翻正后再看）；
- 预览拼图 `preview-4x.png` 落在 `.scratch/wanda-planar-plan/v5/art/`（已 gitignore）。

坑与决策见 [`docs/mods/wanda_planar_plan/development.md`](../../docs/mods/wanda_planar_plan/development.md) §7（资源与工具）、
[`docs/mods/common/development.md`](../../docs/mods/common/development.md) §4~§5（图标与 anim 管线）。
