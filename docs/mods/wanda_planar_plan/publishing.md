# 旺达位面计划 · 发布指南

> 流程与介绍页写作规范见 [`../common/publishing.md`](../common/publishing.md)。
> 本文是**这个 mod 的工坊条目素材**：标题、正文（可直接复制）、截图清单、更新日志。

## 1. 条目信息

| 项 | 值 |
|---|---|
| 工坊条目 | **已发布**（2026-11-18 首发 0.4.0；工坊 ID 待填 `sharedfiles/filedetails/?id=<ID>`） |
| `modinfo.name`（代码） | `Wanda Planar Plan` —— **只能 ASCII**，与文件夹名一致 |
| 工坊标题（网页/上传器） | `Wanda Planar Plan 旺达位面计划`（页面支持中文，玩家看得懂） |
| 模组 ID（本地） | `wanda_planar_plan` |
| `modinfo.version` | `0.4.1` → 工坊标签 `version:0.4.1`（**每次重新上传都要 +1**，否则版本标签不刷新） |
| 安装标签 | `all_clients_require_mod = true` → 工坊标签自动表明「双端都要装」，正文不再赘述 |
| `server_filter_tags` | `wanda`、`character` |
| 作者 | Villkiss |

## 2. 标题

| 位置 | 值 |
|---|---|
| `modinfo.name`（游戏内 Mods 列表、代码里） | `Wanda Planar Plan`（纯 ASCII） |
| 工坊标题（ModUploader 标题框 / 网页） | `Wanda Planar Plan 旺达位面计划` |

**代码里的名字不能有中文**：`modinfo.name`、文件夹名、prefab 名、netvar 名、资源路径一律 ASCII；
中文只出现在展示文本（`description` / `hover` / `STRINGS` / 工坊标题）。

## 3. 正文（复制粘贴用）

> 下方整段粘进 ModUploader 的描述框。全部是真实换行 + 工坊 BBCode 子集，不要转成 Markdown。

```bbcode
[h1]旺达位面计划[/h1]

旺达（Wanda）加强包：位面伤害重做、可命名的怀表、专属钟表袋，以及能切档的加速表与减速表。
每项功能都能在「模组配置」里单独开关。

[h2]新增物品[/h2]
[list]
[*][b]加速表[/b]：右键切换 关闭 / 30% / 50%，移动速度与老化同步加快。
[*][b]减速表[/b]：右键切换 关闭 / 30% / 50%，身边敌人变慢，代价是自己老化更快。
[*][b]钟表袋[/b]：2×8 格，只装旺达的钟表；右键开关，人物走动不会关闭。
[/list]

[h2]能力改动[/h2]
[list]
[*][b]位面伤害[/b]：造成的伤害全额按位面结算，受到的位面伤害按普通伤害结算。
[*][b]倒走表[/b]：施法起手就有格挡，施放成功后追加 10 帧免伤。
[*][b]第二次机会表[/b]：灵魂状态用它救自己后不再损毁。
[*][b]命名[/b]：拿羽毛笔右键溯源表 / 裂缝表即可起名字。
[/list]

[h2]反馈[/h2]
问题请在评论区反馈，附上游戏版本和你装的其它 mod。

[hr][/hr]

[h1]Wanda Planar Plan[/h1]

An overhaul pack for Wanda: reworked planar damage, nameable watches, a dedicated watch bag, and haste / slow watches with switchable tiers.
Every feature can be toggled in Mod Configuration.

[h2]New items[/h2]
[list]
[*][b]Haste Watch[/b]: right-click to cycle off / 30% / 50% — faster movement and faster aging.
[*][b]Slow Watch[/b]: right-click to cycle off / 30% / 50% — nearby enemies slow down, at the cost of faster aging.
[*][b]Watch Bag[/b]: 2×8 slots for Wanda's watches only; right-click to open or close, it stays open while you walk.
[/list]

[h2]Reworked abilities[/h2]
[list]
[*][b]Planar damage[/b]: damage dealt is fully planar; planar damage taken is treated as normal damage.
[*][b]Backstep Watch[/b]: the block starts at cast time, plus 10 frames of protection after the cast.
[*][b]Second Chance Watch[/b]: no longer destroyed when used to revive yourself.
[*][b]Naming[/b]: right-click a Telltale Heart / Rift Watch with a Feather Pencil to name it.
[/list]

[h2]Feedback[/h2]
Please report issues in the comments, with your game version and other mods installed.
```

> 介绍页只写**核心功能与玩家关心的点**：机制细节（档位存在人物身上、叠加公式、UI 布局、
> 配方材料）一律不写——那些玩家进游戏就能看到，写多了反而没人看。

## 4. 预览图 `preview.jpg`（上传器读取）

上传器把 `mods/wanda_planar_plan/preview.jpg` 作为**工坊条目预览图**，缺失就只有默认灰底图。

| 项 | 值 |
|---|---|
| 文件 | `mods/wanda_planar_plan/preview.jpg`（268×268，RGB，JPG） |
| 要求 | 官方约定 268×268；缩略图会缩到 ~120px 显示，字大、主体少 |
| 现状 | **占位图**：临时用 `tools/wanda_planar_plan/gen_workshop_preview.py` 合成（三件精灵 + 标题），待换用户自己的宣传图 |

> **这是宣传图，由用户拍板**——AGENT 不要擅自生成/替换正式版；发布前只提醒用户准备。
> 现有那张是用户看过并认可的占位版（268×268），换正式图时直接覆盖同名文件即可。
>
> 若用户授权代做：脚本取 `anim/*.zip` 里的 128px 精灵（注意 DST 图集解码后要上下翻转才是
> 游戏显示方向，脚本已处理），改了美术后重跑即可。

**Mods 列表图标已出**（2026-11-18）：

| 项 | 值 |
|---|---|
| 文件 | **`mods/wanda_planar_plan/modicon.png`（256×256）+ `modicon.tex` / `modicon.xml`**（根目录！autocompiler 产物 87506 B） |
| 内容 | 两块表斜叠：后排洋红（减速表）、前排青绿（加速表），黄铜壳 + 平涂，两块表盘都完整可见 |
| 生成 | `python tools/wanda_planar_plan/gen_modicon.py` → `autocompiler.exe mods/wanda_planar_plan` |
| `modinfo` | 已加 `icon_atlas = "modicon.xml"`、`icon = "modicon.tex"` |
| 校验 | 解码 `modicon.tex` 回 256×256 RGBA，与 png 平均色差 2.5（DXT 压缩级）；64px 缩略仍能认出"两块表" |
| 踩坑 | 第一版把产物放在 `images/` 下 → 引擎按 `MODS_ROOT/<mod>/` + `icon_atlas` 拼路径，解析失败**静默置 nil**，Mods 列表仍是灰图；日志一行 `WARNING: icon paths … are not valid`。已移到根目录 |

> 图标属于美术物料：这版是按现有风格（黄铜壳 + 平涂三色 + 暖黑描边）代画的，要换风格随时重画。

## 5. 截图清单（工坊页侧栏上传）

| # | 内容 | 素材来源（仓库内） |
|---|---|---|
| 1 | 封面：旺达持表 + mod 名叠字 | 待拍 |
| 2 | 三件新物品在物品栏 / 地面的样子 | `v6/01-物品栏图标.png`、`v6/02-地面造型.png` |
| 3 | 钟表袋打开 + 加速表开启的界面 | `v6/03-分开布局-右侧.png` |
| 4 | 分开布局：钟表袋与背包上下对齐 | `v7/01-分开布局上下居中.png` |
| 5 | 融合布局：钟表袋占用背包列 | `v7/02-分开与融合布局.png` |

## 6. 更新日志（Patch Notes）

首发给一份完整说明，之后每次改动写一行标题 + 要点：

| 版本 | Patch Notes（粘进上传器的「改动说明」） |
|---|---|
| **0.4.1**（当前） | `v0.4.1 — 更名与图标`<br>`· mod 更名为「旺达位面计划」`<br>`· 新增 Mods 列表图标`<br>`· 介绍页精简为核心功能` |
| 0.4.0（首发） | `v0.4.0 — 首发`<br>`· 位面伤害重做、溯源表/裂缝表可命名、钟表袋、加速表与减速表、倒走表护盾、第二次机会表`<br>`· 加速表/减速表各两档（30% / 50%），老化加速加算叠加`<br>`· 钟表袋面板支持分开布局（与背包上下对齐）与融合布局（占用背包列）` |

> **重新上传的硬性步骤**：`modinfo.version` 递增 → 上传器里选中**已有条目**（别新建）→
> Patch Notes 写这一版改了什么 → Upload。版本不变的话工坊标签 `version:x.y.z` 不会刷新，
> 玩家游戏内会继续提示「mod 过期」。

## 7. 发布前检查（本 mod 特有）

```
[ ] `modinfo.name` 是纯 ASCII（`Wanda Planar Plan`），工坊标题才是中文那一版
[ ] 三张图标 tex/xml 与三个 anim.zip 均为最新编译（大小：tex 5566B / zip 8419·8392·8996B）
[x] `modicon.png` + `modicon.tex/xml` 已出并放在 **mod 根目录**，`modinfo.icon_atlas/icon` 已填（2026-11-18）
[ ] modinfo 的 description 与两条 hover 的档位/数值与本文件、features.md 一致
[ ] 介绍页只写核心功能（无配方/公式/布局细节）；数值与 modinfo 的 hover 不矛盾
[ ] 验收报告（v7）已出，`docs/mods/wanda_planar_plan/testing.md` 的回归清单全过
[ ] 分开/融合两种布局各截一张图（介绍页要用，也证明不回退）
[ ] 已提醒用户准备/确认 preview.jpg（268×268 宣传图）；当前是占位版，正式图由用户提供
[ ] 测试标记清零：grep -rn "TEMP\|\[T\]\|\[DBG\]\|\[W7\]" mods/wanda_planar_plan --include=*.lua
[ ] `modinfo.version` 已递增（当前 0.4.1），Patch Notes 已写
[ ] 游戏已关闭 → ModUploader → **选中已有条目** → 目录选 mods/wanda_planar_plan → 粘 §3 → Upload
[ ] Web API 校验 title / tags（应含 all_clients_require_mod、version:0.4.1）/ description
[ ] 网页补 5 张截图、中文语言槽位
```
