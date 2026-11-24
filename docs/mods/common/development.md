# 开发指南（DST Mod）

> 本文合并了原《Mod 开发指南》与旧的踩坑记录（`dst-modding-pitfalls.md`，已退役）中的全部可复用结论
> （沙箱白名单、引擎行为、API 陷阱、容器/UI 机制，尽量带源码行号便于核对）。
> **单个 mod 的具体战役记录**放在 `docs/mods/<mod>/`，本文只写"任何 mod 都会用到"的东西。
> 引擎行为存疑时先解包 `data/databundles/scripts.zip` 求证，不要凭记忆猜。

## 目录

0. [设计与需求](#0-设计与需求)
1. [环境、部署与加载机制](#1-环境部署与加载机制)
2. [沙箱规则（最容易崩服）](#2-沙箱规则最容易崩服)
3. [资源声明 Asset](#3-资源声明-asset)
4. [物品图标管线](#4-物品图标管线)
5. [世界内外观管线（scml → anim.zip）](#5-世界内外观管线scml--animzip)
    - [5.6 用原版 fx 表的 prefab 生成特效时要知道的三件事](#56-用原版-fx-表的-prefab-生成特效时要知道的三件事)
6. [动作、组件动作与界面](#6-动作组件动作与界面)
7. [容器与面板](#7-容器与面板)
8. [状态、存档、网络同步与客户端持久化](#8-状态存档网络同步与客户端持久化)
9. [客户端 / 服务端双模式与 shard](#9-客户端--服务端双模式与-shard)
10. [调试](#10-调试)
11. [工具使用方法](#11-工具使用方法)
12. [报错速查表](#12-报错速查表)
13. [推荐目录结构](#13-推荐目录结构)

---

## 0. 设计与需求

### 0.1 先落 spec，再写代码

需求来自用户口头/速记，先拆成可验收的条目写进 `.scratch/<feature-slug>/spec.md`：

```md
- [ ] 加速表改两档：30% / 50%（右键文案随档位变）
- [ ] 减速表同步改两档
- [ ] 两者加算叠加：50% + 50% = 老化加快 100%
```

每条都必须能回答"**怎么证明它成立**"。写不出验收方法的条目，先找用户确认。

### 0.2 单一数据源

倍率、档位、数值只在**一个模块**里定义，其它地方一律读它：

```lua
-- scripts/<mod>_state.lua
Age.HASTE_TIERS = { 0, 0.30, 0.50 }
Age.SLOW_TIERS  = { 0, 0.30, 0.50 }
```

反例（真实踩过）：档位表在 modmain、显示名写死在 prefab、`modinfo` 描述写第三份数字，
改需求漏改一处 → 物品名说 50%、实际生效 60%。

**改数值时同步检查**：`modinfo.lua` 的 `description` + `hover`、`STRINGS` 名字、
右键文案的档位数（`#TIERS`）、旧存档迁移（`ClampTier`）。

### 0.3 状态分层

| 状态 | 放哪 | 例 |
|---|---|---|
| 物品自身 | 物品字段 + netvar | 充能、读数 |
| **跟着人的** | 玩家字段/netvar/tag，物品只做遥控器 | buff、档位 |
| 世界级 | `TheWorld` 组件 | 全局开关 |

"跟着人"的状态要处理两条边界：丢在地上不失效；最后一件移除时归零（`onremove` 里判断注册表空）。

### 0.4 覆盖原版函数

一律"包一层 + 先调旧实现 + 只对自己关心的实体生效"，且**旧函数每次现读**（可能已被别人包过）：

```lua
local Old = inst.components.container.Open
inst.components.container.Open = function(self, ...)
    if 不该管 then return Old(self, ...) end
    ...
end
```

用 `prefab ==` 精确匹配，别用 tag（tag 会被别的 mod 复用）。

### 0.5 命名

- `scripts/` 下文件名、netvar 名、prefab 名都带 mod 前缀（原因见 §2.5）；
- 常量（面板坐标、缩放、对齐基准）提到文件顶部并注明实测分辨率。

---

## 1. 环境、部署与加载机制

### 1.1 路径

| 用途 | 典型路径 |
|---|---|
| 游戏本体 | `…/steamapps/common/Don't Starve Together/` |
| 引擎 Lua 源码 | `…/Don't Starve Together/data/databundles/scripts.zip` |
| 官方工具 | `…/common/Don't Starve Mod Tools/mod_tools/` |
| 游戏 mod 目录 | `…/Don't Starve Together/mods/<mod>/` |
| 客户端日志 | `文档/Klei/DoNotStarveTogether/client_log.txt` |
| 客户端持久化 | `文档/Klei/DoNotStarveTogether/<KleiID>/client_save/` |
| 存档 | `文档/Klei/DoNotStarveTogether/<userid>/Cluster_N/` |

本机"文档"目录被重定向到 `D:\My\Documents`（注册表 `User Shell Folders\Personal`），
不在 `%USERPROFILE%` 下 → 找日志时先用 `[Environment]::GetFolderPath('MyDocuments')` 确认。

`mod_tools/` 里有：`autocompiler.exe`（批量 png→tex / scml→anim）、`scml.exe`（单个 scml）、
`Spriter/Spriter.exe`（图形化）、`sample_build/build.scml`（官方范本）。

### 1.2 Junction 部署（本仓库默认）

仓库里的 `mods/<mod>` 做成指向游戏 mods 目录的目录联接（`/J` 不需要管理员）：

```bat
mklink /J "…\Don't Starve Together\mods\<mod>" "D:\Code\MyMods\dst-mods\mods\<mod>"
```

**仓库即游戏目录，改完即生效**（脚本改动重进世界；`modmain`/`modinfo`/资源需重启客户端）。

- 替换已有的真实目录前先 `diff -rq` 确认游戏侧没有独有内容；
- 删除用 `rmdir`（只删链接不删源）；仓库搬家后链接悬空，按新路径重建。

### 1.3 mod 加载机制

- 本地 mod：`<游戏根目录>\mods\<文件夹名>\`，**文件夹名即 mod 身份**；
  工坊 mod 是 `workshop-<id>`（引擎自动加前缀）。
- 启用判定：`ModIndex:GetModsToLoad`（enabled / `modoverrides.lua` 强制 / temp）。
- 专用服/集群：shard 存档目录下的 `..\modoverrides.lua`。
- **mod 配置会缓存**：`client_save\mod_config_data\modconfiguration_<modname>`。
  改了 `modinfo` 的默认值后旧缓存不会自动更新 → 界面里 Reset to Defaults，或删缓存文件
  （已删除的配置项留着多余键无害）。

### 1.4 开发循环

1. 改 lua → 重进世界（改 `modmain`/`modinfo` 直接重启客户端）；
2. 改资源（png/scml）→ 编译 → **重启游戏**（资源只在启动时加载）；
3. 控制台（`` ` ``）或临时自检模块跑断言（§10.3）；
4. 看 `client_log.txt`（服务端看 `server_log.txt`）。

### 1.5 客户端图标缓存

改了 `modicon.png` 可能长时间不更新 → 删 `文档/Klei/DoNotStarveTogether/cache/` 下相关目录。

---

## 2. 沙箱规则（最容易崩服）

### 2.1 `modmain.lua`：标准库残缺（崩过两次）

`modmain.lua` 的环境由 `scripts/mods.lua:297 CreateEnvironment` 建立，**只白名单**：

```
pairs, ipairs, print, math, table, type, string, tostring, require, Class, GLOBAL
```

**缺失**：`next`、`pcall`、`tonumber`、`unpack`、`setmetatable`、`error`、`os` …

```lua
local next = GLOBAL.next
local pcall = GLOBAL.pcall
local tonumber = GLOBAL.tonumber
```

崩溃形态：`attempt to call global 'next' (a nil value)`，在进世界 tick 6 左右。
引擎 API 一律走 `GLOBAL`（`GLOBAL.TheSim`、`GLOBAL.TheNet`、`GLOBAL.json`…）。

### 2.2 `modinfo.lua`：零标准库（导致过启动闪退）

执行环境（`scripts/modindex.lua:593 InitializeModInfo`）**只有 3 个变量**：
`folder_name`、`locale`、`ChooseTranslationTable`。

- ✅ 字符串/数字字面量、表构造器、算术、拼接、**字符串元表调用**：`("").char(65 + i)`
- ❌ `string.byte(...)`、`math.floor(...)`、任何标准库全局
- ⚠️ 崩溃形态最恶劣：modinfo 在 `main.lua` 启动阶段加载，报错级联成
  `Error during game initialization!` → **直接闪退**（不是游戏内错误弹窗）

### 2.3 mod API 裸写、游戏全局加 `GLOBAL`

| 写法 | 结果 | 正确做法 |
|---|---|---|
| `pcall(...)` / `require("x")` | `attempt to call global … (a nil value)` | `GLOBAL.pcall` / `GLOBAL.require` |
| `GLOBAL.AddAction(...)` | `variable 'AddAction' is not declared`，**整个 mod 被禁用** | 裸写 `AddAction`（mod 环境注入，不在 `_G`） |
| `GLOBAL.AddComponentAction/AddPrefabPostInit/AddPlayerPostInit/AddRecipe2/AddStategraphActionHandler` | 同上 | 全部裸写 |
| 裸写 `Action` / `Ingredient` / `TECH` / `STRINGS` / `TUNING` | 未声明报错 | 这些**是**真全局，必须 `GLOBAL.` |

判断标准：**mod 注入接口裸写；游戏脚本里定义的全局加 `GLOBAL.`**。

### 2.4 `require` 加载的模块跑在 `_G`

`scripts/*.lua` 没有 `GLOBAL` 代理：直接写 `ThePlayer`、`ACTIONS.WRITE`、`pcall`、`setmetatable`；
写了 `GLOBAL.ThePlayer` 才是 nil。

> 同一个仓库里 `modmain` 要 `GLOBAL.pcall`、`scripts/foo.lua` 直接 `pcall`——最容易写反的地方。

### 2.5 `package.path` 里塞了所有 mod 的 `scripts/`

`mods.lua:528` 把**每个** mod 的 `scripts/` 都加进 `package.path` →
模块名必须带 mod 前缀（`my_mod_state`），否则可能被别的 mod 同名文件顶掉。

### 2.6 不要缓存世界对象为 upvalue

```lua
-- 错：加载 mod 时 TheWorld 还是 nil
local world = TheWorld
-- 对：
local function IsMasterSim() return GLOBAL.TheWorld ~= nil and GLOBAL.TheWorld.ismastersim end
```

### 2.7 `debug.traceback()` 会崩服

`debug` 表存在但 `traceback` 被换过，沙箱里调用直接抛错。**绝不**放进 `Container:Close`、
`GetAttacked`、`Inventory:DROP` 这类高频/关键路径——玩家死亡掉落时直接崩服。
诊断改用分段 `print` + `GLOBAL.GetTime()` 时间戳。

### 2.8 几个"看着能用其实没有"的字符串键

- **`STRINGS.RECIPEDESC` 不存在**（老版键名）。现代键是 `STRINGS.RECIPE_DESC`
  （`strings.lua:4834`，取用处 `recipepopup.lua:297`）。写错 → 启动崩溃。
- `STRINGS.NAMES` / `STRINGS.CHARACTERS.GENERIC.DESCRIBE` 正常存在。

---

## 3. 资源声明 Asset

```lua
Assets =
{
    Asset("ATLAS",       "images/inventoryimages/myitem.xml"),
    Asset("IMAGE",       "images/inventoryimages/myitem.tex"),
    Asset("ANIM",        "anim/my_item.zip"),
    Asset("SOUND",       "sound/my_sound.fsb"),
    Asset("ATLAS_BUILD", "images/xxx.xml", 256),
}
```

可写在 `modmain.lua`，也可写在 prefab 顶部（`assets`/`Assets` 会被合并）。

### 3.1 `INV_IMAGE` 只认原版图集（大坑）

```lua
Asset("INV_IMAGE", "myitem")     -- ❌ mod 物品永远不显示
```

`mainfunctions.lua:96 ShouldIgnoreResolve()` 对 `INV_IMAGE` 直接 `return true`，
即**不做 mod 相对路径解析**，裸名字只在原版 `images/inventoryimages1~4` 里找。

失败形态不是报错，而是运行时反复刷：

```
WARNING! Invalid resource handle for atlas '../mods/<mod>/images/inventoryimages/x.xml',
         did you remember to load the asset?
Looking for default texture '' from atlas '../mods/.../x.xml'.
```

物品栏 + 制作栏一起空白（`Recipe:GetAtlas()` 解析出同一个路径）。

**排查口径**：先 `grep "Invalid resource handle" client_log.txt`，再核对 prefab 的 assets；
别去怀疑 tex 格式或 uv——图集都没加载时贴图长什么样都无所谓。

### 3.2 制作栏图标要额外传 atlas

`Recipe:GetAtlas()` 只查原版 4 张图集：

```lua
AddRecipe2("myitem", { Ingredient("goldnugget", 1) }, TECH.NONE,
    { atlas = "images/inventoryimages/myitem.xml", image = "myitem.tex", builder_tag = "clockmaker" },
    { "CHARACTER" })
```

配合 `RegisterInventoryItemAtlas("images/inventoryimages/myitem.xml", "myitem.tex")`。

### 3.3 `modinfo` 的图标：必须是 mod 内文件，且 tex/xml 放**mod 根目录**

`scripts/modindex.lua:542-557` 是这样拼路径的：

```lua
local atlaspath = MODS_ROOT..modname.."/"..info.icon_atlas      -- mods/<mod>/modicon.xml
local iconpath  = <atlaspath 的目录> .. "/" .. info.icon         -- mods/<mod>/modicon.tex
if softresolvefilepath(atlaspath) and softresolvefilepath(iconpath) then ... else <<置 nil>> end
```

所以：

- ✅ 正确：`mods/<mod>/modicon.tex` + `modicon.xml`（根目录），`icon_atlas = "modicon.xml"`；
- ✅ 也可以：文件放子目录，但 `icon_atlas` 要带子目录（`"images/modicon.xml"`）；
- ❌ 踩过：png 放 `images/modicon.png` 编出 `images/modicon.tex`，`icon_atlas` 却写 `"modicon.xml"`
  → 路径解析失败，**图标静默变空**（Mods 列表还是默认灰图），日志只有一行
  `WARNING: icon paths for mod <mod> (<name>) are not valid. Got icon_atlas="modicon.xml" and icon="modicon.tex".`

其它约束：tex/xml 必须是 mod 目录里的文件（指向游戏内路径同样报上面那行 WARNING）；
`modicon` 建议 256×256（与其它 mod 一致，autocompiler 直接吃根目录的 `modicon.png`）。

---

## 4. 物品图标管线

### 4.1 目录与编译

```
mods/<mod>/images/inventoryimages/
├── myitem.png     ← 64×64 RGBA（你画的）
├── myitem.tex     ← 编译产物（通常 5566 字节）
└── myitem.xml     ← 图集索引
```

```bash
rm -f images/inventoryimages/myitem.{tex,xml}     # 先删，否则 autocompiler 按时间戳跳过
"D:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/autocompiler.exe" \
    "D:/Code/MyMods/dst-mods/mods/<mod>"
```

### 4.2 运行时换图标的正确姿势

```lua
inst:AddComponent("inventoryitem")
inst.components.inventoryitem.imagename = "eyeturret_item"   -- 不带 .tex！走属性 setter
```

三条铁律（每条对应一次失败）：

1. **别用 `ChangeImageName`**。它绕过属性 setter，只改原始字段 + 推 `imagechange` 事件
   （`components/inventoryitem.lua:470-472`），而 `imagechange` 只有 UI 的
   `widgets/itemtile.lua:188` 在听，**不写 net 变量** → 客户端读到的 image 永远是 0，图标空白。
2. **别设 `atlasname`**（除非你真有 mod 本地 atlas）：`atlasname` setter 会 `resolvefilepath()`
   （对 `images.zip` 内资源不可靠），并且会盖掉官方兜底
   （`inventoryitem_replica.lua:163-168` 的 `GetInventoryItemAtlas(self:GetImage())`）。
3. **图标名必须在 `inventoryimages1~4` 里真实存在**，兜底只查这四卷
   （`simutil.lua:675-685`），**不查主卷 `images/inventoryimages.xml`**。
   名字错（如 `mooneye` 实际叫 `bluemooneye`）同样空白。

核名方法：解包 `data/databundles/images.zip`，解析 `<Element name="xxx.tex" …>`
（是 `Element` 不是 `Texture`）。

### 4.3 KTEX 解码（回读产物 / 复用原版美术）

`data/databundles/images.zip` 里的图集是 **KTEX（BC3/DXT5）+ 全 mip 链**，Pillow 不认，
`mod_tools` 的 `TextureConverter.exe` 也不吃。用 `tools/common/ktex2png.py`：

- 头部：magic `KTEX` + 8 字节，偏移 8 处两个 `uint16` 是宽高；
- **头部长度随 mip 数变化**（2048² 图集 128 字节、64² 图标 78 字节）→
  用 `文件长度 − BC3 全 mip 链字节数（每个 mip 16 字节对齐）` 反推最稳；
- 之后是 mip0 的 BC3 数据，自己解 DXT5（alpha 8 字节块 + 颜色 8 字节块）。

### 4.4 方向：PNG 就是显示方向，**解码 atlas 后要翻正**

用解码器回读 **autocompiler 产物**时会看到与源 PNG 上下翻转（差值仅 DXT 级）——
不是 bug：autocompiler 以翻转行序写 KTEX，引擎加载时翻回来。
**不要手动翻转 png**；反过来，从原版图集裁图时按 `u1/v1/u2/v2` 裁（v 是上边界）得到的是翻转图，
要"真实美术"得按 `y = (1 - v2) * height` 裁。

**从 `anim/*.zip` 里解 `atlas-0.tex` 也一样**：解码出来是倒的，直接用于展示/拼图会出错
（实测：怀表的挂环跑到下面、表冠方向反；`tools/wanda_planar_plan/gen_workshop_preview.py`
踩过，修法是 `im.transpose(Image.FLIP_TOP_BOTTOM)`）。判断标准：和同一物品的
`inventoryimages/*.png`（自己画的、正方向）比对，一致才算对。

### 4.5 设计建议（46px 实机的现实）

- 64×64，按 4~8 倍绘制再 LANCZOS 缩小；描边 2px 左右，贴原版贴纸风格；
- 透明边缘做颜色扩散（近透明像素 RGB 填邻近不透明色），否则 mipmap 出黑边；
- **物品栏实际只有 46px**：只有「正圆 / 平涂 / 实心块」活得下来，
  细线、排线纹理、噪点、多环链子在 46px 后一律糊成脏灰：
  - 圆形画**正圆**，不要椭圆/透视压扁；
  - 平涂 + 一层月牙内阴影 + 一处高光，别叠颗粒；
  - 指针只画**一根**（粗 ~1.75），双针必糊；
  - 指示符号（箭头/沙漏）用**实心剪影 + 粗墨描边**，别空心描边；
  - 表链/链环等细节**只放 128px 地面精灵**；
- 画完**回读 atlas 产物核对**（§4.3），别只看自己生成的 png。

---

## 5. 世界内外观管线（scml → anim.zip）

丢在地上显示的是 `AnimState` 的 bank/build，不是 inventoryimages 里的图。复用原版 build
会和同族原版物品长得一样（`SetMultColour` 只能染色）。

### 5.1 工具

```bash
scml.exe <in.scml> <outdir>      # → <outdir>/anim/<scml文件名>.zip
```

zip 内含 `anim.bin`（动画）、`build.bin`（符号/图集映射）、`atlas-0.tex`（贴图）。

### 5.2 最小 scml

```xml
<?xml version="1.0" ?>
<spriter_data generator="BrashMonkey Spriter" generator_version="b5" scml_version="1.0">
  <folder id="0" name="spr">
    <file height="128" id="0" name="spr/sprite-0.png" pivot_x="0.5" pivot_y="0.5" width="128"/>
  </folder>
  <entity id="0" name="my_item">                <!-- entity 名 = build 名 -->
    <animation id="0" length="1000" name="idle">
      <mainline><key id="0">
        <object_ref abs_a="1" abs_angle="360" abs_pivot_x="0.5" abs_pivot_y="0.5"
          abs_scale_x="1" abs_scale_y="1" abs_x="0" abs_y="0"
          file="0" folder="0" id="0" key="0" name="watchprop" timeline="0" z_index="0"/>
      </key></mainline>
      <timeline id="0" name="watchprop"><key id="0" spin="0">
        <object angle="0.0" file="0" folder="0" id="0" scale_x="1.0" scale_y="1.0" x="0" y="0"/>
      </key></timeline>
    </animation>
  </entity>
</spriter_data>
```

多动画名指向同一帧：复制 `<animation>` 块改 `name`（id 递增）。

### 5.3 三个必须踩过的坑

| 坑 | 症状 | 解法 |
|---|---|---|
| **动画名对不上** | 不报错，渲染成一块乱码形状（极易误判为贴图坏了） | bank 里必须有 prefab 实际 `PlayAnimation("…")` 的名字；背包类常用 `"anim"`、钟表类用 `"idle"`；稳妥做法是 `idle / idle_loop / anim / cooldown_long / cooldown_short / swap` 全生成 |
| **符号名对不上** | 施法/装备时看不到模型 | 怀表类会 `OverrideSymbol("watchprop", item_build, "watchprop")`，scml 的 object/timeline 直接叫 `watchprop` |
| **`scml.exe` 找不到 python** | `Unable to find python!`，偶发 | 从 bash 直接调用；用 Python `subprocess` 时子进程拿到 POSIX 风格 PATH（`/c/...`），必须把解释器目录以 Windows 形式塞进 `env["PATH"]` 并重试 |

### 5.4 prefab 接上

```lua
inst.AnimState:SetBank("my_item")     -- = anim.bin 的 bank
inst.AnimState:SetBuild("my_item")    -- = build.bin 的 build
inst.AnimState:PlayAnimation("idle")
```

精灵 128×128 + `SetScale(1,1,1)` 时地面观感约与手相当。

### 5.5 生成器

`tools/wanda_planar_plan/gen_item_build.py` 是完整参考（Pillow 画图 + 生成 scml +
调 `scml.exe` + 拷贝 zip）。新 mod 复用它时拷到 `tools/<mod>/`，把画图部分换掉。

---

## 5.6 用原版 fx 表的 prefab 生成特效时要知道的三件事

`prefabs/fx.lua` 会把 `scripts/fx.lua` 里的条目批量包成 prefab（`SpawnPrefab("shadow_shield3")`
这类）。它内部是「服务端代理 + 客户端本地特效」两层：

1. **代理实体是 `SetCanSleep(false)`，只在 `animover` 时自毁**。动画事件不来（名字写成
   `idle*` 之类的循环动画）就**永久常驻**，每放一次技能叠一个 → 越玩越卡。
   自己生成的特效要能管住生命周期（记录引用 + `KillFX` / `DoTaskInTime` 兜底）。
2. **本地特效用 `Transform:SetFromProxy(proxy.GUID)` 定位**，是独立实体：
   移除代理**不会**带走它，反过来也一样。所以清理要针对"能被移除的那个"下手。
3. **颜色 / 等级这类外观参数走道具字段或方法**（`castfxcolour`、`SetFXLevel`）。
   只在服务端设置时，客户端预测出来的那份特效读不到 → 退默认值（常常是白色）。
   两端都要的显示参数写在 prefab 的 `common_postinit`（`SetPristine` 之前）里。

> 排查这类问题：先 `FindEntities(x,y,z,3,{"FX"})` 数玩家身上挂了几个 FX，正常 ≤1~2；
> 再逐个打印 `prefab / pos / AnimState:GetScale() / parent / 当前动画名`，
> 找出常驻或缩放异常的那个。

## 6. 动作、组件动作与界面

### 6.1 自定义动作

```lua
local MyAction = GLOBAL.Action({ rmb = true, priority = 2, distance = 0 })
MyAction.id = "MY_ACTION"
MyAction.str = "do it"
MyAction.fn = function(act) ... return true end
AddAction(MyAction)                          -- modmain 裸写
GLOBAL.STRINGS.ACTIONS.MY_ACTION = "做事"
```

### 6.2 两个必要条件（否则静默失效）

1. **要么 `instant = true`**，要么注册状态机 handler：

```lua
MyAction.instant = false
AddStategraphActionHandler("wilson", GLOBAL.ActionHandler(MyAction, "doshortaction"))
AddStategraphActionHandler("wilson_client", GLOBAL.ActionHandler(MyAction, "doshortaction"))
```

不满足时：**悬停提示正常，点击后 `fn` 永不执行**——
`StateGraphInstance:PreviewAction` 找不到 handler，非 instant 动作被当 `previewaction`
静默丢弃。这个坑极具迷惑性，先查这条。

- instant 动作走 `locomotor.lua:946` → `entityscript.lua:1660` 直接 `bufferedaction:Do()`；
- 客户端预测要额外给 `wilson_client` 注册一份。

### 6.3 动态文案：`stroverridefn`

不要改全局 `STRINGS.ACTIONS.X`（会影响原版同类动作）：

```lua
MyAction.stroverridefn = function(act)
    local item = act.invobject
    if item == nil then return nil end            -- 返回 nil 回落到原版文案
    if item:HasTag("my_on") then return "关闭" end
    return "开启"
end
```

tag/netvar 是"客户端也读得到"的状态来源。

### 6.4 物品栏右键动作的 `right` 参数

`Inventory:UseItemFromInvTile`（`components/inventory.lua:2270`）调 `GetInventoryActions(item)`
**不传 `right`** → 实际点击时是 `nil`，悬停预览时是 `true`：

```lua
AddComponentAction("INVENTORY", "container", function(inst, doer, actions, right)
    if right == false then return end      -- 别写 if not right then return end
end)
```

写错会"悬停能看到、点下去没反应"。

### 6.5 "手上有工具、目标是另一件物品"的动作：注册在 USEITEM

典型场景：羽毛笔在鼠标上 → 悬停表 → 右键「命名」。链路是

```
Inventory:UseItemFromInvTile (inventory.lua:2270)
  → playeractionpicker:GetUseItemActions(item, active_item, true)
  → useitem:CollectActions("USEITEM", doer, target, actions, right)
```

```lua
AddComponentAction("USEITEM", "inventoryitem", function(inst, doer, target, actions, right)
    if inst.prefab ~= "featherpencil" then return end
    if target.prefab ~= "my_watch" then return end
    table.insert(actions, ACTIONS.WRITE)
end)
```

三个坑：

- 注册在**目标**上的 `INVENTORY` 收集器在这条路径上**不会被调用**；
- 组件名必须是**客户端也存在**的组件：`EntityScript:CollectActions` 只遍历实体上真实存在的组件
  （`componentactions.lua:3236`），`writeable` 只有服务端组件（客户端只有 `writeable_replica`），
  所以 `AddComponentAction("INVENTORY", "writeable", …)` 在客户端永不触发。
  可用替代：`inventoryitem` / `named`；
- 同一组件名在 `MOD_ACTION_COMPONENT_IDS` 里**一个 name 一个 id**，同组件注册多个 actiontype
  会互相覆盖 → 给不同 actiontype 用不同组件名。

### 6.6 tooltip 的"右键: xxx"从哪来

`widgets/itemtile.lua:511`（手上没东西，用 `GetInventoryActions`）与 `:529`（手上有东西，
用 `GetUseItemActions`）都会拼 `actions[1]:GetActionString()`。动作能被收集到，tooltip 自动就有，
**不要**再包 `ItemTile:GetDescriptionString`（会显示两行）。

### 6.7 只给特定物品动作

```lua
if inst.prefab ~= "my_item" then return end
```

prefab 名比 tag 精确。

### 6.8 命名（羽毛笔写名字）

官方范本 `prefabs/kitcoon_nametag.lua`：`writeables.AddLayout(prefab, {…})` + 给物品加
`writeable` / `named` 组件：

```lua
inst.components.named.nameformat = (GLOBAL.STRINGS.NAMES[string.upper(prefab)] or "") .. "-%s"
```

显示名走 `inst.displaynamefn`（保留"潮湿/破损"等形容词），不要覆盖 `GetDisplayName`。
右键文案用 §6.3 挂在 `GLOBAL.ACTIONS.WRITE` 上（先存旧值，非本物品回落旧值）。

### 6.9 动作会被"前置过滤器"整体挡掉（骑牛 / 搬重物 / 手持漂浮物）

`Action(data)` 里有一组**能力开关**，默认全 `false`（`actions.lua:310-318`）。
玩家处于对应状态时，`playeractionpicker` 会压一个过滤器，**只放行带该开关的动作**，
其余动作在 `SortActionList` 里被丢掉（`playeractionpicker.lua:94`）——
**悬停没提示、点了没反应，报错为零**，和 §6.2 的静默失效是同一类坑。

| 状态 | 过滤器 | 需要的字段 | 优先级 |
|---|---|---|---|
| 骑着牛 | `rider_replica.lua` `MountedActionFilter` | `mount_valid = true` | `mounted` 20 |
| 搬重物（雕像等） | `inventory_replica.lua` `HeavyLiftingActionFilter` | `encumbered_valid = true` | `heavylifting` 10 |
| 手持漂浮物 | `inventory_replica.lua` `FloaterHeldActionFilter` | `floating_valid = true` | `floaterheld` 15 |

```lua
local MyAction = GLOBAL.Action({ rmb = true, mount_valid = true })  -- 骑牛也能用
```

- 过滤器作用在**所有**动作收集器上（`INVENTORY` / `USEITEM` / `SCENE` …），
  不是只管场景动作；
- 好了对表：`RUMMAGE` / `EAT` / `ADDFUEL` / `PICKUP` 这些都是 `mount_valid = true`，
  而 `CAST_POCKETWATCH` 不是（原版骑乘时不能从物品栏施法）；
- **顺手检查自己的组件动作有没有加骑乘判断**：原版 `componentactions.lua` 的
  pocketwatch / writeable 等收集器里有显式
  `not (doer.replica.rider and doer.replica.rider:IsRiding())`，抄原版时别只抄一半；
- 只加状态真正需要的那个字段。比如钟表袋只需要 `mount_valid`——原版 `RUMMAGE` 也没有
  `encumbered_valid`，加了就是和原版不一致的额外能力。

**症状记忆点**："平时能开，骑上牛就关不掉""搬着雕像右键没反应"——先查这张表。

---

## 7. 容器与面板

### 7.1 自定义容器布局

`scripts/containers.lua` 的 `params` 是模块内 local 表，自定义 prefab 查不到 → 包 `containers.widgetsetup`：

```lua
local containers = GLOBAL.require("containers")
local OldWidgetSetup = containers.widgetsetup

local MY_WIDGET = {
    slotpos = {},  animbank = "ui_krampusbag_2x8", animbuild = "ui_krampusbag_2x8",
    pos = Vector3(-205, -130, 0), slotscale = 0.86,
}

containers.params.my_bag = MY_WIDGET      -- ★ 客户端要用（见 7.7）

containers.widgetsetup = function(container, prefab, data)
    if prefab == "my_bag" then
        container.widget = MY_WIDGET
        container.issidewidget = true
        container.type = "my_bag"          -- 别用 "pack"，见 7.5
        container.openlimit = 1
        container:SetNumSlots(#MY_WIDGET.slotpos)
        return
    end
    return OldWidgetSetup(container, prefab, data)
end
```

### 7.2 取消"走远自动关闭"

`Container:OnUpdate` 会在玩家不处于 `keep_pocket_rummage` 时自动关闭。要"走动不关"，
覆盖 `Close`（7.4）比逐条堵自动关闭路径省事。

### 7.3 侧边面板位置

`containerroot_side`（`widgets/controls.lua:285`）是右对齐 + 垂直居中，原版背包/克劳斯袋/
种子袋都用 `pos = (-5, …)`，**自定义容器写 -5 就会和背包完全重叠**。

- 横向：往左挪一个面板宽度（`pos` 单位），面板宽 = 底图局部宽度 × `ContainerWidget` 的 0.6 缩放；
- 纵向：**每套底图的 `pos.y` 都不同**，因为各自美术中心不同：

  | prefab | animbuild | pos |
  |---|---|---|
  | `backpack` | `ui_backpack_2x4` | `(-5,-80)` |
  | `spicepack` | `ui_icepack_2x3` | `(-5,-70)` |
  | `piggyback` | `ui_piggyback_2x6` | `(-5,-90)` |
  | `krampus_sack` / `seedpouch` / `candybag` | `ui_krampusbag_2x8` | `(-5,-130)` |

  想和相邻面板上下对中，**读对面的美术包围盒**求差，不能写死：

  ```lua
  local ok, x1, y1, x2, y2 = pcall(bganim.GetVisualBB, bganim)   -- widgets/uianim.lua:23
  local center = (y1 + y2) * 0.5                                  -- ContainerWidget 局部单位
  y = neighbor.pos.y + (center_neighbor - center_self) * 0.6       -- 0.6 = ContainerWidget 缩放
  ```

  - `GetVisualBB()` 返回**当前动画帧**的包围盒：刚开箱还在"弹出"动画里（只有 40 多单位高），
    必须等动画停（正常 350~550）才可用 → 加 `if (y2 - y1) < 200 then 跳过 end`；
  - 自己那张图可以直接写常量（美术固定）；
  - 单位：1 pos ≈ 1.64px、1 局部单位 ≈ 0.98px（2560×1440 / HUDSize 7 实测），比值正好 0.6。

### 7.4 只认自己发起的关闭（注意重入）

原版 `Container:Close(doer)` 与 `Close(nil)` 是**同一个函数**：传 nil 时遍历 `openlist`
递归 `self:Close(各 opener)`。所以"把带 doer 的调用一律拦掉"会让**广播式关闭在第一次递归时
被自己的闸挡住**（实测 `opencount` 永远是 1）。必须带重入标记：

```lua
local OldClose = inst.components.container.Close
inst.components.container.Close = function(self, doer, ...)
    if doer ~= nil and not self._closing then return end
    self._closing = true
    local r = OldClose(self, doer, ...)
    self._closing = nil
    return r
end
```

自己关时用广播式 `container:Close()`。别在这里放 `debug.traceback`（§2.7）。

### 7.5 `container.type` 不能复用 `"pack"`

`Container:Open`（`components/container.lua:625`）会关闭**同 type** 的其它容器 →
开背包把袋子顶掉、反之亦然。自定义字符串即可（`"chest"` 之类会被特殊判定）。
借原版 type 前先确认"同 type 的那个容器不会和你的同时存在"。

### 7.6 融合背包（Integrated Backpack）下的面板锚点

`container.type` 决定面板挂哪个 root（`screens/playerhud.lua:402-412`）：

| type | root |
|---|---|
| `side_inv_behind` | `controls.containerroot_side_behind` |
| `side_inv` / `inv` / `hand_inv` | 同一个 `containerroot_side_behind` |
| `top_rack` / `chest_addon` | 各自的 rack |
| **其余（含自定义 type）** | `containerroot` —— **屏幕正中央** |

- 想让面板出现在原版背包那一列，**把 type 设成上表里的原版值**，
  不要给自定义 type 调 `pos.x`（`containerroot` 是中心锚，换分辨率就漂）；
- `containerroot_side_behind`（`widgets/controls.lua:279-283`）是 `ANCHOR_RIGHT + ANCHOR_MIDDLE`
  + `SCALEMODE_PROPORTIONAL`，天然贴右、垂直居中、分辨率无关；
- 融合模式下原版会主动关掉 side widget 容器（`playerhud.lua:391`）→ 必须 `issidewidget = false`；
- 借 type 前确认不冲突：`side_inv_behind` 是韦伯胡子袋在用（不同角色可安全借用）。

### 7.7 布局必须在"开箱时"重算

`Container:WidgetSetup` 只在组件初始化时跑一次，而 `Profile`（`GetIntegratedBackpack`）是
**客户端专属**的：服务端那份永远算"分开布局"，玩家中途切换设置后客户端还留旧值 →
表现是"面板挂错槽位、和原版背包叠在一起"。

修法：包一层 `PlayerHud:OpenContainer`，开箱前按当前设置重算 `side / issidewidget / type`；
位置基准**跟着实际挂载的 root 走**，不要跟着设置项走。

另外：`containers.widgetsetup` 在**客户端**是以 `prefab = nil` 调用的
（`container_replica.lua:47`，内部回落 `params[container.inst.prefab]`）→
自定义容器必须写 `containers.params.<prefab>`，否则真客户端/专服上
`replica.container.widget` 是 nil，`containerwidget.lua:28` 直接索引 nil 崩。

### 7.8 多面板排排坐（原版不会自动让位）

`Container:Open` 只按**同 type** 互斥，不同 type 的面板会同时存在，位置完全由各自
`widget.pos` 决定——原版从来没排过队。做"第二个侧栏面板"要自己算：

- 侧栏有两个 root：`containerroot_side`（`issidewidget = true` 的原版背包）与
  `containerroot_side_behind`（`type = "side_inv_behind"`）。两者都是
  `ANCHOR_RIGHT + ANCHOR_MIDDLE`，**几何位置完全一致**，可当同一片区域排；
- 开箱时扫这两个 root 的 children，取最左面板的 `pos.x`，自己 = `最左 − 面板宽 − 间隙`；
- 面板宽度用 **pos 单位**（底图局部宽度 × 0.6），与分辨率/HUD 尺寸无关；
- **`Widget.children` 是以 widget 为键的 set**（`widgets/widget.lua:305` `self.children[child] = child`）：
  `ipairs(root.children)` 一个都取不到，必须 `pairs`（要数组语义用 `Widget:GetChildren()`）；
- **`posfn` 里拿不到 `self.container`**：`ContainerWidget:Open` 的顺序是
  `posfn(...)` → `SetPosition` → … → `self.container = container`
  （`containerwidget.lua:50` vs `:188`）。要按"已开了几个面板"精确排位，就在
  `ContainerWidget:Open` 外面包一层（只对自己 prefab 生效），`Open` 走完再 `SetPosition` 校正。

### 7.9 容器音效

- `skipopensnd / skipclosesnd = true` 是"容器没声音"的最常见原因；
- 默认顺序：`SKIN_SOUND_FX → widget.opensound → IsSideWidget() 的背包音 → 通用 HUD 容器音`；
- `IsSideWidget()` 就是 `container.issidewidget` → **为了布局把 `issidewidget` 设成 false 后
  背包音就没了**，要显式写 `widget.opensound / closesound`；
- 音效在**客户端**播（`container_replica.lua:506`），服务端那份 widget 表的修改到不了客户端 →
  音效写在**共享的 widget 表**里（`containers.params` 或 widgetsetup 里构造的那份）。

### 7.10 拦截"只允许某角色打开"的正确位置

```lua
-- components/container.lua:735：CanOpen() 无参，调用方都不传 doer，堵不住
function Container:CanOpen()
    return self.openlimit == nil or self.opencount < self.openlimit
end
```

唯一必要且足够的拦截点是 `Container:Open(doer)`：

```lua
local OldOpen = inst.components.container.Open
inst.components.container.Open = function(self, doer, ...)
    if doer ~= nil and doer.prefab ~= "wanda" then return end
    return OldOpen(self, doer, ...)
end
```

客户端"看不到开启提示"要在 `AddComponentAction` 里用 `doer.prefab` 判断
（`replica.container:CanBeOpened()` 是整实体 netvar，没有 doer 概念）。

### 7.11 别指望 `Widget:GetSize()`

`ContainerWidget` 不设 `self.w/h`，`Widget:GetSize()` 对它没用；面板尺寸只能从
`bganim` 的 `GetVisualBB()` 拿。

---

## 8. 状态、存档、网络同步与客户端持久化

### 8.1 netvar

```lua
inst._tiernet = net_byte(inst.GUID, "mymod.tier", "mymod.tierdirty")   -- 服务端 set，客户端 value()
inst._namenet = net_string(inst.GUID, "mymod.name")
```

客户端拿不到服务端普通字段，**必须走 netvar**；简单布尔状态用 tag 最省事。

### 8.2 状态放哪一层

物品自身状态 → 物品字段 + netvar；"跟着人的"状态 → 玩家字段，物品只做遥控器。
状态在玩家身上时要显式归零：

```lua
inst:ListenForEvent("onremove", function()
    owner._my_items[inst] = nil
    if next(owner._my_items) == nil then ResetState(owner) end
end)
```

（`onremove` 只在实体真被删除时触发，丢在地上不算。）

### 8.3 存档合并

`OnSave`/`OnLoad` 可能已被别人写过，**合并而不是覆盖**：

```lua
AddPlayerPostInit(function(inst)
    local OldSave = inst.OnSave
    inst.OnSave = function(_, data)
        data = OldSave ~= nil and OldSave(_, data) or data or {}
        data.mymod_tier = inst._mymod_tier
        return data
    end
    local OldLoad = inst.OnLoad
    inst.OnLoad = function(_, data)
        if OldLoad ~= nil then OldLoad(_, data) end
        if data ~= nil and data.mymod_tier ~= nil then inst._mymod_tier = data.mymod_tier end
    end
end)
```

- `AddPlayerPostInit` **只能在 modmain** 调用；
- **改档位表要处理旧存档**：老值可能越界，读盘后统一 `ClampTier`；
- `AddComponentPostInit("inventory")` 的 OnLoad **先于** `AddPlayerPostInit` 触发
  （组件数据恢复早于玩家初始化）。

### 8.4 序列化的两个事实

- **空字符串是真值**：`inventoryitem_classified` 的 net_string 同步完成前是 `""`，
  把 `atlas = ""` 缓存进去会让图标永远渲染成 fallback 方块 → 缓存前必须过滤
  `atlas ~= "" and image ~= ""`；
- **`json.decode` 的对象键全是字符串**：用数字槽位做键的表，恢复后要 `tonumber(slot)`；
- 实体上的定时器随实体/世界销毁，跨 shard 时 `DoTaskInTime` 的防抖可能永不触发 →
  关键写盘放在变更点即时执行，或挂 `playerdeactivated` 兜底。

### 8.5 客户端持久化

- API：`TheSim:SetPersistentString(name, str, false)` / `TheSim:GetPersistentString(name, cb)`（异步）；
- 落盘：`Documents\Klei\DoNotStarveTogether\<KleiID>\client_save\`；
- 范本：`scripts/playerhistory.lua`（脏标记 + json + SavePersistentString）；
- **异步读回前不要写盘**：`GetPersistentString` 回调前就 `SetPersistentString`，
  会用内存里的默认值覆盖磁盘上已存的状态（典型：进世界时 `Inventory.OnLoad` 先触发写盘，
  而开关/配置还没来得及读回）。做法：用 `persist_loaded_key` 一类门闩，读回后统一 Flush；
  跨 shard/换世界会重读同一个文件时，“正在读盘”期间也要禁止写；
- 用户可能在读回前操作 UI（如按开关）：记下“读盘发起时的状态”或“操作对应的文件名”，
  回调时不要用磁盘旧值覆盖用户刚做的操作；
- 客户端可用标识：`TheNet:GetServerName()`、`TheNet:GetUserID()`、`TheWorld:HasTag("cave")`；
  **`TheWorld.meta.session_identifier` 客户端拿不到**（meta 是 master-sim 组件）。

---

## 9. 客户端 / 服务端双模式与 shard

### 9.1 地表和洞穴是两个进程、两份存档

- 玩家跨 shard 走**迁移快照**；快照经对端 vanilla `OnSave/OnLoad` 转手后，
  组件数据里"不认识的键"会被**静默丢弃**（这就是"下洞穴丢配置"类 bug 的根因）；
- **client-only mod 不会在洞穴端进程运行**；自开世界的洞穴是独立 dedicated 进程，
  host 进洞穴后自己的客户端也退化成纯客户端；
- 跨 shard 的持久化要么走客户端 `SetPersistentString`，要么两端都装 mod。

### 9.2 客户端模式只有 replica

- `o.replica.inventory` / `o.replica.inventoryitem`（`fn.GetComponent` 的兜底）；
- **客户端无法凭空生成图标资源**：`GetAtlasAndImage` 只查缓存，spawn prefab 的路径被禁用。
  缓存来源必须覆盖：主物品栏（`EachItem`，**不含装备也不含背包**）、装备栏（`GetEquips()`）、
  overflow 容器（背包 `itemget` 事件 + 遍历）、玩家 `equip` 事件（跨 shard 后物品直接落装备槽）。
  **漏哪一路，哪一路就渲染成 `square.tex` 方块**（都踩过）；
- **`GetInventoryItemAtlas(imagename, true)` 纯客户端可调**（`simutil.lua` 全局函数）：
  按 `prefab .. ".tex"` 就能查到原版物品与已注册 atlas 的 mod 物品，物品不在身上也行；
  `no_fallback = true` 让查不到时返回 nil，而不是误拿 `images4.xml`；
- **replica `GetAtlas()` 的 images4 兜底是陷阱**：未注册 atlas 的 mod 物品会拿到
  `images/inventoryimages4.xml` 这个错误路径 —— atlas/image 都有值但 region 不存在，
  渲染成**空白**（不是方块）且引擎不重试；错误数据若进缓存还会冒充"真实来源"。
  任何来源的 atlas/image 写缓存前都要 `TheSim:AtlasContains(atlas, image)` 验证；
- **图标引用要落盘才能跨会话**：按名推断和入手都拿不到时，把入手时的那份 `atlas/image`
  写进 `SetPersistentString`，重启后加载并用 `AtlasContains` 校验（mod 卸载后资源未加载会
  返回 false，条目自动失效）；
- **缓存写入与按钮渲染要闭环**：缓存就绪时若按钮还是 fallback 方块，主动 kill 重画
  （精确记录哪些按钮是方块，别全量重画）；只靠"创建时安排几次延迟重试"会在物品晚到
  （在箱子里、classified 慢同步）时失效，方块永久常驻。

---

## 10. 调试

### 10.1 日志

- 客户端 `client_log.txt`（所有 `print` 带时间戳），服务端 `server_log.txt`；
- 同目录还有崩溃 dump（`donotstarvetogether_*.dmp`）与 caves 端日志；
- **进世界/重启会重置**，重要证据及时另存（验收报告里直接贴原文）。

### 10.2 控制台

```lua
c_give("goldnugget")
c_spawn("hound")
c_find("my_watch")
print(ThePlayer:HasTag("playerghost"), ThePlayer.components.health:IsDead())
```

中文输入法会吞 `` ` ``；自动化用 `tools/common/dstconsole.py`（PostMessage，不依赖焦点）。

### 10.3 临时自检模块

把断言写成 `scripts/<mod>_selftest.lua`（带 mod 前缀，`[T]` 前缀便于 grep），
控制台 `require("<mod>_selftest").Run()`。一次打印几十个状态，比截图可靠。
`require` 会缓存 → 改完先 `package.loaded["<mod>_selftest"] = nil`。

**验完必须删**，并 `grep -rn "TEMP\|\[T\]\|\[DBG\]\|print(" mods/<mod> --include=*.lua` 归零。

### 10.4 求证引擎行为

怀疑引擎行为时解包 `data/databundles/scripts.zip` 直接 grep（沙箱白名单、事件名、组件结构、
`containers.lua` 的 pos、`playerhud.lua` 的 type→root 映射都在里面），**不要凭记忆猜**。
本指南里的行号都来自这份源码。

### 10.5 Lua 语法校验

本机没有 lua/luac：`pip install luaparser`，然后

```python
import luaparser.ast as ast
ast.parse(open(path, encoding="utf-8").read())     # 抛异常即语法错误
```

### 10.6 插桩别用短锚点

`local targets = …` 这种行在多个函数里都有，替换错位置会引用不存在的变量 →
触发沙箱 `variable 'x' is not declared` 直接崩到崩溃报告器。
用函数签名行（`local function UpdateAura(player)`）这种唯一锚点。

---

## 11. 工具使用方法

工具按 mod 划分：**通用放 `tools/common/`，只服务单个 mod 的放 `tools/<mod>/`**。

```
tools/
├── common/                   跨 mod 通用
│   ├── uilook.py             屏幕模板匹配（存在性断言 / 定位）
│   ├── gameinput.py          带焦点校验的键鼠输入（Unicode）
│   ├── dstconsole.py         向控制台注入 Lua（PostMessage，不依赖焦点）
│   ├── dstlua.sh             执行到日志出现标记（无人值守验收）
│   └── ktex2png.py           KTEX 解码（校验图标/图集产物）
└── <mod>/                    单 mod 专用生成器
```

脚本内用 `HERE = 脚本目录`、`REPO = HERE/../..` 定位仓库；跨目录 import 走
`sys.path.insert(0, os.path.join(REPO, "tools", "common"))`。

### 11.1 `uilook.py`：屏幕模板匹配

纯 numpy + Pillow 的归一化互相关（FFT 加速），整屏 2560×1440 约 0.3 秒。

```bash
python tools/common/uilook.py shot shot.png
python tools/common/uilook.py crop shot.png 700,200,80,80 tpl.png
python tools/common/uilook.py find tpl.png --screen shot.png --threshold 0.9 --max 3
python tools/common/uilook.py find tpl.png --region 0,1300,2560,140 --scales 1.0,0.9,0.8
# -> {"ok":true,"matches":[{"x":700,"y":200,"w":80,"h":80,"cx":740,"cy":240,"score":1.0}]}
```

```python
from uilook import grab, crop, find_template
assert find_template("tpl_icon.png", screen=grab(), threshold=0.9), "图标没出现"
```

边界：对缩放敏感（换分辨率/UI 缩放要重截模板）；半透明动态背景易误命中，优先选 UI 面板/图标；
没有 OCR。

### 11.2 `gameinput.py`：带焦点校验的输入

发输入前必须 `GetForegroundWindow() == 目标 hwnd`，不一致就抛错，**绝不盲发**
（不校验的后果：按键被游戏当快捷键吃掉，弹出各种面板污染测试状态）。

```bash
python tools/common/gameinput.py list
python tools/common/gameinput.py focus "Don't Starve"
python tools/common/gameinput.py text 'c_give("goldnugget")' --app "Don't Starve"
python tools/common/gameinput.py key grave --app "Don't Starve"
python tools/common/gameinput.py hold w 800 --app "Don't Starve"
```

Unicode 走 `SendInput + KEYEVENTF_UNICODE`（`VkKeyScanW` 只能 ASCII）；窗口匹配同时比对**类名**
（中文系统标题是中文，命令行传参易被 GBK 破坏）。

### 11.3 `dstconsole.py` / `dstlua.sh`：控制台注入

```bash
python tools/common/dstconsole.py 'print("[T] hi")'
tools/common/dstlua.sh '[T] hi' 'print("[T] hi")'       # 反复试到日志出现标记
```

` ` ` 是 toggle → `dstlua.sh` 内置 4 次重试；控制台已开着用 `--no-toggle`；
字符逐字 `WM_CHAR`（12ms），**不需要窗口焦点、不受中文输入法影响**。

### 11.4 `ktex2png.py`

```bash
python tools/common/ktex2png.py <file.tex> out.png
```

用途：核对编译产物（图标真进 atlas 了吗、`anim/<x>.zip` 里的 `atlas-0.tex` 长什么样）。
DST 图集上下翻转，翻正后再比较（§4.4）。

### 11.5 组合用法

```python
from uilook import grab, find_template
from gameinput import send_command

send_command('c_give("wanda_haste_watch")', enter=True)
assert find_template("tpl_slot.png", screen=grab(), threshold=0.9), "物品没进背包"
```

顺序永远是**先断言存在，再看外观**（见 [测试指南](testing.md)）。

---

## 12. 报错速查表

| 报错 / 症状 | 含义 | 处理 |
|---|---|---|
| `attempt to call global 'next' (a nil value)` | modmain 沙箱缺标准库 | 顶部 `local next = GLOBAL.next`（§2.1） |
| `Error during game initialization!`（闪退） | modinfo 用了标准库/复杂逻辑 | modinfo 只留字面量（§2.2） |
| `variable 'X' is not declared` | 沙箱访问未声明全局 | mod API 裸写；游戏全局加 `GLOBAL.`（§2.3） |
| `attempt to index field 'RECIPEDESC'` | 用了废弃键名 | `STRINGS.RECIPE_DESC`（§2.8） |
| `Invalid resource handle for atlas '…'` | 图集没加载 | 补 `Asset("ATLAS"/"IMAGE")`，路径为 mod 相对（§3.1） |
| 图标空白但无报错 | `INV_IMAGE` / xml 元素名不符 / 图标名不在 images1~4 | 见 §3.1、§4.2 |
| 图标永远是方块（`square.tex`） | 客户端缓存缺来源 / 缓存了 `atlas=""` | 补齐四路来源；过滤空串（§8.4、§9.2） |
| 悬停有提示、点击无反应 | 动作被当 `previewaction` 丢弃 | `instant = true` 或 `AddStategraphActionHandler`（§6.2） |
| 右键在物品栏没反应 | 组件动作写了 `if not right then return end` | 改 `right == false`（§6.4） |
| 手持工具的动作不触发 | 注册在 `INVENTORY`/服务端独有组件 | 注册到 `USEITEM` + `inventoryitem`（§6.5） |
| 地面模型是一团乱块 | bank 缺 `PlayAnimation` 的动画名 | scml 补齐（§5.3） |
| 施法时手里看不到道具 | build 缺 `watchprop` 符号 | scml 的 object/timeline 命名 `watchprop`（§5.3） |
| 开一个容器把另一个顶掉 | `container.type` 相同 | 用自定义 type（§7.5） |
| 广播式关闭关不掉 | `Close` 拦截没做重入标记 | 加 `self._closing`（§7.4） |
| 面板跑到屏幕正中央 | 自定义 type → `containerroot` | 借原版 type（§7.6） |
| 换分辨率面板错位 | 用了中心锚 + 写死坐标 | 挂右侧锚点（§7.6） |
| 面板和背包重叠 / 不居中 | 没算相邻面板 | 扫 root children + `GetVisualBB`（§7.3、§7.8） |
| 容器没声音 | `skipopensnd` / `issidewidget=false` 丢了背包音 | 显式写 `opensound`（§7.9） |
| 玩家死亡掉落时崩服 | 关键路径调了 `debug.traceback` | 删掉（§2.7） |
| `Unable to find python!` | `scml.exe` 在 PATH 找不到 python | 从 bash 直接调用（§5.3） |
| 改了 png 图标没变 | autocompiler 按时间戳跳过 / 客户端缓存 | 先删 tex+xml 再编译；清 cache（§1.5、§4.1） |
| 改了 modinfo 默认值没生效 | `mod_config_data` 缓存 | Reset to Defaults 或删缓存文件（§1.3） |

---

## 13. 推荐目录结构

```
mods/<mod>/
├── modinfo.lua                 # 只有字面量（§2.2）
├── modmain.lua                 # 注册：PrefabFiles / Assets / 动作 / PostInit / 布局覆盖
├── scripts/
│   ├── <mod>_state.lua         # 唯一数据源（倍率、档位）
│   ├── <mod>_selftest.lua      # 临时自检（交付前删）
│   └── prefabs/
│       ├── my_item.lua
│       └── my_bag.lua
├── modicon.png / .tex / .xml   # Mods 列表图标（★ 根目录，不要放 images/）
├── images/
│   └── inventoryimages/        # png + tex + xml
└── anim/
    └── my_item.zip             # 自绘 build（scml 编译产物）
```

配套生成器放 `tools/<mod>/`（§11）；该 mod 的功能说明、开发/测试/发布文档放 `docs/mods/<mod>/`。
