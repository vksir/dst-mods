# Save Equipment Slots (Fix) · 开发指南

> 基于 dani 的 [Save Equipment Slots](https://steamcommunity.com/sharedfiles/filedetails/?id=1598084686) v1.8.3
> 的本地修改版，`modinfo.version = 0.1.1`，`client_only_mod = true`。
> 通用写法（沙箱、Asset、调试、工具）见 [`../common/development.md`](../common/development.md)，
> 本文只写这个 mod 的根因分析与改动。

## 1. 代码结构

单文件 `modmain.lua`（约 2560 行），逻辑分三块：

| 区块 | 内容 |
|---|---|
| 槽位记忆 | `SaveSlot` / `ClearSlot` / `GetSlot` / `ReserveSavedSlots` / `TrySkipSavedSlots` / `Inventory_GetNextAvailableSlot` / `Inventory_Equip` / `Player_OnEquip` |
| 图标子系统 | `GetAtlasAndImage` 系列、`MaybeSetAtlasAndImageCache`、`FindLiveItem`、`BuildHashTexLookup` / `UnhashTex`、`CreateImageButton` / `RefreshIconButtonIfAny` / `ScheduleIconHeal` / `ResyncIconsFromLiveItems` |
| 本地持久化 | `PERSIST_FILE_PREFIX = "ses_fix_slots_"`（槽位配置 + 暂停开关状态）、`ICON_STORE_FILE = "ses_fix_icon_cache"`（图标引用） |

## 2. 核心改动：跨 shard 本地持久化

### 2.1 根因

原版把「槽位 → 物品」配置挂在玩家 `inventory` 组件的 `OnSave/OnLoad` 里，随**所在 shard 的世界存档**
保存。DST 的地表与洞穴是两个独立进程，而本 mod 是 client-only，**不会在洞穴端进程运行**：

1. 下洞穴时玩家实体迁移到洞穴进程，洞穴端跑的是原版存档逻辑，不认识的 `save_equipment_slots`
   键被**静默丢弃**；
2. 回地表时迁移快照里已没有该键 → 配置丢失。

### 2.2 方案

`TheSim:SetPersistentString` 存到本机客户端持久化目录：

```
文档/Klei/DoNotStarveTogether/<KleiID>/client_save/ses_fix_slots_<服务器名>
```

- 文件按**服务器（集群）**维度命名 → 同一世界的地表/洞穴读写同一份；
- 文件内容：`{ version, items, disable_save_slots }`（开关字段可缺省，见 §2.3）；
- Master / Client 两种模式下配置变更都写回（`SaveSlot` / `ClearSlot` / `ToggleDisableSaveSlots` /
  `Inventory:OnLoad` 四处挂钩）；
- 加载优先级：**世界存档（`Inventory.OnLoad`）> 持久化文件**；文件不存在时不重算，
  槽位配置由拾取物品时自然学习；
- client 模式从文件恢复后，用当前背包物品补充图标缓存并重画槽位图标。

### 2.3 暂停开关状态（Ctrl + V）跟随存档

需求：开关不是「每次进世界回到配置默认」，而是与槽位配置一样跟随存档
（地表关掉 → 下洞穴仍关；重进世界仍关）。

**做法**：开关和槽位配置存同一份文件（同一个 `GetPersistFilename()` 键，按服务器命名），
用户切换时立即 `FlushPersistedSlots()` 落盘，进入世界时在 `LoadPersistedSlots` 回调里恢复。
仅当「暂停保存快捷键」配置为某个键时才读写该字段（设为「无」时开关不可变，
语义等同于始终开启，不写盘也不读盘）。

两个必须处理的时序坑：

1. **写盘早于读回**：进世界瞬间 `Inventory.OnLoad` 会触发 `FlushPersistedSlots()`，
   此时内存里的开关还是配置默认值，直接写盘会把文件里已存的开关覆盖掉。
   修法：新增 `state.persist_loaded_key` 门闩，**当前文件名未读回前 `FlushPersistedSlots` 直接返回**；
   跨 shard 时会重读文件，读盘期间由 `state.persist_reading_key` 同样禁止写盘
   （否则可能先写新值、再被读到的旧值覆盖）。
   `LoadPersistedSlots` 回调末尾一定会再 Flush 一次，挂起期间的最新状态不会丢。
2. **异步读回晚于用户操作**：用户进世界后极短时间内就按了 Ctrl + V，之后文件才读回来。
   修法：文件未读回时的切换会把 `state.disable_save_slots_override_key` 记为当前文件名，
   该文件的读回调到达时就不再应用文件值（用户这次操作优先），然后照常 Flush 写回并清除该标记。
   文件**已读回**后的切换会立即落盘，不需要标记，也就不会影响同一个进程里后续进入的其他世界。

旧版本文件没有 `disable_save_slots` 字段（`PERSIST_VERSION` 不变，按字段类型判断）
→ 保持配置里的「初始开关状态」，首次 Flush 后补上该字段。

### 2.4 效果

| 场景 | 原版 | 修复版 |
|---|---|---|
| 下洞穴 | 丢失 | 保留 |
| 重登 / 重启（自开世界） | 保留（世界存档） | 保留（双保险） |
| 纯客户端连服务器 + 重登 | 丢失 | 保留（本机文件） |
| 开关状态（Ctrl + V）的上下洞穴 / 重登 | 回到配置默认 | 保留（同一份本机文件） |
| 槽位图标（含皮肤）重登后 | 方块/丢失 | 正常（推断 + 图标磁盘缓存 + hash 反解） |
| 换电脑 | — | ✗ 不跟随 |

## 3. 图标子系统（占篇幅最大，踩了六轮）

### 3.1 "方块"的四个根因

方块 = client 模式图标缓存未就绪时渲染的 `square.tex` 占位：

1. **缓存写入与按钮渲染互不感知**：恢复配置时物品不在身上 → 渲染成方块；之后玩家捡起物品，
   `itemget` 只写缓存**不重画已有按钮**，延迟自愈（1/3/8 秒）过期后方块永久常驻；
2. **背包（overflow 容器）物品完全不进缓存**：`ClientInventory:EachItem` 只遍历主物品栏；
3. **装备栏物品缺动态补缓存**：跨 shard 迁移/读档时物品直接出现在装备槽（不经 `itemget`），
   load 时 classified 未同步完 → 永远方块；
4. **没利用引擎的按名查图**：官方物品与已注册 atlas 的 mod 物品可按 `prefab.tex` 直接查。

### 3.2 修法

- `state.fallback_buttons` 精确追踪哪些图标还是方块，写入真实来源时自动 kill 重画
  （`RefreshIconButtonIfAny`）→ 闭环"物品任何时候到手，方块即时替换"；
- 缓存来源补齐：overflow 的 `itemget`、玩家 `equip` 事件、`PopulateIconCacheFromInventory`；
- 纯客户端按名推断：`GetInventoryItemAtlas(prefab .. ".tex", true)`
  （`no_fallback = true`：查不到返回 nil，而不是误拿 `images4.xml`）；推断条目带 `inferred` 标记，
  物品入手后被真实图标（皮肤）覆盖；
- 自愈时点延长为 1/3/8/20 秒，职责简化为"定时补缓存"，刷新统一交给缓存就绪钩子。

### 3.3 图标引用磁盘缓存（`ses_fix_icon_cache`，全局一份）

解决"重上游戏后物品不在身上、且图标未注册进 atlas 查询表时又变方块"：

- 入手真实物品时把 `atlas/image` 引用防抖（2 秒）写盘；只存按名推断查不到的条目
  （官方/已注册物品重启后推断必命中，不冗余）；
- 启动时异步加载，不覆盖本会话真实来源，已渲染的方块立即替换；
- 加载时用 `TheSim:AtlasContains` 校验，mod 已卸载的条目自动忽略；
- 玩家实体移除（退出/跨 shard）时立即落盘未写的防抖任务。

仍会方块的合理场景：图标未注册进 atlas 查询表、且从未在本机入手过的 mod 物品。

### 3.4 分级验证（踩过误杀与污染两个反向坑）

`AtlasContains` 验证加错位置会两头翻车：

| 来源 | 是否验证 | 原因 |
|---|---|---|
| 真实来源（入手/装备/在身） | **不验证** | 引擎自己在用这份数据；带皮肤物品的皮肤 atlas 可能尚未注册进查询表，验证会误杀 → 图标退化成方块 |
| spawn 探测 | **验证** | `images4.xml` 垃圾路径的唯一来源，验证失败退回按名推断 |
| 磁盘条目 | **渲染时验证** | 进世界后资源已加载才可靠；在 modmain 加载阶段（主菜单）验证会全数误拒 |

日志确认的机制：`AtlasContains` 查询的是**运行时已加载**的 atlas，主菜单阶段官方
inventoryimages 也未加载（全部返回 false）。

### 3.5 皮肤图标（三个连续坑）

1. spawn 探测拿到的是**无皮肤基础数据**，却被当最高优先级 → 真实皮肤图标无法覆盖：
   改为分级 `真实物品数据(含皮肤) > 磁盘缓存 > spawn 探测 > 按名推断`，
   spawn 结果带 `source="spawn"` 允许被覆盖；
2. 缓存**只按 prefab 做键**，而皮肤图标是经 `inventoryitem.imagename` 网络变量下发的 →
   缓存里一旦存了基础图标就永远返回它。修法：**渲染时优先读活体物品**
   （`FindLiveItem` + `GetAtlasAndImageFromLiveItem`），不一致就更新缓存并重画；
   另加 `ResyncIconsFromLiveItems`（进世界后 1/3/8/20/40 秒、`inventorybar` 重建、`equip` 后）覆盖皮肤数据延迟下发；
3. 磁盘写入过滤要修正：皮肤图标（图像名 ≠ `prefab.tex`）**必须入盘**。

已知近似：同 prefab 多个不同皮肤同时在身上时取第一个；物品不在身上时用磁盘里最近一次的真实图标。

### 3.6 两个线上实证的根因（日志实锤）

复现日志：9 个官方物品（不在身上）`create button: atlas=nil` → 方块；
2 个在身物品拿到 `image=3076280794(number)`，渲染报 `Invalid resource handle for atlas 'FROMNUM'`，
连官方物品栏图标一起坏。

1. **按名推断从未生效**：`GetInventoryItemAtlas` **不在 mod 沙箱白名单内**
   （`mods.lua CreateEnvironment` 是显式字段表、无 `__index` 转发），裸用恒为 `nil`，
   推断函数开头 `not GetInventoryItemAtlas then return` 静默跳过。
   修法：顶部 `local GetInventoryItemAtlas = GLOBAL.GetInventoryItemAtlas`；
2. **`net_hash` 字符串驻留表溢出**：`inventoryitem_classified` 的 image/atlas 是 `net_hash`，
   装了 30+ 个 mod 把驻留表挤满后 `value()` 反查失败，返回 hash 数字（如 3076280794 = `king_cane.tex`）。
   活体路径只过滤空串不过滤数字 → 数字被当"真实来源"写缓存并渲染 → 方块固化，
   还会反向覆盖正常的字符串条目。
   修法：活体数据必须是 `type(x) == "string"`；缓存消费处清理非字符串条目；
   `FlushIconStore` 的 `inferable` 判断恢复真实（推断可复现的官方物品不再冗余入盘）。

3. **数字还原（皮肤图标最后一块）**：
   - master 模式：读组件明文字段 `components.inventoryitem.imagename/atlasname`，绕过 net_hash；
   - client 模式：懒加载构建 hash 反解表（`GLOBAL.hash()` × 数据源：`PREFAB_SKINS` 全量皮肤名 +
     `GLOBAL.Prefabs` 全部已注册 prefab 名），数字 image 按表还原；
   - atlas 数字无解时丢弃，按还原后的 image 名重查官方图集（皮肤图标都在 inventoryimages1-4 内）。

遗留（非本 mod 可修）：数字 hash 导致**官方物品栏 itemtile 渲染失败**是引擎级驻留表溢出，
减装 mod 可缓解；本 mod 修好后槽位图标走字符串来源（推断/磁盘），不受影响。

## 4. 崩溃加固

- `MasterInventory:MoveAway` 原版不检查实体有效性直接调引擎 `GiveItem`：装备回位时若绑定槽被
  别的 mod 已移除的实体占据，引擎断言崩溃；且 `GiveItem` 抛错会让槽位里的 `OCCUPIED` 占位对象
  **永久泄漏**引发连锁崩溃。修法：入口过滤 OCCUPIED / 无 `IsValid` / 实体失效 / 无 `inventoryitem`
  的引用（直接清空槽位），`GiveItem` 用 `pcall` 包裹并保证清理必然执行；
- `MakeSpace` 的 `action == "equip"` 路径对失效实体直接 `Equip` 同样会崩 →
  入口统一清理失效占位（跳过 OCCUPIED），清理后视为空槽；
- `ApplyToItem(nil)` 在 `apply == "all"` 时误返回 true → 显式拒绝 nil。

## 5. 已知限制 / 不修的项

- 配置存本机，换电脑不跟随（要跟随需改造成 server mod）；
- 文件名取自服务器名：同一集群地表/洞穴对外名称不一致时退化为各自记忆；多个同名世界会互相覆盖
  （槽位配置与开关状态都受影响）；
- **持久化文件名实测是 `ses_fix_slots_unknown`**（本机 `client_save` 里只有这一个文件）：
  说明 `GetPersistFilename()` 的 key 落了 `unknown` 兜底。两个待验证的候选原因：
  ① `TheNet:GetServerName()` 在 `InitInventory` 时为空（纯客户端？）；
  ② 名字是中文时被 `gsub("%W", "")` 全部剔除（本机集群名均为中文）。
  无论哪个原因，后果都是**跨世界共用一份配置**（开关也会串世界），待 E2E 时用控制台打印
  `TheNet:GetServerName()` 确认；修法候选：保留 Unicode 字符、只剔除路径非法字符，
  或改用 `TheNet:GetSessionIdentifier()` 作键（改键需要旧文件迁移 + 重跑跨 shard/重登验证）；
- 把「暂停保存快捷键」改成「无」后不再读写持久化里的开关字段，等于强制开启；再改回某个键时
  沿用文件里上一次的开关；
- `state.client_processed` 会话内缓慢累积（每条几十字节，重登清零）；
- 客户端模式 `fn.Lock()` 若回调链中途抛错会泄漏锁（mod 静默失效直到重登，不崩溃）。
