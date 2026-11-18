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
| `modinfo.version` | `0.1.1` → 工坊标签 `version:0.1.1` |
| 安装标签 | `client_only_mod = true` → 工坊标签自动表明「只需自己装」，正文不再赘述 |
| `all_clients_require_mod` | `false` |
| 基于 | dani 的 [Save Equipment Slots](https://steamcommunity.com/sharedfiles/filedetails/?id=1598084686) v1.8.3 |
| 作者 | Villkiss (Original author: dani) |

> 工坊标签（`client_only_mod` / `version:0.1.1` / DLC 兼容）只能由 ModUploader 写；
> 本机当前无网络，页面实际值未通过 Web API 核对。

## 2. 标题

```
Save Equipment Slots (Fix)
```

网页标题若要带中文，建议 `Save Equipment Slots (Fix) 装备槽记忆修复版`，
但需同步 `modinfo.name`，否则游戏内 Mods 列表与工坊页不一致。

## 3. 正文

### 3.1 当前线上版本（原样迁移，未改动）

```bbcode
Modified from dani's Save Equipment Slots. Original mod: https://steamcommunity.com/sharedfiles/filedetails/?id=1598084686.

修改自 dani 的 Save Equipment Slots，原 mod：https://steamcommunity.com/sharedfiles/filedetails/?id=1598084686。

[b]Changes:[/b]
1. Slot configurations no longer get lost when reloading the game or entering/exiting caves.
2. Minor adjustments to the default configuration. In particular, the default toggle shortcut has been changed to Ctrl + V.

[b]改动说明：[/b]
1、槽位配置重上游戏、上下洞穴不再丢失。
2、些许默认配置调整。特别地，默认开关快捷键变更为 Ctrl + V。
```

### 3.2 完整版草案（下次更新建议替换成这一版）

```bbcode
[h1]Save Equipment Slots (Fix) 装备槽记忆修复版[/h1]

让「装备槽 → 物品」的记忆不再丢失：重上游戏、上下洞穴、纯客户端连服务器都记得住。
修改自 dani 的 [url=https://steamcommunity.com/sharedfiles/filedetails/?id=1598084686]Save Equipment Slots[/url]。

[h2]修复了什么[/h2]
[list]
[*]原版把槽位配置存在[b]所在 shard 的世界存档[/b]里；上下洞穴时地表/洞穴是两个进程，配置会被静默丢弃 → 本版改为[b]按服务器存到本机[/b]，地表和洞穴读写同一份。
[*]槽位图标经常变方块：补全图标缓存来源（背包、装备栏、跨洞穴迁移）、按名推断、图标引用磁盘缓存，并修好皮肤图标与 hash 数字反解。
[*]与部分 mod 同装时的崩溃：过滤失效的槽位占位实体，装备腾位路径加保护。
[/list]

[h2]怎么用[/h2]
[list]
[*]把装备/物品放进槽位，它就会被记住；下次该槽位空着时，同类物品自动回到原位。
[*][b]Ctrl + V[/b] 暂停/恢复记忆（快捷键可在配置里改，也可设为「无」）。
[*]槽位上方会显示已记忆物品的小图标，[b]点击图标[/b]即可清除那一格的记忆。
[/list]

[h2]配置项[/h2]
应用类型（装备 / +食物 / +治疗 / 全部）、显示槽位图标、图标不透明度 / 缩放 / 偏移、
暂停快捷键、初始开关状态、暂停时禁用图标点击、允许装备腾位、保留已存槽位。

[h2]兼容性[/h2]
请[b]禁用原版[/b] Save Equipment Slots —— 两者同时启用会重复处理物品移动逻辑。

[h2]已知限制[/h2]
配置存在本机：换电脑不跟随；同一集群若地表/洞穴对外名称不一致，会各自记忆。

[hr][/hr]

[h1]Save Equipment Slots (Fix)[/h1]

Equipment slot memory that survives reloads: relogging, going in/out of caves, and playing as a pure client on a server.
Modified from dani's [url=https://steamcommunity.com/sharedfiles/filedetails/?id=1598084686]Save Equipment Slots[/url].

[h2]What's fixed[/h2]
[list]
[*]The original mod stored slot configs in the [b]world save of the current shard[/b]; the surface and the caves are separate processes, so the config was silently dropped when switching. This version stores it [b]per server on your machine[/b], shared by both shards.
[*]Slot icons turning into squares: completed the icon cache sources (backpack, equipment slots, shard migration), added prefab-name inference and a disk cache for icon references, and fixed skin icons and hash-number resolution.
[*]Crashes when installed together with certain mods: invalid slot placeholders are filtered out and the equip-for-space path is guarded.
[/list]

[h2]Usage[/h2]
[list]
[*]Put an item into a slot and it is remembered; when that slot is free again the same kind of item returns automatically.
[*][b]Ctrl + V[/b] pauses/resumes the memory (rebindable, or set to "None").
[*]A small icon of the remembered item appears above the slot — [b]click it[/b] to clear that slot's memory.
[/list]

[h2]Options[/h2]
Apply-to types (equipment / +food / +healing / all), show slot icons, icon opacity / scale / offset,
toggle hotkey, initial state, disable icon click while paused, allow equip for space, reserve saved slots.

[h2]Compatibility[/h2]
Please [b]disable the original[/b] Save Equipment Slots — running both double-handles item movement.

[h2]Known limits[/h2]
Config lives on your machine (does not follow you to another PC); if the surface and caves of a cluster expose different names, each shard remembers separately.
```

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
[ ] 介绍页里的快捷键/配置项名称与 modinfo 的 label/hover 一致
[ ] 正文没有写安装要求（交给工坊标签），只保留标签表达不了的兼容性提示
[ ] 「禁用原版」的提醒在页面上（避免双重处理）
[ ] mods/save_equipment_slots_fix/preview.jpg 存在且是 268×268（宣传图，别当杂物删；不擅自换）
[ ] 游戏已关闭 → ModUploader → 选中条目 3836742363 → 粘 §3.2 → Upload
[ ] Web API 校验 tags 含 client_only_mod、version:x.y.z，描述换行为真换行
[ ] 网页补截图/语言槽位
```
