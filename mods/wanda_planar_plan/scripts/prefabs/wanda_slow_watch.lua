-- 减速表 / Slow Watch
--
-- 右键循环切档（复用原版 CAST_POCKETWATCH：物品栏中的钟表右键即施法，
-- 见 scripts/componentactions.lua:2848；需要 pocketwatch_castfrominventory 标签）。
--
-- 档位（v4 需求 8）：1 = 关闭、2 = 减速 30%、3 = 减速 60%。
-- 档位存在**玩家**身上（v4 需求 5）：player._wanda_slow_tier，详见 scripts/wanda_planar_age.lua。
-- 本文件里的 inst._tier / inst._is_on 只是玩家状态的缓存（显示名 + tag 契约 wanda_watch_on + 存档）。
-- 效果（减速光环 + 自身老化）挂在玩家身上，所以表丢到地上 / 放进钟表袋都照样生效，
-- 同玩家的所有减速表共享同一个档位。
-- 反向的兜底（D2 裁决）：「没有表就不再持有该状态」—— 名下最后一块减速表被拆解 / 烧毁 / 被吞
-- 或送给别人时（onremove / 换主人），档位归 1（关闭）并立刻收掉光环与粒子；丢地上不算（登记保留）。
--
-- 开启时：
--   1. 周期性把周边 12 格内敌对生物的移速降到 70% / 40%
--      （范围取薇格弗德战歌的 attach 半径，TUNING.BATTLESONG_ATTACH_RADIUS = 12，tuning.lua:4956）；
--   2. 受影响生物身上挂沃尔特减速弹同款粒子特效（prefabs/slingshotammo_debuffs.lua:561
--      slingshotammo_slow_debuff_fx，用法对照 prefabs/slingshotammo.lua:349~360）；
--   3. 自身老化 +30% / +60%（通过 scripts/wanda_planar_age.lua 与加速表合成，避免互相覆盖）。
--
-- 移速：LocoMotor:SetExternalSpeedMultiplier(source, key, m)（components/locomotor.lua:490）
--       key 用 "wanda_slow_watch"，不与沃尔特减速弹的 "slingshotammo_slow" 冲突
--       （不同 key 是相乘叠加，和原版多来源减速的处理一致）。

local assets =
{
	-- 骨架（bank "pocketwatch"）与外观（build）是两份资源，原版 pocketwatch.lua 同样两个都声明；
	-- 只声明 build 时，没加载过原版钟表的客户端会 SetBank 失败 → 物品不可见
	-- 自定义地面外观（tools/gen_item_build.py 用官方 scml 编译器生成）
	Asset("ANIM", "anim/wanda_slow_watch.zip"),
	-- 图标资源必须显式 ATLAS + IMAGE（Asset("INV_IMAGE", ...) 只认原版图集，原因见 wanda_haste_watch.lua）
	Asset("ATLAS", "images/inventoryimages/wanda_slow_watch.xml"),
	Asset("IMAGE", "images/inventoryimages/wanda_slow_watch.tex"),
}

-- 粒子特效是独立 prefab（沃尔特的减速弹药 debuff），作为依赖声明：
-- 引擎会连同它的 anim（anim/slingshotammo_slow_fx.zip）一起加载到客户端。
local prefabs = { "slingshotammo_slow_debuff_fx" }

local PocketWatchCommon = require("prefabs/pocketwatch_common")
local Age = require("wanda_planar_age")

local MOD_KEY = "wanda_slow_watch"
local ON_TAG = "wanda_watch_on"
local UPDATE_PERIOD = 1
local FIND_MUST_TAGS = { "_combat" }
local FIND_CANT_TAGS = { "player", "playerghost", "INLIMBO", "FX", "NOCLICK" }

-- 需求 1（地面/手持外观与溯源表区分）：乘法着色，不新增 anim build
-- （仓库里没有 Spriter / 编译链）。配色以 palette.md §1 为准（已对齐 w-art 定稿）。
local TINT = { 1.00, 0.12, 0.72 } -- 洋红紫红（w-art 定稿 palette.md §1）

--------------------------------------------------------------------------
-- 两端都要跑的部分（客户端也要正确显示名字 / 颜色）
--------------------------------------------------------------------------

local function DisplayName(inst)
	-- 客户端拿不到服务端的 _tier 字段，档位靠 net_byte 同步（见 common_postinit）
	local tier = inst._tiernet ~= nil and inst._tiernet:value() or inst._tier or 1
	local base = STRINGS.NAMES.WANDA_SLOW_WATCH or inst.name or "减速表"
	-- 需求（v7）：激活时名字变成「减速表 30%」/「减速表 50%」
	local pct = Age.SlowPercent(tier)
	if pct > 0 then
		return string.format("%s %d%%", base, math.floor(pct * 100 + 0.5))
	end
	return base
end

local function common_postinit(inst)
	inst._tiernet = net_byte(inst.GUID, "wanda_slow_watch.tier", "wanda_slow_watchtierdirty")
	inst._tier = 1
	inst._is_on = false

	inst.displaynamefn = DisplayName

	-- 已有独立 build（洋红表盘），不再需要着色
	if TINT ~= nil then inst.AnimState:SetMultColour(1, 1, 1, 1) end

	-- 施法特效颜色：SGwilson 的 pocketwatch 施法状态两端都会读 invobject.castfxcolour，
	-- 放在 master_postinit 之后只有服务端有值，客户端预测的特效会退回白色。
	inst.castfxcolour = { 156 / 255, 108 / 255, 208 / 255 }
end

--------------------------------------------------------------------------
-- 服务端：目标筛选
--------------------------------------------------------------------------

-- 注意：Combat:IsValidTarget 只保证"可被攻击"，连中立动物（牛、猪）都返回 true。
-- 需求是"敌对生物"，所以额外要求 hostile tag —— 该 tag 表示"当前敌对"
-- （猪人只在敌对时才带，牛始终不带；102 个 prefab 使用它）。
local function IsHostileTarget(owner, ent)
	if ent == nil or not ent:IsValid() or ent.components.locomotor == nil or ent.components.combat == nil then
		return false
	end
	if ent:HasTag("player") or ent:HasTag("playerghost") or ent:HasTag("INLIMBO") or ent:HasTag("FX") then
		return false
	end
	if not ent:HasTag("hostile") then
		return false
	end
	local owner_combat = owner.components.combat
	return owner_combat ~= nil and owner_combat:IsValidTarget(ent)
end

--------------------------------------------------------------------------
-- 服务端：粒子特效（同一生物只保留一份）
--
-- 特效归"生物"所有，等级按"当前有几个减速表在影响它"取最强的一档：
--   target._wanda_slow_fx        特效实体
--   target._wanda_slow_fx_levels  { [player] = level }
-- 这样两个玩家同时开减速表不会在同一只怪身上叠两层特效。
--------------------------------------------------------------------------

local function BestFXLevel(levels)
	local best = 1
	for _, level in pairs(levels) do
		if level > best then
			best = level
		end
	end
	return best
end

local function AttachFX(player, target, level)
	local levels = target._wanda_slow_fx_levels
	if levels == nil then
		levels = {}
		target._wanda_slow_fx_levels = levels
	end
	levels[player] = level

	local fx = target._wanda_slow_fx
	if fx == nil or not fx:IsValid() then
		fx = SpawnPrefab("slingshotammo_slow_debuff_fx")
		if fx == nil then
			return
		end
		-- 与沃尔特减速弹一致：挂到目标身上再 StartFX，特效自动跟随目标
		fx.entity:SetParent(target.entity)
		fx:StartFX(target)
		target._wanda_slow_fx = fx
	end
	-- 档位 2（30%）用 1 级、档位 3（60%）用 2 级动画
	fx:SetFXLevel(BestFXLevel(levels))
end

local function DetachFX(player, target)
	local levels = target._wanda_slow_fx_levels
	if levels ~= nil then
		levels[player] = nil
		if next(levels) ~= nil then
			-- 还有别的玩家的减速表在影响它：等级降回去，特效保留
			local fx = target._wanda_slow_fx
			if fx ~= nil and fx:IsValid() then
				fx:SetFXLevel(BestFXLevel(levels))
			end
			return
		end
		target._wanda_slow_fx_levels = nil
	end

	local fx = target._wanda_slow_fx
	target._wanda_slow_fx = nil
	if fx ~= nil and fx:IsValid() then
		fx:KillFX()
	end
end

--------------------------------------------------------------------------
-- 服务端：光环本体（任务挂在玩家身上，与表在哪无关）
--------------------------------------------------------------------------

local function ReleaseAll(player)
	local targets = player._wanda_slow_watch_targets
	if targets == nil then
		return
	end
	for ent in pairs(targets) do
		if ent:IsValid() and ent.components.locomotor ~= nil then
			ent.components.locomotor:RemoveExternalSpeedMultiplier(player, MOD_KEY)
		end
		-- 目标已经消失（被打死/移除）时也要清：特效是它的子实体，不清会一直赖在原地
		DetachFX(player, ent)
		targets[ent] = nil
	end
end

local function StopAura(player)
	if player._wanda_slow_watch_task ~= nil then
		player._wanda_slow_watch_task:Cancel()
		player._wanda_slow_watch_task = nil
	end
	ReleaseAll(player)
end

local function UpdateAura(player)
	local tier = Age.GetSlowTier(player)
	local pct = Age.SlowPercent(tier)
	local targets = player._wanda_slow_watch_targets

	if pct <= 0 or not player:IsValid() or player:HasTag("playerghost") then
		-- 关闭 / 幽灵（死后不再减速，复活后下一轮自动恢复，任务不停）
		if targets ~= nil then
			ReleaseAll(player)
		end
		return
	end

	if targets == nil then
		targets = {}
		player._wanda_slow_watch_targets = targets
	end

	local mult = 1 - pct
	local level = tier - 1 -- 档位 2 → 1 级特效，档位 3 → 2 级

	local x, y, z = player.Transform:GetWorldPosition()
	local ents = TheSim:FindEntities(x, y, z, TUNING.BATTLESONG_ATTACH_RADIUS, FIND_MUST_TAGS, FIND_CANT_TAGS)
	local seen = {}
	for _, ent in ipairs(ents) do
		if IsHostileTarget(player, ent) then
			seen[ent] = true
			-- 同一玩家同一 key 是覆盖而非相乘；档位变了这里会直接改成新倍率
			ent.components.locomotor:SetExternalSpeedMultiplier(player, MOD_KEY, mult)
			AttachFX(player, ent, level)
			targets[ent] = true
		end
	end

	-- 离开范围 / 不再敌对 / 已消失的：立刻恢复速度并清掉特效
	for ent in pairs(targets) do
		if not seen[ent] then
			if ent:IsValid() and ent.components.locomotor ~= nil then
				ent.components.locomotor:RemoveExternalSpeedMultiplier(player, MOD_KEY)
			end
			-- 目标死了也要清特效（它是目标的子实体，不会跟着自动删）
			DetachFX(player, ent)
			targets[ent] = nil
		end
	end
end

-- 档位 > 1 时保证光环任务在跑；= 1 时停掉并立刻恢复
local function ApplyAura(player)
	if Age.SlowPercent(Age.GetSlowTier(player)) <= 0 then
		StopAura(player)
		return
	end

	if player._wanda_slow_watch_task == nil then
		player._wanda_slow_watch_task = player:DoPeriodicTask(UPDATE_PERIOD, UpdateAura, 0)
		-- 玩家离开世界（下线 / 换 shard）时把怪身上的减速与特效清掉，
		-- 否则特效实体没有主人，会一直挂在怪身上
		if player._wanda_slow_watch_cleanup_hooked == nil then
			player._wanda_slow_watch_cleanup_hooked = true
			player:ListenForEvent("onremove", function()
				StopAura(player)
			end)
		end
	end

	UpdateAura(player)
end

--------------------------------------------------------------------------
-- 服务端：玩家状态 <-> 表的表现
--------------------------------------------------------------------------

-- 表的持有者（会穿过容器：在钟表袋/背包里也算这个玩家）；在地上时返回 nil
local function GetOwner(inst)
	local owner = inst.components.inventoryitem ~= nil
		and inst.components.inventoryitem:GetGrandOwner() or nil
	if owner ~= nil and owner:IsValid() and owner:HasTag("player") then
		return owner
	end
	return nil
end

local function SyncWatch(inst, player)
	local tier = Age.GetSlowTier(player)
	inst._tier = tier
	inst._is_on = tier > 1
	inst._tiernet:set(tier)
	-- 记下主人：这块表的缓存只对同一个玩家有“种回去”的价值（见 Refresh）
	inst._state_userid = player.userid
	inst:AddOrRemoveTag(ON_TAG, inst._is_on)
end

-- 玩家身上登记的减速表（含已丢到地上的：它们也要跟着玩家档位显示）
local function RefreshWatches(player)
	local watches = player._wanda_slow_watches
	if watches == nil then
		return
	end
	for watch in pairs(watches) do
		if watch:IsValid() then
			SyncWatch(watch, player)
		else
			watches[watch] = nil
		end
	end
end

-- 档位一变：刷所有同类表 + 重算光环
local function OnPlayerStateChanged(player)
	RefreshWatches(player)
	ApplyAura(player)
end
Age.AddApplier(OnPlayerStateChanged)

-- 从玩家名下摘掉一块表。
-- 摘掉后如果这个玩家**名下最后一块**减速表也没了（拆解 / 烧毁 / 被吞 / 送给别人），
-- 就按「没有表就不再持有该状态」把档位归 1（关闭）并立刻撤掉光环与粒子；
-- 丢到地上 / 放进背包或钟表袋**不**走这里（那些路径保留登记，效果保留）——
-- onremove 只在实体真被删除时触发（EntityScript:Remove），丢地上不会触发。
local function Unregister(inst)
	local player = inst._state_owner
	inst._state_owner = nil
	if player == nil or not player:IsValid() or player._wanda_slow_watches == nil then
		return
	end

	local watches = player._wanda_slow_watches
	watches[inst] = nil
	if next(watches) == nil then
		player._wanda_slow_watches = nil
		-- 最后一块没了：关掉档位，ApplyAura 会把光环任务、移速修饰器、粒子一起收干净
		Age.SetSlowTier(player, 1)
		Age.NotifyChanged(player)
	end
end

local function Register(inst, player)
	if inst._state_owner ~= nil and inst._state_owner ~= player then
		Unregister(inst)
	end
	inst._state_owner = player
	player._wanda_slow_watches = player._wanda_slow_watches or {}
	player._wanda_slow_watches[inst] = true
end

local function Refresh(inst)
	local player = GetOwner(inst)
	if player == nil then
		-- 不在任何人身上（丢地上 / 躺着地上的钟表袋里）：保留上一次的持有者与缓存
		return
	end

	local fresh_player = not player._wanda_planar_state_init
	Age.EnsurePlayer(player)
	if fresh_player then
		-- 本次会话第一次接触减速表。如果读档时玩家名下没有任何同类表（比如表都收在箱子里），
		-- 玩家的 OnSave 挂在当时根本没人装，存档里的档位不会被读回来 —— 这时用表自己的缓存种回去。
		-- 只在同一玩家（userid 一致）时种，避免把 A 的档位带给捡了 A 掉的表的 B。
		local cached = inst._tier or 1
		if cached > 1
			and (inst._state_userid == nil or inst._state_userid == player.userid)
			and Age.GetSlowTier(player) <= 1
		then
			Age.SetSlowTier(player, cached)
			Age.NotifyChanged(player)
		end
	end

	Register(inst, player)
	SyncWatch(inst, player)
	-- 玩家可能是这次会话第一次接触减速表（懒挂钩刚装好）：确保光环已按档位生效
	ApplyAura(player)
end

local function DoCastSpell(inst, doer)
	local player = doer
	if player == nil or not player:IsValid() or not player:HasTag("player") then
		player = GetOwner(inst)
	end
	if player == nil then
		return false
	end

	Age.EnsurePlayer(player)
	-- 循环切档：关闭 → 30% → 60% → 关闭
	Age.SetSlowTier(player, (Age.GetSlowTier(player) % Age.SLOW_TIER_COUNT) + 1)
	Age.NotifyChanged(player)

	if doer ~= nil and doer.components ~= nil and doer.components.talker ~= nil then
		local pct = Age.SlowPercent(Age.GetSlowTier(player))
		doer.components.talker:Say(pct > 0
			and string.format("减速表：%d%%", math.floor(pct * 100 + 0.5))
			or "减速表：已停用")
	end
	return true
end

local function OnSave(inst, data)
	data.tier = inst._tier
	data.userid = inst._state_userid
end

local function OnLoad(inst, data)
	if data ~= nil and data.tier ~= nil then
		inst._tier = Age.SLOW_TIERS[data.tier] ~= nil and data.tier or 1
		inst._is_on = inst._tier > 1
		if inst._tiernet ~= nil then
			inst._tiernet:set(inst._tier)
		end
		inst:AddOrRemoveTag(ON_TAG, inst._is_on)
	end
	if data ~= nil then
		inst._state_userid = data.userid
	end
	Refresh(inst)
end

local function master_postinit(inst)
	inst.components.inventoryitem.atlasname = "images/inventoryimages/wanda_slow_watch.xml"
	inst.components.inventoryitem.imagename = "wanda_slow_watch"

	inst.components.pocketwatch.DoCastSpell = DoCastSpell

	inst.OnSave = OnSave
	inst.OnLoad = OnLoad

	inst:ListenForEvent("onputininventory", Refresh)
	inst:ListenForEvent("onownerputininventory", Refresh)
	inst:ListenForEvent("ondropped", Refresh)
	inst:ListenForEvent("onownerdropped", Refresh)
	inst:ListenForEvent("onremove", Unregister)

	inst:DoTaskInTime(0, Refresh)
end

local function fn()
	-- cast_from_inventory = true：右键切档（原版 CAST_POCKETWATCH 只在物品栏提供该动作）
	local inst = PocketWatchCommon.common_fn("wanda_slow_watch", "wanda_slow_watch", DoCastSpell, true,
		nil, common_postinit, master_postinit)
	return inst
end

return Prefab("wanda_slow_watch", fn, assets, prefabs)
