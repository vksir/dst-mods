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

## 10. 创意工坊发布（只用官方 ModUploader）

结论先行：发布统一走 `Don't Starve Mod Tools\ModUploader.exe`。
steamcmd 的 `workshop_build_item` 试过一整套（VDF + 脚本），**已弃用**，原因见 10.1。

### 10.1 为什么弃用 steamcmd

1. **写 `description` / `title` 会覆盖网页手写的文案**。VDF 里出现这两个键，这次上传就把对应字段整体替换；
   网页上润色过的排版会被打回，只能重贴（踩过）。
2. **VDF 不支持 `\n` 转义**。引号里写 `\n` 会原样入库，工坊页面显示字面量 `\n\n`；
   多行文案必须写**真实换行**（KeyValues 允许引号内换行）。
3. **`tags` 段完全无效**。`workshop_build_item` 只支持 `kvtags`（key-value 标签：页面不显示、不能按它筛选），
   不支持普通 tags。两种写法都实测过——数组块 `"tags" { "0" "client_only_mod" }`、
   逗号串 `"tags" "client_only_mod"`——上传均成功但条目标签一个没变（减法测试：原来的 `version:0.1.1` 没被移除）。
4. **`version:` 标签会停滞**。只会更内容的 steamcmd 无法刷新 `version:x.y.z`。
   玩家仍会自动下载新内容（Steam 订阅），但游戏内「mod 过期」提示不刷新，容易误判。

steamcmd 唯一的优势是「不用关游戏、可脚本化」，抵不过维护两套配置的成本。
若将来确实要临时更内容，VDF 只写 4 个键（`appid` / `publishedfileid` / `contentfolder` / `changenote`），
其余字段一律不写；否则就会命中上面第 1、2 条。

### 10.2 ModUploader 的坑

- **不选条目 = 新建条目**。「Mod 列表」下拉列的是账号下已发布条目，不选直接发布会生成新 ID；
  新 ID 要记住，旧条目用工具 Delete 删掉（删掉的条目网页返回 500）。
- **打包整个 mod 目录**（`Update Data (ALL files in directory will be uploaded)`）。
  README、临时文件放进去就会进订阅者的下载包——所以开发文档放 `docs/`，mod 目录只留本体。
  体积对不上时，先查目录里多了什么（本轮靠 15KB/13KB 的差值定位到 README 和 preview.jpg）。
- **描述框没有语言选项**，写的是 `english` 槽位；且每次 Update 都会用描述框内容整体覆盖工坊描述。
  网页上润色过的文案会被打回 → 定稿要粘进工具，或更新后回网页补。
- **Patch Notes 留空** → 「改动说明」里出现一条无正文记录，删不掉。
- 工具要占用 AppID 322330 的 Steam 接口，**游戏必须先关**。

### 10.3 工坊条目的数据模型

- **标题/描述按语言分别存**（`ISteamUGC::SetItemUpdateLanguage`，不设置时默认 `english`）。
  页面按浏览者客户端语言取对应那份，**没有的语种回退 English**。
  两种双语写法：一段中英并列（落 english 槽位，所有人都看得到）或每种语言一条（中文槽位只能在网页改）。
- **`changenote` 不分语言**，所有语言页面显示同一段文字。
- **没有「版本号」字段**。`modinfo.version` 只在游戏内 Mods 列表显示；工坊页面能看到的版本是标签 `version:x.y.z`。
- modinfo → 标签：

  | modinfo | 工坊标签 |
  |---|---|
  | `client_only_mod = true` | `client_only_mod` |
  | `server_only_mod = true` | `server_only_mod` |
  | `all_clients_require_mod = true` | `all_clients_require_mod` |
  | `*_compatible` | 各 DLC 兼容标签 |
  | `version = "x.y.z"` | `version:x.y.z`（`TheSim:GetWorkshopVersion()` 的来源） |

### 10.4 校验上传结果：用 Web API，别刷社区页

社区页反复抓会 429（返回 12KB 错误壳/空壳），HTML 结构也随 A/B 变。用公开接口：

```
curl -s -X POST https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/ --data "itemcount=1&publishedfileids[0]=3836742363"
```

返回 `title` / `tags` / `description` / `time_updated`，无需登录。可用来确认：
描述有没有被覆盖、换行是真换行还是字面量（`0x0A` vs `0x5C 0x6E`）、标签有没有变。

- 语言槽位：同一条目换 `&l=schinese` / `&l=english` / `&l=german` 对比。
- 标签类型：`workshop/browse/?appid=322330&requiredtags[]=version:0.1.1` 能筛出结果，
  说明它是**普通标签**（kvtags 不参与筛选）。
