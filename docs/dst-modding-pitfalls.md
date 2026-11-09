# DST mod 开发踩坑记录

本仓库开发饥荒联机版（DST）mod 时实际踩过的坑。新会话动手改代码前**先通读本文**，尤其是"沙箱环境"一节。

## 1. modmain 沙箱：标准库残缺（崩过两次）

DST 的 mod 不运行在完整 Lua 环境里。`modmain.lua` 环境（游戏源码 `scripts/mods.lua:297 CreateEnvironment`）**只白名单**：

```
pairs, ipairs, print, math, table, type, string, tostring, require, Class, GLOBAL
```

**缺失**：`next`、`pcall`、`tonumber`、`unpack`、`setmetatable`、`error`、`os` 等。
写代码前先在文件顶部显式导入：

```lua
local next = GLOBAL.next
local pcall = GLOBAL.pcall
local tonumber = GLOBAL.tonumber
```

- 崩溃形态：`attempt to call global 'next' (a nil value)`，发生在进世界时（tick 6 左右）。
- 引擎 API 一律走 `GLOBAL`：`GLOBAL.TheSim`、`GLOBAL.TheNet`、`GLOBAL.json`。
- 官方白名单以游戏源码为准，别凭记忆。

## 2. modinfo 沙箱：零标准库（导致过启动闪退）

`modinfo.lua` 的执行环境（`scripts/modindex.lua:593 InitializeModInfo`）**只有 3 个变量**：
`folder_name`、`locale`、`ChooseTranslationTable`。没有 `string`、没有 `pairs`、什么都没有。

- ✅ 可用：字符串字面量、表构造器、算术、拼接、**字符串元表调用**：`("").char(65 + i)`、`("v"):byte()`
- ❌ 不可用：`string.byte("v")`、`math.floor(...)`、任何标准库全局
- ⚠️ 崩溃形态最恶劣：modinfo 在 `main.lua` 启动阶段加载，报错会级联成 `Error during game initialization!` → **直接闪退**（不是游戏内错误弹窗）。

**规则：modinfo.lua 里永远只写字符串/数字常量和字符串元表调用。**

## 3. Lua 语言层

- **`STRINGS.RECIPEDESC` 不存在（arc_k9 崩过）**：老版键名已废，现代 DST 配方描述键是 **`STRINGS.RECIPE_DESC`**（strings.lua:4834；官方取用 recipepopup.lua:297 `STRINGS.RECIPE_DESC[string.upper(recipe.description or recipe.product)]`）。modmain 里写 `STRINGS.RECIPEDESC.XXX` 直接 `attempt to index field 'RECIPEDESC' (a nil value)` 启动崩溃。`STRINGS.NAMES` / `STRINGS.CHARACTERS.GENERIC.DESCRIBE` 均正常存在。

- **空字符串是真值**。`inventoryitem_classified` 的 net_string 在同步完成前是 `""`——把 `atlas=""` 缓存进去会让图标永远渲染成 fallback 方块。缓存前必须过滤 `atlas ~= "" and image ~= ""`。
- **json.decode 的对象键全是字符串**。`state.items` 用数字槽位做键，从持久化文件恢复后要 `tonumber(slot)` 还原，否则 `state.items[1]` 查不到。
- **实体上的定时器随实体/世界销毁**。跨 shard 切换时 `DoTaskInTime` 的防抖任务可能永远不触发；关键写盘要么在变更点即时执行，要么在 `playerdeactivated` 等事件兜底。
- `AddComponentPostInit("inventory")` 的 OnLoad 钩子**先于** `AddPlayerPostInit` 触发（恢复存档数据在前，玩家初始化在后）。

## 4. DST 架构：shard 与双模式

- **地表/洞穴是两个独立进程、独立存档**。玩家跨 shard 走迁移快照；快照经对端 vanilla `OnSave/OnLoad` 转手后，组件数据里"不认识的键"会被**静默丢弃**——这就是原版 Save Equipment Slots 下洞穴丢配置的根因。
- **client-only mod 不会在洞穴端进程运行**。自开世界的洞穴是独立 dedicated 进程；host 进洞穴后自己的客户端也退化成纯客户端。
- 客户端模式没有组件只有 replica：`o.replica.inventory` / `o.replica.inventoryitem`（见 `fn.GetComponent`）。
- **client 模式无法凭空生成图标资源**（`GetAtlasAndImage` 仅查缓存，spawn prefab 的路径被禁用）。缓存来源必须覆盖：主物品栏（`EachItem`，**不含装备也不含背包**）加上装备栏（`replica:GetEquips()`）加上 overflow 容器（背包：`itemget` 事件 + 遍历），再加上玩家的 `equip` 事件（跨 shard 迁移后物品直接落在装备槽，不经 `itemget`）。漏了哪路，哪路的物品就渲染成 `square.tex` 方块（都踩过）。
- **缓存写入与按钮渲染必须闭环**：缓存就绪时若对应按钮还是 fallback 方块，要主动 kill 重画（精确追踪哪些按钮是方块，别全量重画）；只靠"创建方块时安排几次延迟重试"会在物品晚到（在箱子里、classified 慢同步）时失效，方块永久常驻。
- **`GetInventoryItemAtlas(imagename, true)` 纯客户端可调**（simutil.lua 全局函数）：官方物品与已注册 atlas 的 mod 物品按 `prefab .. ".tex"` 就能查到图标，物品不在身上也能显示；`no_fallback=true` 让它查不到时返回 nil 而不是误拿 `images4.xml`。推断结果要带标记，物品入手后用真实图标（皮肤等特殊图标）覆盖。
- **replica `GetAtlas()` 的 images4 兜底是陷阱**：未注册 atlas 查询表的物品（服务端 mod 常见）会拿到 `images/inventoryimages4.xml` 错误路径——atlas/image 都有值但 region 不存在，渲染成空白（不是方块），且引擎不重试；错误数据若进缓存还会冒充"真实来源"阻断后续正确数据。任何来源的 atlas/image 引用写入缓存前都要 `TheSim:AtlasContains(atlas, image)` 验证。
- **未注册 atlas 的 mod 物品图标要落盘才能跨会话**。按名推断与物品入手都拿不到时（重上游戏、物品不在身上），唯一持久的办法是把入手时拿到的 `atlas/image` 引用写进本机持久化文件（SetPersistentString），重启后加载并用 `TheSim:AtlasContains` 校验（mod 卸载后资源未加载会返回 false，条目自动失效）。图标引用是静态资源标识，跨会话/跨服务器通用，全局存一份即可。
- **classified 同步可能晚于本地文件加载**。恢复配置后安排延迟刷新兜底：定时重跑 `PopulateIconCacheFromInventory`，配合上面的闭环钩子把 fallback 方块替换成真实图标。

## 5. 客户端持久化

- API：`TheSim:SetPersistentString(name, str, false)` / `TheSim:GetPersistentString(name, cb)`，异步。
- 落盘位置：`Documents\Klei\DoNotStarveTogether\<KleiID>\client_save\`。
- 官方范本：`scripts/playerhistory.lua`（脏标记 + json + SavePersistentString）。
- 客户端可用标识：`TheNet:GetServerName()`、`TheNet:GetUserID()`、`TheWorld:HasTag("cave")`；**`TheWorld.meta.session_identifier` 客户端拿不到**（meta 是 master-sim 组件）。

## 6. mod 加载机制

- 本地 mod：`<游戏根目录>\mods\<文件夹名>\`，**文件夹名即 mod 身份**；工坊 mod 身份是 `workshop-<id>`（引擎自动加前缀）。
- 启用判定：`ModIndex:GetModsToLoad`（enabled / modoverrides 强制 / temp）。
- 专用服/集群：shard 存档目录的 `..\modoverrides.lua`。
- 部署：游戏 mods 目录中的 mod 文件夹是指向仓库目录的 **Junction**（目录联接，无需管理员权限），仓库即游戏目录，**改完即生效，无需复制**：
  ```cmd
  mklink /J "D:\SteamLibrary\steamapps\common\Don't Starve Together\mods\<mod>" "D:\Code\MyMods\dst-mods\<mod>"
  ```
  - 替换已存在的真实目录前先 `diff -rq` 确认游戏侧无独有内容
  - 删除 Junction 用 `rmdir`（只删链接不删源）；仓库移动后链接会悬空，需重建

## 7. 调试手段

- **游戏 Lua 源码在本地**：`D:\SteamLibrary\steamapps\common\Don't Starve Together\data\databundles\scripts.zip`。怀疑引擎行为时解包 grep 求证（沙箱白名单、事件名、组件结构都在里面），不要凭记忆猜。
- 客户端日志：`D:\My\Documents\Klei\DoNotStarveTogether\client_log.txt`。
  ⚠️ 本机"文档"目录重定向到 `D:\My\Documents`（注册表 `User Shell Folders\Personal`），不在 `%USERPROFILE%` 下。
- 同目录有崩溃 dump（`donotstarvetogether_*.dmp`）和 caves 端日志。
- **游戏会缓存 mod 配置**：`client_save\mod_config_data\modconfiguration_<modname>`。改了 modinfo 默认值后旧缓存不会自动更新——界面里 Reset to Defaults，或删缓存文件。删掉已删除配置项没问题（多余键被忽略）。
- Lua 语法校验：本机无 lua/luac，用 `pip install luaparser`（新会话可能需重装）+ `luaparser.ast.parse`。

## 8. 本仓库 git 约定

- **只保留一个基线导入 commit**（原版 mod 源码），此后所有修改**保持未提交**——用户明确要求，不要主动 commit。
- 提交信息风格：中文、`【标签】描述`（见既有历史）。

## 9. 物品栏图标（arc_k9 踩了三轮才定案）

要让一个自制物品在背包里显示官方图标的**完整正确姿势**：

```lua
inst:AddComponent("inventoryitem")
inst.components.inventoryitem.imagename = "eyeturret_item"  -- 不带 .tex！走属性 setter
```

三条铁律（每条都对应一次失败）：

1. **别用 `ChangeImageName`**。它绕过属性 setter，只改 `self.imagename` 原始字段 + 推 `imagechange` 事件（`components/inventoryitem.lua:470-472`）。而 `imagechange` 全游戏只有 UI 的 `widgets/itemtile.lua:188` 在听，**不会写 net 变量**，客户端读 `classified.image` 永远为 0，图标空白。属性 setter 才走同步：
   ```lua
   -- inventoryitem.lua:5-7
   local function onimagename(self, imagename)
       self.inst.replica.inventoryitem:SetImage(imagename)
   end
   ```
2. **别设 `atlasname`**（除非你真的有 mod 本地 atlas）。官方兜底已经够用，而显式设会盖掉兜底：
   ```lua
   -- inventoryitem_replica.lua:163-168
   function InventoryItem:GetAtlas()
       return (override and override.atlas) or
           (self.classified.atlas:value() ~= 0 and self.classified.atlas:value()) or
           GetInventoryItemAtlas(self:GetImage())   -- ← 官方兜底，能用就别动
   end
   ```
   且 `atlasname` setter 会 `resolvefilepath()`——对 `images.zip` 内的游戏资源不可靠，设坏路径直接渲染失败。
3. **图标名必须在 inventoryimages1~4 里真实存在**，因为兜底函数只查这四卷（`simutil.lua:675-685`），**不查主卷 `images/inventoryimages.xml`**。名字写错（如 `mooneye` 不存在、真名是 `bluemooneye`）同样空白。

核名方法：解包 `data/databundles/images.zip`，解析 `<Element name="xxx.tex" ...>`（是 `Element` 不是 `Texture`）。

另：**modinfo 的 `icon_atlas`/`icon` 不能指向游戏内路径**（启动日志 `WARNING: icon paths ... are not valid`），必须是 mod 目录内的 tex+xml 对，需 ktech 等工具制作。

## 10. 创意工坊发布（steamcmd / ModUploader）

两条上传路线，职责不同：

| 路线 | 能做什么 | 不能做什么 |
|---|---|---|
| `steamcmd +workshop_build_item` | 更新内容、changenote | 改 tags、改版本标签 |
| `Don't Starve Mod Tools\ModUploader.exe` | 标题/描述/tags/预览图/新建条目 | 无法脚本化、要关游戏 |

### 10.1 steamcmd 的 VDF：省略即不动，写了就覆盖

`workshop_build_item` 只处理 VDF 里出现的键，**省略的字段不会被修改**，反之写了就整体覆盖。

所以 `publish/workshop_item.vdf` 只保留 4 个键：

```
"workshopitem"
{
	"appid"				"322330"
	"publishedfileid"	"3836742363"
	"contentfolder"		"D:/Code/MyMods/dst-mods/save_equipment_slots_fix"
	"changenote"		"0.1.1 描述格式修正"
}
```

### 10.2 写 `description` 会冲掉网页上手工润色的文案（踩过）

只要 VDF 里有 `description`（或 `title` / `previewfile` / `visibility`），这次上传就把对应字段替换成 VDF 里的值。
网页上改好的排版、封面、可见性会被打回，且**改动说明里只留一条记录，原文案只能从历史版本/存档里找回**。
规则：**描述只在网页维护；VDF 不写 description**。文案定稿存 `publish/workshop_description.txt`。

### 10.3 VDF 不支持 `\n` 转义（踩过）

VDF 字符串里写 `\n` 会被**原样入库**，工坊页面直接显示字面量 `\n\n`（满屏反斜杠）。
KeyValues 允许引号内出现真实换行，多行文案必须写成：

```
	"description"	"第一行
第二行"
```

校验办法见 10.6（读接口看描述里是 `0x0A` 还是 `0x5C 0x6E`）。

### 10.4 `tags` 段写了无效

`workshop_build_item` 支持的是 `kvtags`（key-value 标签），**不支持普通 tags**。
实测：VDF 里写 `"tags" { "0" "client_only_mod" }`，上传成功但条目标签一个没变。
`client_only_mod` / `version:x.y.z` 这类普通标签只能由 ModUploader 写入。

### 10.5 工坊条目的数据模型

- **标题/描述按语言分别存**（`ISteamUGC::SetItemUpdateLanguage`，不设置时默认 `english`）。
  页面按浏览者客户端语言取对应那份，**没有的语种回退 English**。
  两种「双语」写法：一段中英并列（落 English 槽位，所有人都看得到）或每种语言一条。
- **`changenote` 不分语言**，所有语言页面显示同一段文字。
- **没有「版本号」字段**。`modinfo.version` 只在游戏内 Mods 列表显示，
  并由 `mods.lua` 的 `IsModOutOfDate`（`TheSim:GetWorkshopVersion()`）判断工坊 mod 是否过期。
- ModUploader 会额外打一个普通标签 **`version:<modinfo.version>`**，页面标签栏可见、`?requiredtags[]=` 可筛；
  `GetWorkshopVersion()` 读的就是它。**steamcmd 发版不会更新它** → 只用 steamcmd 时版本标签会滞后，
  玩家仍会自动下载新内容（Steam 订阅），但游戏内「mod 过期」提示不刷新。需要同步就再用 ModUploader Update 一次。

### 10.6 校验上传结果：用 Web API，别刷社区页

社区页反复抓会 429（返回 12KB 的错误壳或空壳），而且 HTML 结构随 A/B 变。直接用公开接口：

```
curl -s -X POST https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/ \
  --data "itemcount=1&publishedfileids[0]=3836742363"
```

返回 `title` / `tags` / `description` / `time_updated`，无需登录，可用来核对：
描述有没有被覆盖、换行是真换行还是字面量、标签有没有变。

其他验证手段：

- 语言槽位：同一 ID 换 `&l=schinese` / `&l=english` / `&l=german` 对比（后者应有则显示、无则回退英文）。
- 标签类型：`workshop/browse/?appid=322330&requiredtags[]=version:0.1.1` 能筛出结果，
  说明它是**普通标签**（kvtags 不参与筛选）。

### 10.7 ModUploader 的坑

- **不选条目就是新建**。工具「Mod 列表」下拉里列的是你账号下已发布条目；不选直接发布 → 生成新 ID。
  新 ID 必须写回 VDF 的 `publishedfileid`，旧条目用工具里的 Delete 删掉（删后网页返回 500）。
- **打包的是整个 mod 目录**（`Update Data (ALL files in directory will be uploaded)`）。
  所以 mod 目录只放本体文件；开发用 README 之类放 `docs/`，否则会进订阅者的下载包。
- 描述框没有语言选项，写的是 `english` 槽位。
- Patch Notes 留空 → 工坊「改动说明」里出现一条无正文记录（删不掉）。
- 上传包大小对不上时先看目录里多了什么（本轮：README 15KB、preview.jpg 13KB 的差异就是这么定位的）。

### 10.8 steamcmd 登录态与重试

- 登录 token 缓存在 `steamcmd\config\config.vdf` 的 `ConnectCache`，一段时间内 `+login <user>` 免密；
  过期才提示密码 + 手机令牌。
- 上传报 `Failed to download manifest ".../manifest/..." (request failed)` 是 CDN 瞬时失败，**原命令重跑一次**即可。
