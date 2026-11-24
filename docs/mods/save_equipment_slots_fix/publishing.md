# Save Equipment Slots (Fix) · 发布指南

> 流程与介绍页写作规范见 [`../common/publishing.md`](../common/publishing.md)。
> 本文是该 mod 的工坊条目素材（标题 + 正文 + 截图 + 更新日志）。
> 仓库原来的 `publish/workshop_description.txt` 已迁移到本文 §3.1（该目录已取消，文案定稿统一放本文件）。

## 1. 条目信息

| 项 | 值 |
|---|---|
| 工坊条目 | [3836742363](https://steamcommunity.com/sharedfiles/filedetails/?id=3836742363)（已发布） |
| 标题 | `Save Equipment Slots (Fix)`（= `modinfo.name`；网页实际标题未核对） |
| 模组 ID（本地） | `save_equipment_slots_fix` |
| `modinfo.version` | `0.1.2`（待上传；线上仍为 `0.1.1`）→ 工坊标签 `version:0.1.2` |
| 安装标签 | `client_only_mod = true` → 工坊标签自动表明「只需自己装」，正文不再赘述 |
| `all_clients_require_mod` | `false` |
| 基于 | dani 的 [Save Equipment Slots](https://steamcommunity.com/sharedfiles/filedetails/?id=1598084686) v1.8.3 |
| 作者 | Villkiss (Original author: dani) |
| 双语文案定稿 | `workshop/en.txt`、`workshop/zh.txt`——`workshop.py publish` 直接读 |

> 工坊标签（`client_only_mod` / `version:x.y.z` / DLC 兼容）由 `ISteamUGC` 写：
> 首发时是 ModUploader，之后用 `tools/common/workshop.py`（见 [`../common/publishing.md`](../common/publishing.md) §1）。
> 工坊侧实际值一律用 `python tools/common/workshop.py verify --item 3836742363` 核对。

## 2. 标题

```
Save Equipment Slots (Fix)
```

网页标题若要带中文，建议 `Save Equipment Slots (Fix) 装备槽记忆修复版`，
但需同步 `modinfo.name`，否则游戏内 Mods 列表与工坊页不一致。

## 3. 正文（中英双语）

> **正文只放一处**：[`workshop/zh.txt`](workshop/zh.txt)（中文）与 [`workshop/en.txt`](workshop/en.txt)（英文），
> 第 1 行标题、第 2 行空、第 3 行起是 bbcode 正文。`tools/common/workshop.py publish` 直接读它们，
> 按语言各提交一次。**改描述就改这两个文件**，别在网页上手改（下次发布会覆盖）。
>
> 内容是**以线上为准**拉回来的（`workshop.py dump`）；注意线上 english 槽位目前是中英混排，
> 想拆干净就编辑 `workshop/en.txt` / `workshop/zh.txt` 后再发布。

## 4. 预览图 `preview.jpg`（上传器读取）

| 项 | 值 |
|---|---|
| 文件 | `mods/save_equipment_slots_fix/preview.jpg`（已存在，268×268，13.7 KB） |
| 内容 | 斧头 / 背包 / 草帽 → 三个编号槽位（"物品会被记住它在哪一格"） |
| 维护 | 宣传图由作者提供（原作者线的插图）；改版式/换素材时由用户决定，AGENT 只提醒，不擅自替换 |

> 注意：`preview.jpg` 是 mod 目录里**必需**的一张图（上传器拿它当工坊预览图），
> 排查"上传包体积不对"时别把它当成杂物删掉。

## 5. 截图清单

| # | 内容 | 说明 |
|---|---|---|
| 1 | 封面：装备槽上方显示记忆图标 | 待拍/取旧图 |
| 2 | 下洞穴前后配置仍在（两张对比） | 核心卖点，建议做成左右拼接 |
| 3 | 槽位图标点击清除的瞬间 | 体现"可清除" |
| 4 | 配置项界面 | 让玩家知道可调 |

## 6. 更新日志（Patch Notes）

```
v0.1.2 — 暂停开关状态跟随存档
· Ctrl + V 的开关状态改为与槽位配置同存一份本机文件：上下洞穴、重登/重启保持

v0.1.1 — 修复重登后槽位图标变方块
· 图标引用改为分级来源 + 磁盘缓存，皮肤图标与 hash 数字反解补齐
· 失效槽位占位过滤，避免与其它 mod 同装崩溃

v0.1.0 — 首个修复版
· 槽位配置改为按服务器存到本机，上下洞穴/重登不再丢失
· 默认快捷键改为 Ctrl + V
```

## 7. 发布前检查（本 mod 特有）

```
[ ] modinfo.version 递增，介绍页 Patch Notes 与之对应
[ ] `workshop/{en,zh}.txt` 已同步（注意：线上 english 槽位目前是中英混排，脚本会原样提交 en.txt）
[ ] `python tools/common/workshop.py plan --mod mods/save_equipment_slots_fix --item 3836742363` 无警告
[ ] `... publish --mod mods/save_equipment_slots_fix --item 3836742363 --changenote "v<x.y.z> — …"` 跑完（中英各一次提交）
[ ] `... verify --item 3836742363 --pages` 核对 tags 含 client_only_mod、version:<新版本>，中英标题与正文都对
[ ] 介绍页里的快捷键/配置项名称与 modinfo 的 label/hover 一致
[ ] 正文没有写安装要求（交给工坊标签），只保留标签表达不了的兼容性提示
[ ] 「禁用原版」的提醒在页面上（避免双重处理）
[ ] mods/save_equipment_slots_fix/preview.jpg 存在且是 268×268（宣传图，别当杂物删；不擅自换）
[ ] 游戏已关闭（`workshop.py` 的 preflight 会拦）
[ ] 网页补截图
```
