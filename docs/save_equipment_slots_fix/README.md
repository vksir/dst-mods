# Save Equipment Slots 修复版

> 当前版本：**0.1.1**（2026-11-09；仅更新中英文简介与版本号）

基于创意工坊 mod [Save Equipment Slots](https://steamcommunity.com/sharedfiles/filedetails/?id=1598084686)（作者 dani，v1.8.3）的本地修改版。

## 修复的问题

原版将「槽位 → 物品」配置挂在玩家 `inventory` 组件的 OnSave/OnLoad 里，随**所在 shard 的世界存档**保存。
DST 的地表与洞穴是两个独立进程（shard），而原版是 client-only mod，**不会在洞穴端进程运行**：

1. 下洞穴时，玩家实体迁移到洞穴进程，洞穴端是原版存档逻辑，不认识的 `save_equipment_slots` 键被静默丢弃；
2. 回到地表时，迁移快照里已没有该键 → 配置丢失，只能重新配置。

## 修改内容

新增**跨 shard 本地持久化**（方案：`TheSim:SetPersistentString`）：

- 配置额外保存到本机客户端持久化目录：
  `Documents\Klei\DoNotStarveTogether\<KleiID>\client_save\ses_fix_slots_<服务器名>`
- 文件按**服务器（集群）**维度命名，同一世界的地表/洞穴读写同一文件；
- Master / Client 两种模式下配置变更都会写回文件（`SaveSlot` / `ClearSlot` / `SaveCurrentItemSlots` / `Inventory:OnLoad` 四处挂钩）；
- 加载优先级：**世界存档（Inventory.OnLoad）> 持久化文件**；文件不存在时不重算，槽位配置由拾取物品时自然学习；
- client 模式下从文件恢复配置后，会用当前背包物品补充图标缓存并重画槽位图标。

### 效果

| 场景 | 原版 | 修复版 |
|---|---|---|
| 下洞穴 | 配置丢失，需重新配置 | 配置保留 |
| 重登 / 重启游戏（自己开世界） | 配置随世界存档保留 | 配置保留（双保险） |
| 纯客户端连服务器 + 重登 | 配置丢失 | 配置保留（存在本机） |
| 槽位图标（含皮肤）重登后 | 方块/丢失 | 正常显示（推断 + 图标引用磁盘缓存 + hash 反解） |
| 换电脑 | — | ✗ 配置不跟随（存在本机，非世界存档） |

## 安装

把整个 `save_equipment_slots_fix` 文件夹复制到游戏本地 mod 目录：

```
<Steam库>\steamapps\common\Don't Starve Together\mods\save_equipment_slots_fix
```

然后游戏内 Mods 列表启用本 mod，并**禁用原版**（两者同时启用会双重处理物品移动逻辑）。

## 修复记录

按时间顺序记录；按主题可分为三组：**崩溃修复**（与其它 mod 同装）、
**图标显示修复**（占位方块 / 皮肤 / hash 数字反解，占篇幅最大）、
**槽位配置跨 shard 持久化**（本 mod 的核心改动，见上方“修改内容”）。

### 社区反馈：与"漫漫长路"同装崩溃（原版已知问题）

`MasterInventory:MoveAway` 不检查实体有效性直接调用引擎 `GiveItem`：
装备回位时若绑定槽被其他 mod 已移除的实体占据，引擎断言崩溃；
且 `GiveItem` 一旦抛错，槽位里的 `OCCUPIED` 占位对象会永久泄漏，引发连锁崩溃。
修复：入口处过滤 OCCUPIED / 无 IsValid / 实体失效 / 无 inventoryitem 的引用
（直接清空槽位），`GiveItem` 用 `pcall` 包裹并保证清理必然执行。

### 同族问题：`MakeSpace` 装备腾位路径

反馈方案未覆盖：`action == "equip"` 时对失效实体直接 `Equip` 同样会崩。
修复：`MakeSpace` 入口统一清理失效占位（跳过 OCCUPIED），清理后视为空槽。

### 其他加固

- `ApplyToItem(nil)` 在 `apply == "all"` 时误返回 true，
  导致 `Player_OnEquip` 里对 nil 取字段的风险；现已显式拒绝 nil。

### 贴图经常变成方块（槽位图标 fallback 常驻）

方块 = client 模式下图标缓存未就绪时渲染的 `square.tex` 占位。四个根因：

1. **缓存写入与按钮渲染互不感知**（主因）：恢复配置时物品不在身上 →
   渲染成方块；之后玩家捡起物品，`itemget` 只写缓存**不重画已有按钮**，
   延迟自愈（1/3/8 秒）过期后方块永久常驻。
2. **背包（overflow 容器）物品完全不进缓存**：`ClientInventory:EachItem`
   只遍历主物品栏，overflow 的 `itemget` 事件也没补缓存
   → 背包里的装备（备用手杖等）永远是方块。
3. **装备栏物品缺动态补缓存**：跨 shard 迁移/读档时物品直接出现在
   装备槽（不经 `itemget`），load 时 classified 未同步完就永远方块。
4. **物品不在身上时未利用引擎的按名查图**：官方物品与已注册 atlas
   的 mod 物品可按 `prefab.tex` 直接查到 atlas，不必等物品入手。

修复：

- 新增 `state.fallback_buttons` 精确追踪哪些槽位图标还是方块；
  `MaybeSetAtlasAndImageCache` 写入真实来源缓存时自动 kill 并重画对应
  方块（`RefreshIconButtonIfAny`），闭环"物品任何时候到达身上 →
  方块即时替换为真实图标"。
- 缓存来源补齐：overflow 容器的 `itemget`、玩家的 `equip` 事件、
  `PopulateIconCacheFromInventory` 遍历 `state.overflow`。
- 新增纯客户端图标推断（`MaybeSetInferredAtlasAndImageCache`）：
  按 `prefab .. ".tex"` 调 `GetInventoryItemAtlas(name, true)`
  （`no_fallback=true`：查不到返回 nil 而非误拿 images4），
  物品不在身上也能显示正确图标；推断缓存带 `inferred` 标记，
  物品入手时被真实图标（皮肤等特殊图标）覆盖。
- master 模式 spawn 探测失败（无效 prefab 名，如配置残留已卸载 mod 的
  物品）时同样退回按名推断。
- 自愈重试时点延长为 1/3/8/20 秒，职责简化为"定时补充缓存"，
  刷新统一交给缓存就绪钩子。

**图标引用磁盘缓存**（`ses_fix_icon_cache`，全局一份）：解决"重上游戏后
物品不在身上、且图标未注册进 atlas 查询表（旧式 mod 物品常见）时
重新变方块"——

- 入手真实物品时把 `atlas/image` 引用防抖(2 秒)写入本机持久化文件；
  只存按名推断查不到的条目（官方/已注册物品重启后推断必命中，不冗余）；
- 启动时异步加载，不覆盖本会话真实来源，已渲染的 fallback 方块
  立即替换；加载时用 `TheSim:AtlasContains` 校验，mod 已卸载的条目
  自动忽略（校验过严的最坏结果也只是退回方块，不比修复前差）；
- 玩家实体移除（退出/跨 shard 迁移）时立即落盘未写的防抖任务。

仍会显示方块的合理场景：图标未注册进 atlas 查询表、且从未在本机
入手过的 mod 物品（首见之前无法知道其图标引用）。

### 服务端 mod（all_clients_require_mod）物品图标空白

现象：客户端 mod 的物品图标正常，服务端 mod 的物品图标看不到。

根因：服务端 mod 物品常未注册 atlas 查询表（client-only mod 作者必须
处理好客户端渲染所以注册齐全），此时 replica 的 `GetAtlas()` 会兑底到
`images/inventoryimages4.xml` 的**错误路径** → 渲染空白；master 模式的
spawn 探测拿到的正是这个错误结果，且被当成"真实来源"写入内存缓存和
磁盘图标缓存，**污染后物品入手的正确数据也无法覆盖**。

修复：

- `SetAtlasAndImageCache` 统一用 `AtlasContains` 验证，无效引用拒绝
  写入（所有入口覆盖：spawn/入手/推断/磁盘，含 `[SES-FIX]` 诊断日志）；
- spawn 探测结果验证失败时退回按名推断；
- master 模式补齐真实来源缓存入口：`itemget`/`equip` 事件
  （原先仅 client 模式有），磁盘缓存因此能积累服务端 mod 物品的
  正确图标引用，重上游戏直接复用；
- 自愈循环对 master 模式开放。

### 回归修复：皮肤物品图标全部变方块（AtlasContains 误杀）

上一步为拦截 images4 错误路径把 `AtlasContains` 验证加在了**所有**缓存
写入入口，但带皮肤物品的真实图标（皮肤专属 atlas）可能尚未注册进
引擎查询表——验证误杀皮肤图标，入手/装备事件全部被拒，图标退化为
fallback 方块。

修复：验证只留给不可信来源——

- **真实来源**（入手/装备/在身物品）：信任，不验证（引擎自己在用这份数据）；
- **spawn 探测**：保留验证（images4 垃圾的唯一来源），验证失败退回按名推断；
- **磁盘条目**：渲染时验证（进世界后资源已加载，`AtlasContains` 可靠；
  之前在 modmain 加载阶段（主菜单）验证会因 atlas 未加载而全数误拒，
  仅靠进世界后 modmain 重载救回，不可靠）。

日志确认的机制：`AtlasContains` 查询的是**运行时已加载**的 atlas，
主菜单阶段官方 inventoryimages 也未加载（全部返回 false）。

### 皮肤物品显示基础图标，无法正确显示皮肤

上一节的分级验证修好了"皮肤图标被误杀变方块"，但皮肤物品随后显示
的是**无皮肤的基础图标**——spawn 探测产生的是无皮肤基础数据，却被
标记为最高优先级（真实来源），玩家物品的真实皮肤图标（入手/装备/
在身）无法覆盖它；世界存档恢复路径又没有 populate 时机补充。

修复：缓存来源分级 `真实物品数据(含皮肤) > 磁盘缓存 > spawn 探测 >
按名推断`——

- spawn 探测结果标记 `source="spawn"`，允许被真实数据覆盖；
- `RefreshIconButtonIfAny`：缓存数据升级(fallback→真实 / 基础→皮肤)
  时重画对应按钮（"真实来源不再重算"保证至多一次，无闪烁）；
- `InitInventory` 末尾统一 populate：用身上物品（含装备栏的皮肤
  override 数据）补缓存，覆盖世界存档恢复路径；
- rerender 重建只挂推断/磁盘来源（spawn 数据已验证过，升级走覆盖重画）。

### 皮肤物品显示无皮肤基础图标

根因：图标缓存**只按 prefab 做键**，而皮肤图标是经 `inventoryitem` 的
`imagename` 网络变量下发的（服务端 `ChangeImageName` → 复制到
`inventoryitem_classified`）。一旦缓存里存了基础图标（spawn 探测、
或皮肤数据尚未同步时的快照），渲染就永远返回它，从不重读身上物品的
真实图像。

修复：**渲染时优先读活体物品**——

- 新增 `FindLiveItem`（物品栏/背包/装备栏查找）与
  `GetAtlasAndImageFromLiveItem`；`GetAtlasAndImage` 首步即读活体数据，
  与缓存不一致时更新缓存并重画，保证皮肤图标始终最新；
- 新增 `ResyncIconsFromLiveItems`：进入世界后于 1/3/8/20/40 秒、
  `inventorybar` 重建、`equip` 事件后重同步，覆盖皮肤数据延迟下发；
- 磁盘写入过滤修正：皮肤图标（图像名 ≠ `prefab.tex`）必须入盘，
  否则重上游戏推断（只用基础名）会退回基础图标。

已知近似：同 prefab 多个不同皮肤同时在身上时，图标取找到的第一个；
物品不在身上时用磁盘里最近一次的真实图标。

### 回归修复：下线再上线后槽位图标仍变方块（日志实锤两个根因）

复现日志（client_log.txt）：9 个官方物品（不在身上）`create button:
atlas=nil` → fallback 方块；2 个在身物品（king_cane/yellowstaff）
拿到 `image=3076280794(number)`，渲染时报 `Invalid resource handle
for atlas 'FROMNUM'`，且**官方物品栏本身图标也坏**（同源警告）。

根因一：**按名推断从未生效**——`GetInventoryItemAtlas` 不在 mod
沙箱白名单内（`mods.lua CreateEnvironment` 是显式字段表、无
`__index` 转发），裸用恒为 `nil`，推断函数开头 `not GetInventoryItemAtlas
then return` 静默跳过。而 mod 沙箱里其余引擎全局都靠顶部
`GLOBAL.xxx` 显式取，唯独漏了这个（`FlushIconStore` 里的
`~= nil` 防御正是作者踩过的痕迹）。

修复：顶部补 `local GetInventoryItemAtlas = GLOBAL.GetInventoryItemAtlas`。

根因二：**net_hash 字符串驻留表溢出**——`inventoryitem_classified`
的 image/atlas 是 `net_hash`，引擎按字符串驻留表还原；装了 30+ 个
mod 把表挤满后 `value()` 反查失败返回 hash 数字（如 3076280794 =
hash("king_cane.tex")）。活体路径只过滤空串不过滤数字，数字被当作
"真实来源"写缓存并渲染 → 方块固化；`ResyncIconsFromLiveItems`
对比数字≠缓存字符串还会反向覆盖；下线时 `FlushIconStore` 的
`inferable` 判断也因沙箱 nil 恒为 false，数字条目入盘**覆盖丢失
原有字符串条目**。

修复：

- `GetAtlasAndImageFromLiveItem` 要求活体数据必须是字符串
  （`type(atlas) == "string"`），数字拒绝后由缓存/按名推断兜底
  （推断修复后 king_cane 按 `king_cane.tex` 命中官方图集）；
- `GetAtlasAndImage` 缓存消费处防御性清理非字符串条目，
  清除后磁盘字符串条目可重新写入（`LoadIconStore` 本有 type
  校验，双保险）；
- 顶部 local 修复后 `FlushIconStore` 的 `inferable` 恢复真实判断，
  推断可复现的官方物品不再冗余入盘。

遗留（非本 mod 可修）：数字 hash 导致的**官方物品栏 itemtile 渲染
失败**（FROMNUM 警告）是引擎级驻留表溢出，减装 mod 可缓解；本 mod
修复后槽位图标用字符串来源（推断/磁盘）绕过，不再受其影响。

### 皮肤图标无法显示（hash 数字拒收后的还原）

上轮把 hash 数字拒之门外后，皮肤图标（经 `ChangeImageName(skinname)`
下发，同样受驻留表溢出影响返回数字）也随之丢失，槽位退回基础图标。

修复：把数字还原回字符串——

- **master 模式**：活体直读组件明文字段
  `components.inventoryitem.imagename/atlasname`，完全绕过 net_hash；
  `imagename` 为 nil 时按名推断基础图标；
- **client 模式**：懒加载构建 hash 反解表
  （`GLOBAL.hash()` × 数据源：`PREFAB_SKINS` 官方皮肤名全清单 +
  `GLOBAL.Prefabs` 全部已注册 prefab 名），遇到数字 image 按表还原；
- atlas 数字无法反解时丢弃，按还原后的 image 名重查官方图集
  （皮肤图标全部在 inventoryimages1-4 内，已采样验证命中）；
- 反解未命中的（未知 mod 皮肤等）维持拒绝，退基础图标奔底。

效果：入手/装备/重登路径的活体读取重新拿到皮肤图标字符串，写入
缓存并同步入盘（皮肤 tex 名 ≠ prefab.tex 名，必然入盘），重登后
物品不在身上也能复用。

### 已知但不修的项（评估过，影响可忽略）

- `state.client_processed` 会话内缓慢累积（每条几十字节，重登清零）；
- 客户端模式 `fn.Lock()` 若回调链中途抛错会泄漏锁（mod 静默失效直到重登，
  不崩溃；整条链都是 RPC 包装，抛错概率极低）。

## 已知限制

- 配置存在本机，换电脑不跟随（若需跟随世界存档，需改造成 server mod，见仓库讨论）；
- 文件名取自服务器名，若同一集群的地表/洞穴进程对外名称不一致，则退化为各 shard 各自记忆；
- 多个不同世界若同名，配置会互相覆盖。
