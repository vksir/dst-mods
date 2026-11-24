-- Wanda Planar Plan 旺达位面计划
--
-- 本文件同时运行在服务端与客户端（modinfo: all_clients_require_mod = true）。
-- 需要世界内实体/组件的逻辑一律先判断 TheWorld.ismastersim；纯界面/动作注册放在客户端也可执行的位置。
--
-- 引擎依据（data/databundles/scripts.zip）：
--   components/combat.lua:871  Combat:CalcDamage —— 普通伤害吃全部倍率（含旺达年龄倍率
--     customdamagemultfn，prefabs/wanda.lua:271），spdamage 只吃 damagetypebonus/PvP 系数。
--     因此"告警表伤害转位面"必须在 CalcDamage 出口处搬移，不能给武器挂 planardamage 组件
--     （那样伤害不再随年龄变化）。
--   components/combat.lua:574  Combat:GetAttacked_Internal —— 护甲吸收（inventory:ApplyDamage）
--     只作用于普通伤害；且 DoAttack/DoAreaAttack 直调 Internal（combat.lua:1218/1332/1339），
--     所以受击侧必须 wrap GetAttacked_Internal，wrap 公开的 GetAttacked 会漏近战与 AOE。
--   components/container.lua:1059 Container:OnUpdate —— portablestorage 容器在物品栏打开时，
--     玩家不在 keep_pocket_rummage 状态就自动关闭（需求 3 的钟表袋覆盖这段以做到"走动不关"，
--     同时用 ondropped 监听补回"丢出即关"）。
--   prefabs/kitcoon_nametag.lua —— 物品可命名的官方范本：writeables.AddLayout + writeable 组件。
--   components/named.lua + named_replica.lua —— 官方"名字同步到客户端"的组件（net_string），
--     命名后的物品名（溯源表-XXX）靠它两端一致。
--   prefabs/armor_skeleton.lua —— 骨头盔甲护盾：格挡后 10 帧内继续免伤（SHIELD_DURATION）。
--   stategraphs/SGwilson.lua:1041  ActionHandler(ACTIONS.ADDFUEL, "doshortaction") ——
--     钟表袋开关照抄这个短动作；:1336 CAST_POCKETWATCH 的 handler 目标 "pocketwatch_cast" ——
--     加速表 / 减速表开关复用同一段施法动画。
--
-- 沙箱注意（docs/dst-modding-pitfalls.md §1）：modmain 环境没有 next，须从 GLOBAL 显式导入。

local next = GLOBAL.next
local Vector3 = GLOBAL.Vector3

-- 注意：TheWorld / SpawnPrefab / GetTime 等在世界创建后才可用，
-- 不能在 modmain 加载阶段缓存为 upvalue（会得到 nil），一律运行时从 GLOBAL 取。
local function IsMasterSim()
    return GLOBAL.TheWorld ~= nil and GLOBAL.TheWorld.ismastersim
end

local ENABLE_CLOCK_TO_PLANAR = GetModConfigData("clock_to_planar")
local ENABLE_PLANAR_TO_NORMAL = GetModConfigData("planar_to_normal")
local ENABLE_NAMEABLE_WATCHES = GetModConfigData("nameable_watches")
local ENABLE_KEEP_REVIVE_WATCH = GetModConfigData("keep_revive_watch")
local ENABLE_WARP_SHIELD = GetModConfigData("warp_shield")
local ENABLE_HASTE_WATCH = GetModConfigData("haste_watch")
local ENABLE_SLOW_WATCH = GetModConfigData("slow_watch")
local ENABLE_WATCH_BAG = GetModConfigData("watch_bag")

--------------------------------------------------------------------------
-- 自定义 prefab 加载
--------------------------------------------------------------------------

PrefabFiles = {}
if ENABLE_HASTE_WATCH then
    table.insert(PrefabFiles, "wanda_haste_watch")
end
if ENABLE_SLOW_WATCH then
    table.insert(PrefabFiles, "wanda_slow_watch")
end
if ENABLE_WATCH_BAG then
    table.insert(PrefabFiles, "wanda_watch_bag")
end

local POCKETWATCH_WEAPON = "pocketwatch_weapon" -- 告警表
local POCKETWATCH_WARP = "pocketwatch_warp"     -- 倒走表

--------------------------------------------------------------------------
-- 玩家级档位状态：由 modmain 挂 EnsurePlayer（scripts/wanda_planar_age.lua 导出）
--
-- 为什么必须由 modmain 挂：scripts/ 下的 prefab 文件是以 _G 环境加载的
-- （mods.lua:646 直接引用全局 LoadPrefabFile），拿不到 AddPlayerPostInit 这类
-- modmain 注入的接口，那边只能做"首次接触表时懒挂钩"。出生时就挂上可以根治
-- "退档时所有表都在箱子/地上 → 重进后档位回落"的边角（需求 5）。
-- EnsurePlayer 幂等（内部 _wanda_planar_state_init 标记 + 合并 OnSave/OnLoad），
-- 和懒挂钩重复调用无副作用。
--
-- 模块延后到运行时 require：它跑在 _G 里（没有 GLOBAL 代理），且只该在游戏内被调用。
--------------------------------------------------------------------------

local AgeModule = nil
local function GetAge()
    if AgeModule == nil then
        local ok, mod = GLOBAL.pcall(GLOBAL.require, "wanda_planar_age")
        AgeModule = (ok and type(mod) == "table") and mod or false
    end
    return AgeModule or nil
end

if ENABLE_HASTE_WATCH or ENABLE_SLOW_WATCH then
    AddPlayerPostInit(function(inst)
        -- 客户端也会跑这个 postinit：只有主模拟端才有真正的玩家状态与 oldager
        if not IsMasterSim() then
            return
        end
        local age = GetAge()
        if age ~= nil and age.EnsurePlayer ~= nil then
            age.EnsurePlayer(inst)
        end
    end)
end

local WANDA_HASTE_WATCH = "wanda_haste_watch"
local WANDA_SLOW_WATCH = "wanda_slow_watch"
local WANDA_WATCH_BAG = "wanda_watch_bag"
-- 加速表/减速表的"已激活"tag：由 scripts/prefabs/wanda_*_watch.lua 在档位变化时同步
-- （实体 tag 会同步到客户端，见原版 pocketwatch_inactive 的用法），右键文案读它
local WANDA_WATCH_ON_TAG = "wanda_watch_on"

-- 与 prefabs/armor_skeleton.lua 的 SHIELD_DURATION 一致（10 帧）
local WARP_SHIELD_FRAMES = 10

local function WarpShieldDuration()
    return WARP_SHIELD_FRAMES * GLOBAL.FRAMES
end

local function IsAlarmingClock(weapon)
    return weapon ~= nil and weapon.prefab == POCKETWATCH_WEAPON
end

-- 普通伤害 -> 位面：在 CalcDamage 全部倍率计算完成后整体搬移
local function MoveDamageToPlanar(damage, spdamage)
    if damage == nil or damage <= 0 then
        return damage, spdamage
    end
    spdamage = spdamage or {}
    spdamage.planar = (spdamage.planar or 0) + damage
    return 0, spdamage
end

-- 位面 -> 普通：受击入口处搬回，护甲吸收/耐久损耗走普通伤害路径
local function MovePlanarToDamage(damage, spdamage)
    if spdamage == nil or (spdamage.planar or 0) <= 0 then
        return damage, spdamage
    end
    damage = (damage or 0) + spdamage.planar
    spdamage.planar = nil
    if next(spdamage) == nil then
        spdamage = nil
    end
    return damage, spdamage
end

--------------------------------------------------------------------------
-- 需求 2：倒走表"响两次"（施法声 + 护盾声）→ 去掉护盾那一声
--
-- 护盾沿用骨头盔甲同款特效 shadow_shield3（scripts/fx.lua:4070），它的定义里带
-- sound = "dontstarve/creatures/together/stalker/shield"，和施法声
-- （wanda2/characters/wanda/watch/warp，SGwilson.lua:20568）叠在一起就是"响两次"。
--
-- 对生成出来的实体 KillAllSounds 没用：原版 fx 的构造函数（prefabs/fx.lua:8~60）
-- 晚一帧才把 t.sound 交给 SoundEmitter，那一刻没有正在播的声音可杀。
-- 但 fx 每次生成都会**重新从 fx 表条目里读** bank/build/anim/sound
-- （prefabs/fx.lua:168 只按条目建 prefab，不复制字段），所以改一个原版**从未使用**的条目，
-- 就能得到"长着骨甲护盾外观、完全没有声音"的特效，而 shadow_shield3 本身不动
-- （骨头盔甲自己的格挡声照旧）。
--
-- 选中的 ghostlyelixir_player_shadow_fx：scripts/fx.lua:1376 注明 "This is unused"，
-- 全脚本除定义外零引用（已 grep 确认）。
--------------------------------------------------------------------------

local SHIELD_FX = "shadow_shield3" -- 兜底：原版若改了这个空壳条目就退回原版特效（会带回声音）

if ENABLE_WARP_SHIELD then
    -- 骨甲护盾的图（bank/build 都是 stalker_shield）挂在原版 fx prefab 的资源里，
    -- 我们改的条目原本只声明 player_vial_fx，所以要自己把图声明进 mod 资源。
    Assets = {
        Asset("ANIM", "anim/stalker_shield.zip"),
    }

    local ok, fxdefs = GLOBAL.pcall(GLOBAL.require, "fx")
    if ok and type(fxdefs) == "table" then
        for _, def in ipairs(fxdefs) do
            -- 只认原版那个"未使用"的空壳定义；字段对不上就什么都不改
            if def.name == "ghostlyelixir_player_shadow_fx"
                and def.bank == "player_vial_fx"
                and def.anim == "buff_shadow"
                and def.sound == nil then
                def.bank = "stalker_shield"
                def.build = "stalker_shield"
                -- idle3 = 原版 shadow_shield3 的动画（fx.lua:4070，j=0 时 anim = "idle"..i）
                def.anim = "idle3"
                def.fn = function(inst)
                    inst.AnimState:SetFinalOffset(2) -- 同原版 shadow_shield*（fx.lua 的 FinalOffset2）
                end
                SHIELD_FX = def.name
                break
            end
        end
    end
end

--------------------------------------------------------------------------
-- 需求 7：倒走表护盾（骨头盔甲同款：shadow_shield 特效 + 短时间完全免伤）
--------------------------------------------------------------------------

local function GrantWarpShield(doer, skipfx)
    if doer == nil or not doer:IsValid() or doer.components.health == nil then
        return
    end

    doer._wandaplanar_shield_until = GLOBAL.GetTime() + WarpShieldDuration()

    if not skipfx then
        -- 外观同骨头盔甲的主护盾特效 shadow_shield3，但静音（见上面"需求 2"）
        local fx = GLOBAL.SpawnPrefab(SHIELD_FX)
        if fx ~= nil and fx:IsValid() then
            fx.entity:SetParent(doer.entity)
        end
    end
end

-- 护盾生效条件：
--   1. 前摇状态标记（整段 pocketwatch_warpback_pre，由状态机 onenter/onexit 维护）；
--   2. 或定时窗口（DoCastSpell 成功后的 10 帧，对齐骨头盔甲 SHIELD_DURATION）。
-- 前摇是一段完整施法动画（>10 帧），只靠定时窗口会在中后段裸奔，所以前摇用状态标记精确覆盖。
local function IsWarpShieldActive(inst)
    return inst._wandaplanar_precast_shield
        or (inst._wandaplanar_shield_until ~= nil and GLOBAL.GetTime() < inst._wandaplanar_shield_until)
end

--------------------------------------------------------------------------
-- 需求 1 + 7：旺达的出招转化 / 受击转化 / 护盾
--------------------------------------------------------------------------

AddPrefabPostInit("wanda", function(inst)
    -- 战斗只发生在 master sim；客户端（含 host 进世界后退化的纯客户端）没有 combat 组件
    if not IsMasterSim() or inst.components.combat == nil then
        return
    end

    if ENABLE_CLOCK_TO_PLANAR then
        local OldCalcDamage = inst.components.combat.CalcDamage
        inst.components.combat.CalcDamage = function(self, target, weapon, multiplier)
            local damage, spdamage = OldCalcDamage(self, target, weapon, multiplier)
            if IsAlarmingClock(weapon) then
                damage, spdamage = MoveDamageToPlanar(damage, spdamage)
            end
            return damage, spdamage
        end
    end

    if ENABLE_PLANAR_TO_NORMAL or ENABLE_WARP_SHIELD then
        local OldGetAttackedInternal = inst.components.combat.GetAttacked_Internal
        inst.components.combat.GetAttacked_Internal = function(
                self, attacker, damage, weapon, stimuli, spdamage, from_doattack)
            if ENABLE_WARP_SHIELD and IsWarpShieldActive(inst) then
                -- 护盾期内完全免伤：伤害归零后由原函数走 blocked 分支
                damage, spdamage = 0, nil
            elseif ENABLE_PLANAR_TO_NORMAL then
                damage, spdamage = MovePlanarToDamage(damage, spdamage)
            end
            return OldGetAttackedInternal(self, attacker, damage, weapon, stimuli, spdamage, from_doattack)
        end
    end

    print("[wanda_planar_plan] wanda hooks: clock_to_planar=" .. tostring(ENABLE_CLOCK_TO_PLANAR)
        .. ", planar_to_normal=" .. tostring(ENABLE_PLANAR_TO_NORMAL)
        .. ", warp_shield=" .. tostring(ENABLE_WARP_SHIELD))
end)

if ENABLE_WARP_SHIELD then
    AddPrefabPostInit(POCKETWATCH_WARP, function(inst)
        if not IsMasterSim() or inst.components.pocketwatch == nil then
            return
        end
        local DoCastSpell = inst.components.pocketwatch.DoCastSpell
        if DoCastSpell == nil then
            return
        end
        -- 注意：pocketwatch:CastSpell 是函数式调用，首个参数是表自身实体
        inst.components.pocketwatch.DoCastSpell = function(watch_inst, doer, target, pos)
            local success = DoCastSpell(watch_inst, doer, target, pos)
            if success then
                -- 前摇入口已经发过特效，这里只刷新定时窗口（对齐骨头盔甲的 10 帧），不重复放特效
                GrantWarpShield(doer, true)
            end
            return success
        end
    end)

    -- 需求 7（方案 A）：护盾提前到施法起手
    --
    -- 原版的施法时序（stategraphs/SGwilson.lua:20551）：
    --   ACTIONS.CAST_POCKETWATCH 进入 "pocketwatch_warpback_pre" → 播放 pocketwatch_warp_pre →
    --   animover 时才 PerformBufferedAction()（actions.lua:3146 → PocketWatch:CastSpell → DoCastSpell），
    --   即 DoCastSpell 里发的护盾要等到前摇播完才生效；而前摇本身没有无敌帧
    --   （原版的无敌帧在 "pocketwatch_warpback" 第 4 帧才 SetInvincible，SGwilson.lua:20614）。
    -- 所以在状态机入口处就把护盾挂上，让前摇整段都有免伤；DoCastSpell 的那次授予保留作为兜底。
    AddStategraphPostInit("wilson", function(sg)
        local state = sg.states ~= nil and sg.states.pocketwatch_warpback_pre or nil
        if state == nil or state.onenter == nil or state._wandaplanar_wrapped then
            return
        end
        local OldOnEnter = state.onenter
        local OldOnExit = state.onexit

        state.onenter = function(inst, ...)
            -- 只有主模拟端需要护盾（GetAttacked_Internal 的判定在服务端），
            -- 客户端也会跑状态机（预测），不能在那里 SpawnPrefab
            if IsMasterSim() then
                -- 用状态标记（而不是 10 帧定时窗口）覆盖整段前摇：
                -- pocketwatch_warp_pre 是一段完整施法动画，比 10 帧长得多。
                inst._wandaplanar_precast_shield = true
                GrantWarpShield(inst)
            end
            return OldOnEnter(inst, ...)
        end

        state.onexit = function(inst, ...)
            if IsMasterSim() then
                -- 离开前摇就撤标记（进 pocketwatch_warpback 后原版自己会 SetInvincible）
                inst._wandaplanar_precast_shield = nil
            end
            if OldOnExit ~= nil then
                return OldOnExit(inst, ...)
            end
        end

        state._wandaplanar_wrapped = true
    end)
end

--------------------------------------------------------------------------
-- 需求 4：第二次机会表自复活后不损毁
--------------------------------------------------------------------------

if ENABLE_KEEP_REVIVE_WATCH then
    AddPrefabPostInit("pocketwatch_revive", function(inst)
        if not IsMasterSim() or inst.components.hauntable == nil then
            return
        end
        local hauntable = inst.components.hauntable
        if hauntable.onhaunt == nil then
            return
        end

        hauntable.onhaunt = function(haunt_inst, haunter)
            -- 复刻原版 Revive_OnHaunt（prefabs/pocketwatch.lua），
            -- 唯一区别：旺达用表复活自己成功后保留表，不做 DropLoot + brokentool + Remove
            hauntable.hauntvalue = GLOBAL.TUNING.HAUNT_SMALL
            if haunter:HasTag("pocketwatchcaster")
                and haunt_inst.components.pocketwatch:CastSpell(haunter, haunter) then
                return true
            end
            GLOBAL.Launch(haunt_inst, haunter, GLOBAL.TUNING.LAUNCH_SPEED_SMALL)
            return nil
        end
    end)
end

--------------------------------------------------------------------------
-- 需求 3 + 4：钟表袋的容器面板（两端都需要，客户端 replica 靠它拿布局）
--
-- 原版 scripts/containers.lua 的 params 是模块内 local 表，自定义 prefab 查不到，
-- 因此这里既写 containers.params，又包裹导出的 containers.widgetsetup。
--------------------------------------------------------------------------

if ENABLE_WATCH_BAG then
    local containers = GLOBAL.require("containers")
    local OldWidgetSetup = containers.widgetsetup

    -- 需求 4：面板位置跟随原版「背包布局」设置项
    --   融合背包 = Profile:GetIntegratedBackpack()（playerprofile.lua:1308；选项界面
    --   screens/redux/optionsscreen.lua:431）；手柄模式也按融合处理
    --   （screens/playerhud.lua:391，TheInput:ControllerAttached()）。
    -- Profile 纯客户端可用；主机端可能没有 TheInput（也没有 Profile），一律兜 nil。
    local function IsIntegratedBackpackLayout()
        local profile = GLOBAL.Profile
        if profile ~= nil and profile.GetIntegratedBackpack ~= nil
            and profile:GetIntegratedBackpack() then
            return true
        end
        local input = GLOBAL.TheInput
        return input ~= nil and input.ControllerAttached ~= nil and input:ControllerAttached() == true
    end

    -- 复用原版 ui_krampusbag_2x8 面板（2 列 x 8 行 = 16 格）。
    -- 该底图按 7 行绘制（krampus_sack 只用 14 格），但格子背景是程序化绘制的 inv_slot.tex
    -- （widgets/containerwidget.lua:139），不受底图限制：行距 75→66、格子缩放 0.86 后
    -- 16 格实测全部落在边框内（见 v4 截图 06-钟表袋面板.png）。
    local BAG_COL_X = { -162, -87 } -- 沿用原版 containers.lua 的两列（backpack/krampus_sack 同款）
    local BAG_ROW_Y0 = 240          -- 首行高度，同 params.krampus_sack（containers.lua:1077）
    local BAG_ROW_DY = 66           -- 75 压到 66 才能把 8 行 16 格塞进 7 行高的底图
    local BAG_SLOT_SCALE = 0.86

    -- 面板底图在「pos 单位」下的宽度：底图 215 局部单位 × ContainerWidget 的 0.6 缩放
    -- （widgets/containerwidget.lua:11 的 SetScale(0.6)）≈ 129。pos 同样是 root 局部坐标，
    -- 所以这两个量同一把尺子，可以直接相减——与分辨率、HUD 尺寸全都无关。
    local BAG_PANEL_W_POS = 129
    local BAG_PANEL_GAP_POS = 6

    -- 两套布局的基准 pos（必须在 BagPanelPosFn 之前声明，否则闭包抓不到这两个 local）
    local BAG_POS_SIDE = Vector3(-137, -85, 0)
    local BAG_POS_INTEGRATED = Vector3(-5, -80, 0)

    -- ContainerWidget 自己的缩放（widgets/containerwidget.lua:11 SetScale(.6)）：
    -- 面板美术的包围盒是「ContainerWidget 局部单位」，乘这个值才是 root 的 pos 单位。
    local CONTAINER_WIDGET_SCALE = 0.6

    -- 本袋面板（ui_krampusbag_2x8）美术中心相对 widget 原点的局部 y。实测包围盒
    -- y ∈ [-287, 264] → 中心 -11.5。本袋美术是固定的，所以用常量：
    -- 刚开箱那一刻面板还在"弹出"动画里，GetVisualBB 只有 40 多单位高，采不到真实值。
    local BAG_ART_CENTER_LOCAL = -11.5

    -- 相邻面板的美术中心（局部 y）。只有在包围盒足够高（动画已停）时才可信。
    local function NeighborArtCenterY(widget)
        local bganim = widget ~= nil and widget.bganim or nil
        if bganim == nil or bganim.GetVisualBB == nil then
            return nil
        end
        -- 包一层：动画状态异常时 GetVisualBB 可能报错（modmain 沙箱里 pcall 要走 GLOBAL）
        local ok, _, y1, _, y2 = GLOBAL.pcall(bganim.GetVisualBB, bganim)
        if not ok or y1 == nil or y2 == nil or (y2 - y1) < 200 then
            return nil
        end
        return (y1 + y2) * 0.5
    end

    -- 右侧侧栏有两个 root（widgets/controls.lua:279/285，都是 ANCHOR_RIGHT + ANCHOR_MIDDLE，
    -- 几何位置完全一致）：
    --   containerroot_side        ← issidewidget=true 的容器（原版背包 / 本 mod 分开布局）
    --   containerroot_side_behind ← type="side_inv_behind"（本 mod 融合布局）
    local function BagSideRoots(hud)
        local c = hud ~= nil and hud.controls or nil
        if c == nil then
            return {}
        end
        return { c.containerroot_side, c.containerroot_side_behind }
    end

    -- 面板位置在**开箱那一刻**算，而且是开完再校正一次。理由：
    --   1) ApplyBagLayout 只在 WidgetSetup 时跑，玩家中途切换「整合背包」后 issidewidget /
    --      type 的旧值会残留，布局基准就会和实际挂载的 root 对不上；
    --   2) 原版没有任何“多个侧栏面板排排坐”的逻辑（同 type 才互斥，背包和本袋 type 不同），
    --      两个面板都落在 pos=-5 就会严丝合缝叠在一起 —— 这就是“钟表袋和背包重叠”的成因。
    -- 所以：基准位置跟着**实际挂载的 root** 走，且永远贴到同片侧栏里最左边那个面板的左侧。
    local function BaseBagPos(parent, hud)
        if parent ~= nil and hud ~= nil and hud.controls ~= nil
            and parent == hud.controls.containerroot_side_behind then
            return BAG_POS_INTEGRATED
        end
        -- 还没挂上去（posfn 阶段拿不到 parent）时，先按设置项给一个合理初值
        if parent == nil and IsIntegratedBackpackLayout() then
            return BAG_POS_INTEGRATED
        end
        return BAG_POS_SIDE
    end

    -- 把 self（本袋的 ContainerWidget）挪到不重叠的位置。self 为 nil 时只算基准位置。
    local function ComputeBagPos(parent, self, container, doer)
        local hud = doer ~= nil and doer.HUD or nil
        if hud == nil or hud.controls == nil then
            return BAG_POS_SIDE
        end
        local base = BaseBagPos(parent, hud)
        local x = base.x
        -- 同一片侧栏（两个 root 几何重合，一起比）里已经有别的容器面板 → 贴到最左者左侧
        local leftmost = nil
        local neighbor = nil
        -- 注意：Widget.children 是「以 widget 为键的 set」（widgets/widget.lua:305），
        -- 不是数组，必须用 pairs 遍历（ipairs 会一个都取不到）。
        for _, root in ipairs(BagSideRoots(hud)) do
            if root ~= nil and root.children ~= nil then
                for _, child in pairs(root.children) do
                    if child ~= self and child.container ~= nil
                        and child.container ~= container and child.GetPosition ~= nil then
                        local p = child:GetPosition()
                        if p ~= nil and p.x <= 0 and (leftmost == nil or p.x < leftmost) then
                            leftmost = p.x
                            neighbor = child
                        end
                    end
                end
            end
        end
        if leftmost ~= nil then
            local cand = leftmost - BAG_PANEL_W_POS - BAG_PANEL_GAP_POS
            if cand < x then
                x = cand
            end
        end
        -- 垂直方向：让两个面板的**美术中心**落在同一条中轴线上（需求：分开布局上下居中对齐）。
        --   自己：BAG_ART_CENTER_LOCAL（固定美术，常量）
        --   对方：GetVisualBB 实测（每套底图的美术中心都不一样，原版就是靠各自不同的
        --         pos.y 让面板看起来各自居中：backpack -80 / spicepack -70 / piggyback -90 /
        --         krampus_sack -130，见 containers.lua）
        --   两者之差 × 0.6（ContainerWidget 的缩放）= pos 单位。
        local y = base.y
        if neighbor ~= nil then
            local nb_center = NeighborArtCenterY(neighbor)
            local nb_pos = neighbor:GetPosition()
            if nb_center ~= nil and nb_pos ~= nil then
                y = nb_pos.y + (nb_center - BAG_ART_CENTER_LOCAL) * CONTAINER_WIDGET_SCALE
            end
        end
        return Vector3(x, y, base.z)
    end

    -- posfn：ContainerWidget:Open 里 SetPosition 之前调用（widgets/containerwidget.lua:50）。
    -- 这时 self.container 还没赋值（containerwidget.lua:188），只能给个基准；精确校正靠下面
    -- 包一层 ContainerWidget:Open。
    local function BagPanelPosFn(container, doer)
        return ComputeBagPos(nil, nil, container, doer)
    end

    -- 「整合背包」这个设置项可能在玩家游戏中途被切换，而 ApplyBagLayout 只在 WidgetSetup
    -- 时跑一次：issidewidget / type 会是旧值，面板就可能挂进原版背包的槽位（重叠的另一种成因）。
    -- 开箱前按当前设置把这三样（side / issidewidget / type）校正一遍。
    do
        local PlayerHud = GLOBAL.require("screens/playerhud")
        local OldOpenContainer = PlayerHud.OpenContainer
        PlayerHud.OpenContainer = function(self, container, side)
            local replica_container = container ~= nil and container.prefab == WANDA_WATCH_BAG
                and container.replica ~= nil and container.replica.container or nil
            if replica_container ~= nil then
                local want_side = not IsIntegratedBackpackLayout()
                replica_container.issidewidget = want_side
                replica_container.type = want_side and "wanda_watch_bag" or "side_inv_behind"
                side = want_side
            end
            return OldOpenContainer(self, container, side)
        end
    end

    -- 只在“本袋的面板”上做后校正，其它容器原样不动（不改类的行为，只加一层转发）
    do
        local ContainerWidget = GLOBAL.require("widgets/containerwidget")
        local OldContainerWidgetOpen = ContainerWidget.Open
        ContainerWidget.Open = function(self, container, doer)
            OldContainerWidgetOpen(self, container, doer)
            if container ~= nil and container.prefab == WANDA_WATCH_BAG then
                self:SetPosition(ComputeBagPos(self:GetParent(), self, container, doer))
            end
        end
    end

    -- 两种布局只差 pos：slotpos / slotscale 必须一模一样——面板底图（bganim）是按
    -- ContainerWidget 的局部坐标 1:1 画的，把 slotpos 缩小只会让格子脱离底图上的格框。
    -- 两套布局的屏幕上大小相同（都是 0.898 px/局部单位，见下面融合布局注释）。
    local function MakeBagWidget(pos)
        local widget = {
            slotpos = {},
            animbank = "ui_krampusbag_2x8",
            animbuild = "ui_krampusbag_2x8",
            pos = pos,
            -- posfn 优先于 pos（widgets/containerwidget.lua:50）。位置见 BagPanelPosFn。
            posfn = BagPanelPosFn,
            slotscale = BAG_SLOT_SCALE,
            -- 音效必须写在这里（而不是只靠 prefab 里改 widget）：widget 表是每个 Lua 状态一份，
            -- 专用服/真客户端上 prefab 的修改发生在服务端那份表上，客户端 replica 的 widget
            -- 拿不到它。融合布局下 IsSideWidget() == false，只有这一层能保证仍是背包音效。
            opensound = "dontstarve/wilson/backpack_open",
            closesound = "dontstarve/wilson/backpack_close",
        }
        for y = 0, 7 do
            local rowy = BAG_ROW_Y0 - BAG_ROW_DY * y
            table.insert(widget.slotpos, Vector3(BAG_COL_X[1], rowy, 0))
            table.insert(widget.slotpos, Vector3(BAG_COL_X[2], rowy, 0))
        end
        return widget
    end

    -- 分开布局（侧边容器）：
    --   containerroot_side 是右侧中部对齐（widgets/controls.lua:285），原版背包 / 克劳斯袋
    --   都用 pos.x = -5。
    --
    --   【单位坑】pos 是挂载点的坐标（1 单位 ≈ 1.50 px），而底图/格子的偏移是
    --   ContainerWidget 的局部坐标（1 单位 = 0.6 × 1.50 = 0.90 px）——两层差 0.6 倍。
    --   所以“底图宽 211 局部单位”在 pos 意义上只有 127 单位，两块侧边面板相接的
    --   pos 间距是 ≈127，不是 211。
    --
    --   实测标定（t27 直接改 pos 量的，2560×1440，误差 <1 px）：
    --     pos=(-114,-85) → panel world (2389,593)，底图本体 x ∈ [2180,2370]（宽 190 px）
    --     pos=(-5,-85)   → panel world (2552,593)，底图本体 x ∈ [2345,2535]（宽 190 px，与原版背包同形）
    --   → 1 个 pos 单位 ≈ 1.50 px；底图相对 widget 原点 x ∈ [-209, -19] px
    --     （= 局部 [-233, -21]，宽 211 局部单位，中心 -127 ≈ 两列中点 -124.5）。
    --   → 两块侧边面板相接所需的 pos 间距 = 190 px / 1.50 ≈ 127 单位（= 211 局部单位 × 0.6）。
    --   （旧的 -185 也是错在这里：当时把底图宽 190 px 误当 157 px，-185 实际缝 ≈112 px。）
    --
    --   原版背包（pos=(-5,-80)）底图左缘 = 2345。取 pos.x = -137：
    --   本袋原点 x = 2560 - 137×1.50 ≈ 2354，右缘 = 2354 - 19 ≈ 2335 → 缝 ≈ 10 px。
    --   （-140 → 14 px；-130 → 完全贴上）
    --   pos.y：背包面板中心在 -80，本袋面板中心在 pos.y + 9，取 -85 上下居中对齐。
    local BAG_WIDGET_SIDE = MakeBagWidget(BAG_POS_SIDE)

    -- 融合布局（v6 需求 3：显示在**右侧**，即分开布局时原版背包面板所在的位置）
    --
    --   v5 是挂 containerroot（屏幕正中）——用户明确否掉：「不要显示在屏幕正中央」。
    --   融合模式下背包格子合进了物品栏，右侧那一片本来就是空的，所以钟表袋直接占
    --   原版背包面板的坑位：pos 取背包自己的 (-5, -80)，底图本体就落在 x ≈ 2345~2535。
    --
    --   挂载点靠 type 选（screens/playerhud.lua:402-412）：
    --     "side_inv_behind" → self.controls.containerroot_side_behind，
    --     它在 widgets/controls.lua:279 是 ANCHOR_RIGHT + ANCHOR_MIDDLE——
    --     即“贴右边缘、垂直居中”，和 containerroot_side（原版背包侧边面板）同一个锚点。
    --
    --   为什么不用侧边容器（issidewidget=true）来蹭这个位置：融合模式下
    --   PlayerHud:OpenContainer/CloseContainer（playerhud.lua:391/438）会把 side 容器
    --   转成 inv.rebuild_pending，面板不落地也不收起。所以必须 issidewidget=false，
    --   只是把 type 指到右锚的 containerroot_side_behind。
    --
    --   为什么不用自定义 type + pos.x 往右推：containerroot 是“屏幕中心”锚点，
    --   任何 x 偏移都会随分辨率漂。右锚点才是分辨率无关的。
    --
    --   openlimit 同分开布局；格子布局 slotpos 两套都一样（见 MakeBagWidget 注释）。
    --   一个已知副作用：side_inv_behind 是韦伯胡子袋（containers.lua:1370）在用的 type，
    --   Container:Open 会关闭同 type 的其它容器——韦伯没有旺达的袋子，实际不会同时出现。
    local BAG_WIDGET_INTEGRATED = MakeBagWidget(BAG_POS_INTEGRATED)

    -- 布局按当前设置项二选一（widget + issidewidget + type 三者一起换）
    local function ApplyBagLayout(container)
        if IsIntegratedBackpackLayout() then
            container.widget = BAG_WIDGET_INTEGRATED
            container.issidewidget = false
            container.type = "side_inv_behind"
        else
            container.widget = BAG_WIDGET_SIDE
            container.issidewidget = true
            -- 分开布局不看 type（走 issidewidget=true 分支），给个自己的值即可。
            -- 别用 "pack"/"chest"：Container:Open（container.lua:625）会关闭“同一 type”的
            -- 其它容器，用 "pack" 会导致开背包时把钟表袋顶掉、开钟表袋时把背包顶掉。
            container.type = "wanda_watch_bag"
        end
        container.openlimit = 1
        container:SetNumSlots(#BAG_WIDGET_SIDE.slotpos)
    end

    -- 需求 6 + 9：钟表袋"开启 / 关闭"——一个动作管两端，动画用原版"添加燃料"同款短动作
    --
    -- 原版对"已被自己打开"的容器不再给 RUMMAGE（componentactions.lua:296 的
    -- replica.container:CanBeOpened() 配合 openlimit），所以右键已打开的袋子等于没反应。
    -- 这里给钟表袋一个自己的动作：开着 → 关，关着 → 开。priority 2 高于原版 RUMMAGE（-1），
    -- 所以悬停/右键看到的就是这个动作（文案"开启 / 关闭"由 stroverridefn 决定）。
    --
    -- 动画：不能用 instant（无动画），也不能等状态机自己猜——自定义动作没有 ActionHandler 时
    -- StateGraphInstance:PreviewAction 会把它当 previewaction 静默丢弃（fn 永不执行，见踩坑文档 §16）。
    -- 原版 ACTIONS.ADDFUEL 走的是 "doshortaction"（SGwilson.lua:1041；pickup/pickup_pst 共 10 帧，
    -- 第 6 帧 PerformBufferedAction），这里照抄；客户端预测需另给 "wilson_client" 加一份。
    -- mount_valid = true：骑牛时也能开关。骑乘中 playeractionpicker 会压一个
    -- MountedActionFilter（components/rider_replica.lua:135，只放行 action.mount_valid == true，
    -- 优先级 ACTION_FILTER_PRIORITIES.mounted = 20），它作用在所有动作收集器（含 INVENTORY）上，
    -- 所以不加这个字段就是“右键提示没了、点了也没反应”——而本袋的自动关闭全被拦掉，
    -- 于是骑在牛上就再也关不掉。原版 RUMMAGE / EAT / ADDFUEL 等也都是 mount_valid。
    -- 不要顺手加 encumbered_valid / floating_valid：原版 RUMMAGE 也没有，保持一致。
    local ToggleBagAction = GLOBAL.Action({ rmb = true, priority = 2, distance = 0, mount_valid = true })
    ToggleBagAction.id = "WANDA_TOGGLE_WATCH_BAG"
    ToggleBagAction.str = "开启"
    ToggleBagAction.fn = function(act)
        local bag, doer = act.invobject, act.doer
        if bag == nil or not bag:IsValid() or doer == nil or bag.components == nil then
            return false
        end
        local container = bag.components.container
        if container == nil then
            return false
        end
        if container:IsOpenedBy(doer) then
            -- 必须用广播式 Close()（不带 doer）：钟表袋的 Close 会把带 doer 的调用当作
            -- 原版自动关闭一律忽略，见 scripts/prefabs/wanda_watch_bag.lua
            container:Close()
            return true
        end
        if not container:CanOpen() then
            return false
        end
        container:Open(doer)
        return true
    end
    -- 右键文案：关着 → "开启"，开着 → "关闭"（不要"关闭钟表袋"）。
    -- stroverridefn 返回 nil 时回落到 STRINGS.ACTIONS[...]（bufferedaction.lua:52），
    -- 所以下面的 STRINGS 只当兜底。
    ToggleBagAction.stroverridefn = function(act)
        local bag = act.invobject
        local container = bag ~= nil and bag.replica ~= nil and bag.replica.container or nil
        if container == nil then
            return nil
        end
        return container:IsOpenedBy(act.doer) and "关闭" or "开启"
    end
    -- 注意：AddAction / AddComponentAction / AddStategraphActionHandler 是 modmain 环境注入的接口，
    -- 不在 _G 里，写成 GLOBAL.AddAction 会触发 "variable 'AddAction' is not declared" 并禁用整个 mod
    AddAction(ToggleBagAction)
    GLOBAL.STRINGS.ACTIONS.WANDA_TOGGLE_WATCH_BAG = "开启"
    AddStategraphActionHandler("wilson", GLOBAL.ActionHandler(ToggleBagAction, "doshortaction"))
    AddStategraphActionHandler("wilson_client", GLOBAL.ActionHandler(ToggleBagAction, "doshortaction"))

    -- 注意 right 参数：物品栏 tooltip（widgets/itemtile.lua:513）调 GetInventoryActions 时不传
    -- right（nil），实际右键（playercontroller.lua:5337）传 true，左键传 false。
    -- 写 if not right then return end 会让动作只在点击时存在、悬停提示看不到，所以只跳过 left。
    AddComponentAction("INVENTORY", "container", function(inst, doer, actions, right)
        -- 需求 3（v5）：只有旺达能看到 / 使用这个动作。replica.container:CanBeOpened() 是
        -- 整实体 netvar、不带 doer，没法按玩家区分（见 scripts/prefabs/wanda_watch_bag.lua 的注释），
        -- 所以这一层用 doer.prefab 直接把非旺达的动作隐藏掉。
        if right == false or inst.prefab ~= WANDA_WATCH_BAG
            or doer == nil or doer.prefab ~= "wanda" then
            return
        end
        local container = inst.replica.container
        if container ~= nil and (container:IsOpenedBy(doer) or container:CanBeOpened()) then
            table.insert(actions, ToggleBagAction)
        end
    end)

    -- 客户端 replica 的 container 构造时调的是 containers.widgetsetup(self)
    -- ——**不带 prefab**（components/container_replica.lua:47），原包装靠
    -- params[container.inst.prefab] 取布局；自定义 prefab 不在 params 里，所以客户端
    -- 的 replica 拿不到 widget / issidewidget / type，widgets/containerwidget.lua:28
    -- 会索引 nil（面板打不开、音效回落成通用 container_open）。两条路都铺：
    --   1) 往 containers.params 里登记一份（原版 widgetsetup 的查表兜底）；
    --   2) 下面包裹 widgetsetup，把 prefab = nil 的调用也认出来（布局要按设置项动态选，
    --      静态 params 表装不下两套 pos/type，所以真正的判定放在这里）。
    containers.params[WANDA_WATCH_BAG] = {
        widget = BAG_WIDGET_SIDE,
        issidewidget = true,
        type = "wanda_watch_bag",
        openlimit = 1,
    }

    containers.widgetsetup = function(container, prefab, data)
        local name = prefab or (container.inst ~= nil and container.inst.prefab or nil)
        if name == WANDA_WATCH_BAG then
            ApplyBagLayout(container)
            return
        end
        return OldWidgetSetup(container, prefab, data)
    end
end

--------------------------------------------------------------------------
-- 需求 4：溯源表 / 裂缝表可用羽毛笔命名
--
-- v4 追加：右键文案"命名"；命名后名字变「溯源表-XXX」并同步给客户端。
--
-- 官方范本 prefabs/kitcoon_nametag.lua：writeables.AddLayout 注册界面布局 + writeable 组件；
-- 写手由 classified 同步后客户端自动开屏。
-- 动作入口【v5 改正】：用户是“点一下羽毛笔把它放到鼠标上，再右键表”，这条路径是
--   Inventory:UseItemFromInvTile（components/inventory.lua:2276）→ GetUseItemActions
--   （playeractionpicker.lua:145 useitem:CollectActions("USEITEM", ...)），
-- 动作必须注册在**羽毛笔**上（USEITEM/inventoryitem）；v4 注册在表的 writeable 上，
-- 而那条 INVENTORY 收集器只在“手上没东西”时才会被调，所以永远不触发。
-- 其余两条保留：INVENTORY（笔已装备）、SCENE（地上的表）。
-- tip：悬停时的“右键: 命名”不需要另外包 itemtile——widgets/itemtile.lua:529 在 active_item
-- 存在时会自己把 GetUseItemActions 的首项拼上（GetActionString → stroverridefn）。
--------------------------------------------------------------------------

if ENABLE_NAMEABLE_WATCHES then
    local writeables = GLOBAL.require("writeables")

    local WATCH_WRITE_LAYOUT = {
        prompt = "给钟表命名 / Name this watch",
        animbank = "ui_board_5x3",
        animbuild = "ui_board_5x3",
        menuoffset = Vector3(6, -70, 0),
        maxcharacters = 40,

        cancelbtn = { text = GLOBAL.STRINGS.SIGNS.MENU.CANCEL, cb = nil, control = GLOBAL.CONTROL_CANCEL },
        acceptbtn = { text = GLOBAL.STRINGS.SIGNS.MENU.ACCEPT, cb = nil, control = GLOBAL.CONTROL_ACCEPT },
    }

    local NAMABLE_WATCHES = {
        pocketwatch_recall = true, -- 溯源表
        pocketwatch_portal = true, -- 裂缝表
    }

    local function IsNamableWatch(inst)
        return inst ~= nil and inst.prefab ~= nil and NAMABLE_WATCHES[inst.prefab] == true
    end

    -- 书写工具判定：羽毛笔是原版唯一一种；writeable_tool 给别的 mod 的工具留个口子
    local function IsWritingTool(inst)
        return inst ~= nil and (inst.prefab == "featherpencil" or inst:HasTag("writeable_tool"))
    end

    local function HoldsWritingTool(doer)
        local inventory = doer ~= nil and doer.replica ~= nil and doer.replica.inventory or nil
        if inventory == nil then
            return false
        end
        return IsWritingTool(inventory:GetEquippedItem(GLOBAL.EQUIPSLOTS.HANDS))
    end

    -- 表是否在书写者身上（物品栏 / 背包 / 装备栏）。
    -- 原版 ACTIONS.WRITE.fn 对 act.target 一律调 CanEntitySeeTarget，而“自己身上的东西”
    -- 位置会跟着主人走（components/inventoryitem.lua:353 owner:AddChild + 本地坐标归零），
    -- 视线判定不可靠（可能直接 return false），所以在自己身上时跳过。
    local function IsHeldBy(inst, doer)
        local inventoryitem = inst ~= nil and inst.components ~= nil and inst.components.inventoryitem or nil
        return inventoryitem ~= nil and inventoryitem:GetGrandOwner() == doer
    end

    for prefab, _ in pairs(NAMABLE_WATCHES) do
        writeables.AddLayout(prefab, WATCH_WRITE_LAYOUT)

        AddPrefabPostInit(prefab, function(inst)
            -- 两端都装显示名：直接读 named 的 net_string（客户端也是同步值），
            -- 不依赖 named_replica 的脏事件时序（首次同步/读档后立刻显名）。
            -- 没命名过（空串）就返回 nil，回落到原版名字（STRINGS.NAMES）。
            inst.displaynamefn = function(watch)
                local replica_named = watch.replica ~= nil and watch.replica.named or nil
                local synced = replica_named ~= nil and replica_named._name ~= nil
                    and replica_named._name:value() or nil
                if synced ~= nil and synced ~= "" then
                    return synced
                end
                return nil
            end

            if not IsMasterSim() then
                return
            end

            if inst.components.writeable == nil then
                inst:AddComponent("writeable")
            end
            local writeable = inst.components.writeable
            -- 不走原版"写一次就摘 tag"的默认语义：命名可以反复改，动作由下面的
            -- AddComponentAction 自己发（是否出现只看有没有拿书写工具）。
            -- 顺带好处：不挂 writeable tag，原版按 tag 给的 SCENE 写动作就绕不过"必须拿笔"。
            writeable:SetDefaultWriteable(false)
            -- automatic_description: 写过的文本作为检查描述显示，用于区分不同标记点的表
            writeable:SetAutomaticDescriptionEnabled(true)
            writeable:SetWriteableDistance(3)

            -- 需求 4：名字显示成「溯源表-XXX」。
            -- 用官方的 named 组件（components/named.lua + named_replica.lua）：它把名字塞进
            -- net_string 同步给客户端，客户端的 EntityScript:GetBasicDisplayName（entityscript.lua:687）
            -- 取到的就是同步过来的 self.name，所以物品栏 / 地上的悬停名字都对。
            -- nameformat 由 Named:DoSetName（named.lua:9）用 string.format(nameformat, name) 展开。
            if inst.components.named == nil then
                inst:AddComponent("named")
            end
            local named = inst.components.named
            named.nameformat = (GLOBAL.STRINGS.NAMES[string.upper(prefab)] or "") .. "-%s"

            writeable:SetOnWrittenFn(function(watch, text)
                if text ~= nil and text ~= "" then
                    named:SetName(text)
                else
                    named:SetName(nil) -- 清空输入框 = 恢复原名
                end
            end)
        end)
    end

    -- 右键文案必须是"命名"（原版是 Write On / 写）。
    -- 用 stroverridefn（bufferedaction.lua:59 调用，返回 nil 就回落到原版文本），
    -- 不去改 STRINGS.ACTIONS.WRITE，牌子等其它可写物品的文案不受影响。
    local OldWriteStroverride = GLOBAL.ACTIONS.WRITE.stroverridefn
    GLOBAL.ACTIONS.WRITE.stroverridefn = function(act)
        if act ~= nil and (IsNamableWatch(act.invobject) or IsNamableWatch(act.target)) then
            return "命名"
        end
        return OldWriteStroverride ~= nil and OldWriteStroverride(act) or nil
    end

    -- 动作收集器：物品栏里 / 地上的表
    --
    -- 【v5 根因】用户的操作是“羽毛笔在鼠标上（active item）”，此时：
    --   * 悬停 tooltip：widgets/itemtile.lua:529 走 GetUseItemActions；
    --   * 右键执行：components/inventory.lua:2276 Inventory:UseItemFromInvTile →
    --     GetUseItemActions(item, active_item, true) → playeractionpicker.lua:145
    --     → **useitem（羽毛笔）**:CollectActions("USEITEM", doer, target, actions, right)。
    --   也就是说动作必须注册在鼠标上的那根羽毛笔上，原来的 INVENTORY/writeable 两条永远不会
    --   在“手里拿着笔”的路径上被调用（那时 GetInventoryActions 压根不会被调）。
    --
    -- 组件名选择：EntityScript:CollectActions 只跑实体上真实存在的组件
    -- （componentactions.lua:3236），而 mod 的组件 id 是**从服务端同步过来的**
    -- （entityscript.lua:97 / componentactions.lua:3194），所以客户端没有 writeable 组件也不影响——
    -- 只要服务端实体的组件 id 列表里有它。三个 actiontype 用三个**不同**的组件名，
    -- 避开 MOD_ACTION_COMPONENT_IDS 同名互相覆盖（componentactions.lua:3174）：
    --   USEITEM → inventoryitem（羽毛笔）
    --   INVENTORY → named（手上的表，笔已装备时用）
    --   SCENE → writeable（地上的表，与其它 mod / 原版同名无冲突）
    local function InsertWriteAction(inst, doer, actions, right)
        if right == false or not IsNamableWatch(inst) or not HoldsWritingTool(doer) then
            return
        end
        table.insert(actions, GLOBAL.ACTIONS.WRITE)
    end
    AddComponentAction("INVENTORY", "named", InsertWriteAction) -- 物品栏 / 背包里的表（笔在手上）
    AddComponentAction("SCENE", "writeable", InsertWriteAction) -- 丢在地上的表

    -- 需求 5 的关键一条：inst 是鼠标上的书写工具，target 是被悬停的表。
    -- 只跳过左键（right == false），不写 if not right——悬停 tooltip 传的就是 true。
    AddComponentAction("USEITEM", "inventoryitem", function(inst, doer, target, actions, right)
        if right == false or not IsWritingTool(inst) or not IsNamableWatch(target) then
            return
        end
        table.insert(actions, GLOBAL.ACTIONS.WRITE)
    end)

    -- 原版 ACTIONS.WRITE.fn 只处理 act.target，而且写过就不让再写；这里补两种入口：
    --   * SCENE / USEITEM：act.target 是表（羽毛笔在鼠标上时 act.invobject 是笔）；
    --   * INVENTORY：没有 target，但 act.invobject 是表（笔已装备）。
    -- 并允许改名（表是“锚点标签”，名字写错了要能改）。
    --
    -- 注意：这段在**服务端**负责真正生效（BeginWriting 设 writer → writeable_classified
    -- 同步 → 客户端 replica 才开输入框，components/writeable_replica.lua:118），
    -- 客户端预测跑同一函数时 components 里没有 writeable，会自然回落到 OldWriteFn（无副作用）。
    local OldWriteFn = GLOBAL.ACTIONS.WRITE.fn
    GLOBAL.ACTIONS.WRITE.fn = function(act)
        if act.doer == nil or act.doer.components == nil then
            return OldWriteFn(act)
        end
        local watch = nil
        if IsNamableWatch(act.target) then
            watch = act.target
        elseif act.target == nil and IsNamableWatch(act.invobject) then
            watch = act.invobject
        end
        local writeable = watch ~= nil and watch.components.writeable or nil
        if writeable == nil then
            return OldWriteFn(act) -- 牌子等其它可写物品一律走原版
        end
        if writeable:IsBeingWritten() then
            return false, "INUSE"
        end
        -- 在自己身上的表跳过视线判定（见 IsHeldBy 注释）；地上的表仍要求看得见（与原版一致）
        if not IsHeldBy(watch, act.doer) and not GLOBAL.CanEntitySeeTarget(act.doer, watch) then
            return false
        end
        writeable:BeginWriting(act.doer)
        return true
    end
end

--------------------------------------------------------------------------
-- 需求 9：加速表 / 减速表的右键文案（激活 / 提升档位 / 停用）
--
-- 不能直接改 STRINGS.ACTIONS.CAST_POCKETWATCH（会连带改掉原版四种钟表）。
-- 做法：给这两件物品一个自己的动作，动画复用原版 CAST_POCKETWATCH 的 ActionHandler 目标
-- （SGwilson.lua:1336 → "pocketwatch_cast"；我们的表没有 recall_unmarked /
-- pocketwatch_warp_casting tag，prefab 也不是 pocketwatch_portal，原版会给的也是这一状态）。
-- fn 直接走 pocketwatch:CastSpell（内部就会调 prefab 自带的 DoCastSpell 切换档位/开关）。
-- 文案用 stroverridefn 分三态（具体规则见下方 stroverridefn 前的注释）；
-- 档位由 scripts/prefabs/wanda_*_watch.lua 用 net_byte 同步，tag "wanda_watch_on" 只表达开/关。
--------------------------------------------------------------------------

local TOGGLE_WATCH_PREFABS = {}
if ENABLE_HASTE_WATCH then
    TOGGLE_WATCH_PREFABS[WANDA_HASTE_WATCH] = true
end
if ENABLE_SLOW_WATCH then
    TOGGLE_WATCH_PREFABS[WANDA_SLOW_WATCH] = true
end

if next(TOGGLE_WATCH_PREFABS) ~= nil then
    local ToggleWatchAction = GLOBAL.Action({ rmb = true, priority = 2, distance = 0 })
    ToggleWatchAction.id = "WANDA_TOGGLE_WATCH"
    ToggleWatchAction.str = "激活"
    ToggleWatchAction.fn = function(act)
        local watch, doer = act.invobject, act.doer
        if watch == nil or not watch:IsValid() or doer == nil or watch.components == nil then
            return false
        end
        local pocketwatch = watch.components.pocketwatch
        if pocketwatch == nil then
            return false
        end
        -- CastSpell 内部会检查 inactive（充能中不施法），然后回调 prefab 的 DoCastSpell
        return pocketwatch:CastSpell(doer, act.target, act.pos)
    end
    -- 右键文案分三态（监工定案）：档位是循环切换（0 → 30% → 50% → 0，
    -- 两张表都是两档），"停用"只在"再按一次就归零"的最高档才诚实，
    -- 中间档写“停用”会误导，所以统一为：
    --   1 档（关）→ “激活”；中间档 → “提升档位”；最高档 → “停用”
    -- 档位读 w-watch 同步过来的 net_byte（_tiernet），客户端文案才和真实档位一致；
    -- 拿不到时退回 _tier，最后退回 tag（二元 degrade）。
    ToggleWatchAction.stroverridefn = function(act)
        local watch = act.invobject
        if watch == nil then
            return nil
        end
        local tier = watch._tiernet ~= nil and watch._tiernet:value() or watch._tier
        if tier == nil then
            return watch:HasTag(WANDA_WATCH_ON_TAG) and "停用" or "激活"
        end
        -- 档位总数以 scripts/wanda_planar_age.lua 为准（单一数据源），取不到再退回常量
        local count = 0
        local age = GetAge()
        if age ~= nil then
            local tiers = watch.prefab == WANDA_HASTE_WATCH and age.HASTE_TIERS
                or (watch.prefab == WANDA_SLOW_WATCH and age.SLOW_TIERS or nil)
            count = tiers ~= nil and #tiers or 0
        end
        if count <= 1 then
            count = 3
        end
        if tier <= 1 then
            return "激活"
        elseif tier >= count then
            return "停用"
        end
        return "提升档位"
    end

    AddAction(ToggleWatchAction)
    GLOBAL.STRINGS.ACTIONS.WANDA_TOGGLE_WATCH = "激活"
    -- 动画与现在一致：进原版施法状态；客户端预测也注册一份（客户端该状态是等服务器转发的桩）
    AddStategraphActionHandler("wilson", GLOBAL.ActionHandler(ToggleWatchAction, "pocketwatch_cast"))
    AddStategraphActionHandler("wilson_client", GLOBAL.ActionHandler(ToggleWatchAction, "pocketwatch_cast"))

    -- 只给加速表 / 减速表，原版钟表仍然走 CAST_POCKETWATCH。
    -- 骑乘限制照抄原版 pocketwatch 的 componentaction（骑乘时不能从物品栏施法）。
    AddComponentAction("INVENTORY", "pocketwatch", function(inst, doer, actions, right)
        if right == false or TOGGLE_WATCH_PREFABS[inst.prefab] ~= true then
            return
        end
        if not doer:HasTag("pocketwatchcaster") then
            return
        end
        if doer.replica.rider ~= nil and doer.replica.rider:IsRiding()
            and not inst:HasTag("pocketwatch_mountedcast") then
            return
        end
        table.insert(actions, ToggleWatchAction)
    end)
end

--------------------------------------------------------------------------
-- 新物品显示名
--------------------------------------------------------------------------

if ENABLE_HASTE_WATCH then
    GLOBAL.STRINGS.NAMES.WANDA_HASTE_WATCH = "加速表"
    GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.WANDA_HASTE_WATCH = "指针拨快一点，时间就不够用了。右键切换档位。"
    -- 配方弹窗读 STRINGS.RECIPE_DESC[大写产品名]（widgets/recipepopup.lua:297），
    -- 不写会显示空白描述（SetMultilineTruncatedString 对 nil 会静默渲染空串）
    GLOBAL.STRINGS.RECIPE_DESC.WANDA_HASTE_WATCH = "拨动指针，让时间走得更快一些。"
end
if ENABLE_SLOW_WATCH then
    GLOBAL.STRINGS.NAMES.WANDA_SLOW_WATCH = "减速表"
    GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.WANDA_SLOW_WATCH = "让周围的家伙都慢下来——代价是自己老得更快。右键开关。"
    GLOBAL.STRINGS.RECIPE_DESC.WANDA_SLOW_WATCH = "把周围的敌人都拖进慢动作里，自己却老得更快。"
end
if ENABLE_WATCH_BAG then
    GLOBAL.STRINGS.NAMES.WANDA_WATCH_BAG = "钟表袋"
    GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.WANDA_WATCH_BAG = "专门装钟表的袋子，挂在腰带上也不会关。"
    GLOBAL.STRINGS.RECIPE_DESC.WANDA_WATCH_BAG = "随身携带的钟表收纳袋，只装得下钟表。"
end

--------------------------------------------------------------------------
-- 制作配方（旺达专属，clockmaker）
--
-- config.atlas / config.image：Recipe2 会把它们存进 Recipe:GetAtlas()（recipe.lua:195）。
-- 不传时 GetAtlas 会走 GetInventoryItemAtlas()，而它只查原版 4 张 inventoryimages 图集
-- （simutil.lua:675），mod 图集查不到 → 制作栏图标空白。
-- 同时用官方接口注册图集，让别的界面（拾取提示、搜索等）也能查到。
--------------------------------------------------------------------------

local function RegisterInvAtlas(name)
    if GLOBAL.RegisterInventoryItemAtlas ~= nil then
        GLOBAL.RegisterInventoryItemAtlas("images/inventoryimages/" .. name .. ".xml", name .. ".tex")
    end
end

local function InvAtlasConfig(name, opts)
    opts.atlas = "images/inventoryimages/" .. name .. ".xml"
    opts.image = name .. ".tex"
    return opts
end

-- 需求 3（v4）：材料调整。
-- pocketwatch_parts 就是游戏里中文的"时间碎片"（prefabs/pocketwatch_parts.lua），没有 time_shard 这个 prefab。
if ENABLE_HASTE_WATCH then
    RegisterInvAtlas(WANDA_HASTE_WATCH)
    AddRecipe2(WANDA_HASTE_WATCH,
        {
            GLOBAL.Ingredient("pocketwatch_parts", 2), -- 时间碎片
            GLOBAL.Ingredient("goldnugget", 2),
            GLOBAL.Ingredient("walrus_tusk", 1),        -- 海象牙
        },
        GLOBAL.TECH.NONE,
        InvAtlasConfig(WANDA_HASTE_WATCH, { builder_tag = "clockmaker" }),
        { "CHARACTER" })
end

if ENABLE_SLOW_WATCH then
    RegisterInvAtlas(WANDA_SLOW_WATCH)
    AddRecipe2(WANDA_SLOW_WATCH,
        {
            GLOBAL.Ingredient("pocketwatch_parts", 2),
            GLOBAL.Ingredient("nightmarefuel", 4),
            GLOBAL.Ingredient("purplegem", 1),          -- 由 prefabs/gem.lua 动态生成（不在 prefablist 字面量里）
        },
        GLOBAL.TECH.NONE,
        InvAtlasConfig(WANDA_SLOW_WATCH, { builder_tag = "clockmaker" }),
        { "CHARACTER" })
end

if ENABLE_WATCH_BAG then
    RegisterInvAtlas(WANDA_WATCH_BAG)
    AddRecipe2(WANDA_WATCH_BAG,
        {
            GLOBAL.Ingredient("pocketwatch_parts", 2),
            GLOBAL.Ingredient("pigskin", 4),            -- 猪皮
            GLOBAL.Ingredient("silk", 4),               -- 蜘蛛丝
        },
        GLOBAL.TECH.NONE,
        InvAtlasConfig(WANDA_WATCH_BAG, { builder_tag = "clockmaker" }),
        { "CHARACTER" })
end
