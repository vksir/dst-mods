# Wanda Planar Plan 旺达位面计划 · 开发指南

> 仓库 `mods/wanda_planar_plan/`，`modinfo.version = 0.4.1`（内部按轮次记 v3~v7）。
> 通用写法（沙箱、Asset、动画管线、调试）见 [`../common/development.md`](../common/development.md)，
> 本文只写**这个 mod 特有**的设计决策、常量与踩过的战役。

## 1. 功能清单

| 功能 | 说明 | 引入 |
|---|---|---|
| 非位面攻防全额转化 | 旺达造成的伤害按非位面结算；受到的位面伤害按普通伤害结算 | v1 |
| 溯源表 / 裂缝表命名 | 手持羽毛笔 → 悬停表 → 右键「命名」→ 木牌式输入框 → 显示「溯源表-XXX」，全服可见 | v1（v5 修好） |
| 钟表袋 | 2×8 格，只收旺达的钟表；右键开关（添加燃料同款短动作）；移动不关、不连带关背包 | v3 |
| 加速表 | 三档（关 / 30% / 50%），同步加速移速与老化 | v4（v7 定档） |
| 减速表 | 三档（关 / 30% / 50%），自身老化加速 + 12 格内敌对生物减速 | v4（v7 定档） |
| 老化加速加算叠加 | `rate = 1 + 加速 + 减速`，50%+50% = 老化加快 100% | v7 |
| 倒走表护盾 | 施法起手即格挡（覆盖前摇），施放后追加骨头盔甲同款 10 帧免伤 | v3 |
| 第二次机会表 | 灵魂状态用它复活自身后不损毁 | v1 |
| 状态挂玩家 | 所有同类表共享档位；丢地上/放袋里照样生效 | v4 |

所有功能都能在「模组配置」单独开关（`modinfo.configuration_options` 8 项）。

## 2. 设计决策

1. **状态挂玩家，物品只做遥控器**
   档位存 `player._wanda_haste_tier / _wanda_slow_tier`（+ netvar 同步），
   物品只负责改值。好处：丢表/放袋/换表都不断效果；代价：最后一件移除要显式归零
   （`onremove` 里查注册表）。
2. **老化倍率只有一个出口**
   `scripts/wanda_planar_age.lua` 的 `RefreshOldAge()` 统一写 `oldager.rate`，
   任何功能都不自己改 rate。v7 起是**加算**：`rate = 1 + haste + slow`。
   旧档位（v4 的 100% / 60% 档）读盘后由 `ClampTier` 钳到当前档数。
3. **伤害转化在 `CalcDamage` 出口搬移**
   不改 `combat:GetAttacked` 的判定，只在最终数值上把位面/普通互相搬移，
   避免与其它 mod 的伤害修正在中间环节打架。
4. **受击侧包 `GetAttacked_Internal`**
   护盾与"受击绕表"逻辑都挂这里；**绝不**在这里用 `debug.traceback`（会崩服）。
5. **instance shadowing**
   同一 prefab 的多块表共存时，用实例字段覆盖方法，而不是改类方法（`prefabpostinit` 层面）。
6. **敌对判定加 `hostile` tag**
   减速光环必须同时满足 `_combat` 且有 `hostile`，否则会误减速中立生物/宠物。
7. **钟表袋只认自己发起的关闭**
   原版自动关闭路径很多，统一拦截带 `doer` 的 `Close`，只放行广播式 `Close()`；
   必须带**重入标记**（见 §5.5）。
8. **面板布局借原版 type**
   融合布局下必须用 `side_inv_behind` + `issidewidget = false`，不要自定义 type 再算 pos.x
   （`containerroot` 是中心锚，换分辨率会漂）。

## 3. 数值表（唯一来源 `scripts/wanda_planar_age.lua`）

```lua
Age.HASTE_TIERS = { 0, 0.30, 0.50 }   -- 关闭 / 30% / 50%
Age.SLOW_TIERS  = { 0, 0.30, 0.50 }   -- 关闭 / 30% / 50%
oldager.rate = 1 + haste + slow       -- 加算
```

| 项 | 30% 档 | 50% 档 |
|---|---|---|
| 加速表 → 移速 | ×1.30 | ×1.50 |
| 加速表 → 老化 | ×1.30 | ×1.50 |
| 减速表 → 自身老化 | ×1.30 | ×1.50 |
| 减速表 → 12 格内敌对生物移速 | ×0.70 | ×0.50 |

- 叠加：`50+50 → 2.00`（老化加快 100%）、`30+30 → 1.60`、单开 50% → `1.50`；
- 光环半径 `TUNING.BATTLESONG_ATTACH_RADIUS`（12 格，同薇格弗德战歌），
  1 秒 `DoPeriodicTask` 刷新，带 `slingshotammo_slow_debuff_fx` 同款粒子；
- 倒走表护盾 `WARP_SHIELD_FRAMES = 10`（与 `prefabs/armor_skeleton.lua` 一致）；
- 骑乘时加速表**只生效老化**，不加移速；
- 配方：加速表 = 时间碎片×2 + 金块×2 + 海象牙×1；减速表 = 时间碎片×2 + 噩梦燃料×4 + 紫宝石×1；
  钟表袋 = 时间碎片×2 + 猪皮×4 + 蜘蛛丝×4（`builder_tag = "clockmaker"`）。

**改数值时同步**：`modinfo.lua` 的 `description` + 两条 `hover`、物品显示名、
右键文案档位数（`#TIERS`）、`docs/mods/wanda_planar_plan/publishing.md` 的介绍页正文。

## 4. 代码结构

```
mods/wanda_planar_plan/
├── modinfo.lua                 # 8 个开关 + 文案（只有字面量）
├── modmain.lua                 # 注册、动作、伤害转化、钟表袋布局覆盖（~1100 行）
├── scripts/
│   ├── wanda_planar_age.lua    # ★ 唯一数据源：档位、老化合成、netvar、NotifyChanged
│   └── prefabs/
│       ├── wanda_haste_watch.lua   # 档位、移速、右键三态文案
│       ├── wanda_slow_watch.lua    # 档位 + 光环（FindEntities + locomotor 外部倍率）
│       └── wanda_watch_bag.lua     # 容器、只认自己发起的关闭、只允许旺达打开
├── images/inventoryimages/     # 三张图标 png + tex + xml
└── anim/                       # 三个 .zip（自绘 anim build）
```

`modinfo` 的 8 个开关：`clock_to_planar`、`planar_to_normal`、`nameable_watches`、
`keep_revive_watch`、`warp_shield`、`haste_watch`、`slow_watch`、`watch_bag`。

## 5. 钟表袋：容器与面板（最折腾的部分）

### 5.1 两种布局

| 布局 | 做法 | 位置 |
|---|---|---|
| 分开（`Profile:GetIntegratedBackpack() == false`） | 自定义 `type = "wanda_watch_bag"` + `issidewidget = true` | 原版背包左侧，`(-137,-85)` 起算 |
| 融合（整合背包） | 借原版 `type = "side_inv_behind"` + `issidewidget = false` | 背包坑位 `(-5,-80)` |

- 分开布局**不能**用 `"pack"` / `"chest"`：`Container:Open` 会按同 type 互斥，把背包顶掉；
- 融合布局必须借原版 type：自定义 type 会挂到 `containerroot`（屏幕正中），调 pos.x 换分辨率就漂；
  `side_inv_behind` 的 root（`widgets/controls.lua:279`）是右锚 + 垂直居中 + 比例缩放，分辨率无关。
- 已知副作用：`side_inv_behind` 也是韦伯胡子袋用的 type，但两者不会共存。

### 5.2 常量（实测标定 2560×1440 / HUDSize 7）

| 常量 | 值 | 用途 |
|---|---|---|
| `BAG_POS_SIDE` | `(-137, -85)` | 分开布局基准（无相邻面板时） |
| `BAG_POS_INTEGRATED` | `(-5, -80)` | 融合布局 |
| `BAG_PANEL_W_POS` | `129` | 面板宽（pos 单位）= 底图 215 局部单位 × 0.6 |
| `BAG_PANEL_GAP_POS` | `6` | 与左侧邻居的间隙 |
| `CONTAINER_WIDGET_SCALE` | `0.6` | `ContainerWidget:SetScale(.6)`，局部↔pos 换算 |
| `BAG_ART_CENTER_LOCAL` | `-11.5` | 本袋底图 `ui_krampusbag_2x8` 的包围盒中心 |

标定：1 pos ≈ 1.64px、1 局部单位 ≈ 0.98px（比值 0.6）；1 底图局部宽度 215。

### 5.3 位置算法

```lua
-- 横向：贴到同区域最左面板的左侧
pos.x = 最左面板.pos.x - BAG_PANEL_W_POS - BAG_PANEL_GAP_POS
-- 纵向：跟相邻面板的美术中心对齐（每套底图中心不同，不能写死）
y = neighbor.pos.y + (neighbor_center - BAG_ART_CENTER_LOCAL) * 0.6
```

- `neighbor_center = (y1+y2)*0.5`，来自 `bganim:GetVisualBB()`；
  包围盒高度 `< 200` 说明面板还在"弹出"动画里 → 本次跳过（回落基准位）；
- 原版各容器的 `pos.y`：`backpack -80` / `spicepack -70` / `piggyback -90` / `krampus_sack -130`；
- 两个侧栏 root（`containerroot_side` 与 `containerroot_side_behind`）几何一致，可当同一片区域排；
- 遍历 children 必须 `pairs`（`Widget.children` 是 set）。

### 5.4 时机

- `containers.widgetsetup` 里挂 `posfn` 给基准位置（原生钩子，`SetPosition` 前调用）；
- `ContainerWidget:Open` 外面包一层，`Open` 走完再 `SetPosition` 校正
  （`posfn` 阶段 `widget.container` 还没赋值）；
- 包一层 `PlayerHud:OpenContainer`，开箱前按当前设置重算 `side / issidewidget / type`
  （`Profile` 是客户端专属，服务端永远算"分开布局"）；
- 客户端 `containers.widgetsetup` 是 `prefab = nil` 调的 → 必须写
  `containers.params.wanda_watch_bag`，否则客户端 widget 为 nil 崩。

### 5.5 关闭行为

```lua
local OldClose = inst.components.container.Close
inst.components.container.Close = function(self, doer, ...)
    if doer ~= nil and not self._closing then return end   -- 忽略原版自动关闭
    self._closing = true
    local r = OldClose(self, doer, ...)
    self._closing = nil
    return r
end
```

`Close(nil)` 与 `Close(doer)` 是同一个函数，传 nil 时会递归关闭各 opener——
没有重入标记的话，广播式关闭会被自己的闸挡住（`opencount` 永远是 1）。

"只允许旺达打开"的拦截点是 `Container:Open(doer)`（`CanOpen()` 无参，堵不住）；
客户端看不到开启提示要在 `AddComponentAction` 里用 `doer.prefab` 判断。

### 5.6 音效

`issidewidget = false`（融合布局）会丢背包音 → 显式写 `opensound` / `closesound`
（用背包的开关音效），写在**共享 widget 表**里（客户端播，`container_replica.lua:506`）。

## 6. 动作与文案

### 6.1 右键三态文案

`Action.stroverridefn` 按当前档位返回 `激活 / 提升档位 / 停用`，
档位数由 `#HASTE_TIERS - 1` 驱动（v7 起两档 → 三态）；返回 `nil` 回落原版文案。
不要改全局 `STRINGS.ACTIONS.X`。

### 6.2 命名动作（羽毛笔 → 表）

注册在 **`USEITEM` + `inventoryitem`**：

```lua
AddComponentAction("USEITEM", "inventoryitem", function(inst, doer, target, actions, right)
    if inst.prefab ~= "featherpencil" then return end
    if not IsNameableWatch(target) then return end
    table.insert(actions, ACTIONS.WRITE)
end)
```

- 注册在目标的 `INVENTORY` 收集器在这条路径上不会被调用；
- 组件名必须是客户端存在的（`writeable` 只有服务端组件 → 用它永不触发）；
- 动作要 `instant = true` 或注册 `AddStategraphActionHandler`（`wilson` + `wilson_client`），
  否则悬停有提示、点击无效；
- 木牌式输入框走 `writeables.AddLayout` + `writeable`/`named` 组件，
  显示名用 `displaynamefn`，格式「溯源表-%s」。

### 6.3 钟表袋右键

`开启 / 关闭` 两态，同样用 `stroverridefn`；自定义 action 必须同时注册状态机 handler
（用了"添加燃料"同款的短动作，所以不是 instant）。

## 7. 资源与工具

```bash
# 图标（64×64 → tex/xml）
python tools/wanda_planar_plan/gen_wanda_icons.py
rm -f mods/wanda_planar_plan/images/inventoryimages/wanda_*.{tex,xml}
"D:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/autocompiler.exe" \
  "D:/Code/MyMods/dst-mods/mods/wanda_planar_plan"

# 地面造型（128×128 → scml → anim.zip）
python tools/wanda_planar_plan/gen_item_build.py --no-compile
scml.exe <生成目录>/build.scml <生成目录>        # 从 bash 直调，别走 subprocess

# 校验产物
python tools/common/ktex2png.py mods/wanda_planar_plan/images/inventoryimages/wanda_haste_watch.tex out.png
```

- **46px 现实**：物品栏槽位只有 46px，只留「正圆 + 平涂 + 实心块」；
  表链/齿轮/月牙暗部只画在 128px 地面精灵里（v6 定案）；
- 三张图标同一套几何（表盘圆心 `cx=31.6, cy=34.4, R=20.4`），
  单针 = 加速、双箭头 = 减速、沙漏 = 钟表袋；
- 地面/手持是独立 build（不是原版贴图 + 染色），`idle/idle_loop/anim/cooldown_*/swap`
  全生成，符号名 `watchprop`；
- 详细命令与设计约束见 [`tools/wanda_planar_plan/README.md`](../../../tools/wanda_planar_plan/README.md)。

## 8. 特效（fx prefab）约定

用原版 fx 表里生成的 prefab（`SpawnPrefab("shadow_shield3")` /
`slingshotammo_slow_debuff_fx`）时，引擎那边的三个特性决定了本 mod 的写法：

| 特性（`prefabs/fx.lua`） | 后果 | 本 mod 的做法 |
|---|---|---|
| 代理实体 `SetCanSleep(false)`，只有 `animover` 才自毁 | 动画事件不来就常驻 | 自己管生命周期：光环特效 `KillFX`，目标离开/死亡/下线都要清（`ReleaseAll`） |
| 本地特效实体是 `Transform:SetFromProxy` 定位，独立于代理 | 代理移除不会带走本地特效 | 同上，别只依赖代理自毁 |
| 特效颜色/等级由**道具字段 + 方法**提供（如 `castfxcolour`、`SetFXLevel`） | 字段只在服务端设置时，客户端预测的特效拿不到 | `castfxcolour` 写在 `common_postinit`（两端都有）；等级走网络/实例字段 |

通用机制（沙箱、Asset、anim 管线等）见 [`../common/development.md`](../common/development.md)。

## 9. 已知行为 / 限制

- 减速表光环只作用于 `_combat` + `hostile` 的生物，中立/宠物不受影响；
- 加速表骑乘时不加移速（只加老化）；
- 钟表袋在融合布局下占用背包坑位：同时打开背包会看到两者重叠由原版保证互斥
  （同 type），不会同时显示；
- 旧存档的档位越界值会被钳位（v4 的 100% 档 → v7 的 50% 档），不报错；
- 所有表共享一人份状态：换表/丢表不叠加（避免"多块加速表叠乘"）。
