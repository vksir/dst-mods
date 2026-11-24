# Wanda Planar Plan 旺达位面计划 · 测试指南

> 通用要求（报告位置、内嵌图片、只写验证过的结论、测试分层）见
> [`../common/testing.md`](../common/testing.md)。本文只列**这个 mod 特有的断言与回归项**。
> 验收报告：`D:\Code\MyBlog\笔记\开发\饥荒\Mod\旺达加强\v<N>\验收报告.md`。

## 1. 测前准备

```lua
-- 角色常是幽灵：走原版复活流程，别只改血量（会造成"活着但看着像幽灵"的分裂状态）
if ThePlayer:HasTag("playerghost") then ThePlayer:PushEvent("respawnfromghost", {}) end
ThePlayer.components.health:SetPercent(1)
ThePlayer:SetInvincible(true)
```

- **别改 `ThePlayer.prefab`**（会把 HUD 弄坏）；要换角色就换存档；
- **别批量 `e:Remove()`**（一次删几十个实体会崩服务器）：只删指定 prefab，加数量上限；
- 减速表开着时角色会"时间流逝"老死 → 变幽灵 → 物品栏隐藏，这是设计如此，不是 bug；
- 测布局前把「整合背包」设置摆到要测的那一档，进世界前确认。

## 2. 数值断言（最长用）

```lua
-- 九种档位组合的老化倍率（期望见 development.md §3）
local Age = require("wanda_planar_age")
local out = {}
for h = 0, Age.HASTE_TIER_COUNT - 1 do
  for s = 0, Age.SLOW_TIER_COUNT - 1 do
    Age.SetHasteTier(ThePlayer, h); Age.SetSlowTier(ThePlayer, s); Age.NotifyChanged(ThePlayer)
    out[#out+1] = h .. "+" .. s .. "=" .. string.format("%.2f", ThePlayer.components.oldager.rate)
  end
end
print("[T] " .. table.concat(out, " "))
-- 期望：00=1.00 01=1.30 02=1.50 10=1.30 11=1.60 12=1.80 20=1.50 21=1.80 22=2.00
```

| 断言 | 期望 |
|---|---|
| 档位总数 | `HASTE_TIER_COUNT == 3`、`SLOW_TIER_COUNT == 3` |
| 50%+50% | `rate == 2.00`（**加算**；相乘会得 2.25，能一眼区分） |
| 单开 50% | `1.50` |
| 物品名 | 0 档「加速表 / 减速表」；1 档「… 30%」；2 档「… 50%」 |
| 移速倍率 | 加速表开档后 `locomotor.externalspeedmultiplier == 1.3 / 1.5` |
| 光环范围 | 12 格内 `hostile` 生物 `externalspeedmultiplier == 0.7 / 0.5`；13 格外不受影响 |
| 旧档迁移 | 存档里 `_wanda_haste_tier = 4` → 读盘后钳到 2（50%） |
| 护盾 | 倒走表施法后 `WARP_SHIELD_FRAMES = 10` 内继续免伤 |

## 3. 面板布局断言（两种布局）

用 `GetVisualBB()` 算美术中心，**不要看 `pos.y`**（每套底图中心不同）：

```lua
-- 期望：钟表袋中轴线 == 相邻背包面板中轴线（误差 < 1 pos 单位）
local c = ThePlayer.HUD.controls
for _, root in pairs({ c.containerroot_side, c.containerroot_side_behind }) do
  if root ~= nil then
    for _, w in pairs(root.children or {}) do
      local bb = w.bganim
      if bb ~= nil then
        local _, y1, _, y2 = bb:GetVisualBB()
        print("[T] " .. tostring(w.panel_prefab or w.container and w.container.inst.prefab)
          .. " pos.y=" .. tostring(w.pos and w.pos.y)
          .. " center=" .. string.format("%.1f", (w.pos.y or 0) + (y1 + y2) * 0.5 * 0.6))
      end
    end
  end
end
```

| 场景 | 期望 |
|---|---|
| 分开布局 + 8 格背包（`-80`） | 两面板中轴线一致（实测 -80.3 / -80.6） |
| 分开布局 + 克劳斯袋（`-130`） | 一致（实测 -137.2 / -137.4）—— **改前这里差 45 pos** |
| 分开布局 + 猪皮包（`-90`）/ 香料包（`-70`） | 各自一致 |
| 分开布局并排 | 钟表袋在左、背包在右，**不重叠**，间隙 ≈ 6 pos |
| 连开两个钟表袋 | 依次向左排（-137 → -275 这一档） |
| 中途切「整合背包」再开袋 | 挂 `containerroot_side_behind`、位置 `(-5,-80)`，不压原版背包 |
| 融合布局 | 只在背包坑位显示（单人只看到一列），不回退到屏幕中央 |
| 同帧开背包 + 袋（邻居动画未停） | 袋回落基准 `-85`，不报错、不乱跳 |

截图要量到**中轴线**才说明问题（参考 v7 报告的四联图）。

## 4. 交互断言

| 项 | 怎么验 |
|---|---|
| 右键三态文案 | 悬停表看 tooltip：`激活` → `提升档位` → `停用`，档数 3 态 |
| 钟表袋右键 | `开启` / `关闭`；开启后走开不自动关；再右键才关；关袋不连带关背包 |
| 钟表袋 + 骑牛 | 开袋 → 上牛 → 右键仍是「关闭」且能关掉；骑牛时袋关着也能右键打开；下牛后照旧 |
| 加速/减速表 + 骑牛 | 骑牛时表没有右键动作（照抄原版施法限制），下牛后恢复；已开档位骑牛时仍生效 |
| 只允许旺达 | 换角色（或临时改 `doer.prefab` 判断）确认动作不出现 |
| 命名动作 | 羽毛笔拿手上 → 悬停溯源表 → 右键文案「命名」→ 弹出木牌输入框 → 名字变「溯源表-XXX」 |
| 钟表袋只收表 | 往袋里放非钟表物品应放不进 |
| 音效 | 开/关袋都有背包同款音效（融合布局也不能丢） |
| 地面外观 | 丢地上是自绘造型，不与溯源表/克劳斯背包混淆（截图 + `ktex2png` 回读） |

## 5. 历史回归清单（每轮都抽查）

这些都是修过的 bug，改任何相关代码后要重验：

```
[ ] 图标：物品栏 46px 能认出三件物品；地面造型不混淆（v3/v6）
[ ] 钟表袋面板：分开布局不压背包、融合发展布局在右侧坑位（v6）
[ ] 钟表袋关闭：走动不关；关袋不连带关背包（v3）；骑牛也能开关（v8）
[ ] 右键文案：关闭态显示「停用」而非「激活」（v4）
[ ] 命名：羽毛笔链路能出「命名」并成功写入名字（v5）
[ ] 音效：只有一次，不叠加护盾声（v4）
[ ] 数值：档位/文案/modinfo 三处一致（v4/v5/v7）
[ ] 档位共享：两块同类表交替右键，档位同步（v4）
[ ] 老化倍率：九宫格矩阵与期望一致（v7）
[ ] 反复施法 10 次后，玩家身上残留 FX ≤1（`FindEntities` 半径 3 带 FX tag）
[ ] 施法特效颜色：客户端预测的施法光圈是青绿（加速表）/ 紫（减速表），不是白色（`castfxcolour` 两端都设）
[ ] 减速表开着打一群怪再跑开：怪身上粒子消失、移速恢复，玩家附近不留 FX
```

## 6. 报告要点（本 mod 特有）

- 环境必须写清 **HUDSize 与分辨率**（布局结论依赖它们，实测 2560×1440 / HUDSize 7）；
- 布局类结论给**期望 vs 实测 vs 误差**表格，配中轴线截图；
- 数值类结论给**矩阵表**，别只写"正常"；
- 未验证项（右键文案逐档截图、敌速逐档实测、旧档迁移实测）要如实列出。
