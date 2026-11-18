-- 加速表 / Haste Watch
--
-- 档位：0% / 30% / 50% / 100%（v4 需求 7），右键循环切换。
--
-- 档位存在**玩家**身上（v4 需求 5）：player._wanda_haste_tier，详见 scripts/wanda_planar_age.lua。
-- 本文件里的 inst._tier / inst._is_on 只是玩家状态的缓存 —— 用于显示名、tag（契约 wanda_watch_on）
-- 与存档，丢了也能从玩家身上重新读回来。效果（移速 + 老化）挂在玩家身上，
-- 所以表丢到地上 / 放进钟表袋都照样生效，同玩家的所有加速表共享同一个档位。
-- 反向的兜底（D2 裁决）：「没有表就不再持有该状态」—— 名下最后一块加速表被拆解 / 烧毁 / 被吞
-- 或送给别人时（onremove / 换主人），档位归 1 并撤掉移速与老化；丢地上不算（登记保留）。
--
-- 移速：LocoMotor:SetExternalSpeedMultiplier(source, key, m)（components/locomotor.lua:490）
--       source 用玩家、key 用 "wanda_haste_watch"，同玩家的多块表天然只有一份修饰器。
-- 老化：oldager.rate，由 wanda_planar_age 统一合成（加速 × 减速）。

local assets =
{
	-- 骨架（bank "pocketwatch"）与外观（build）是两份资源，原版 pocketwatch.lua 同样两个都声明；
	-- 只声明 build 时，没加载过原版钟表的客户端会 SetBank 失败 → 物品不可见
	-- 自定义地面外观（tools/gen_item_build.py 用官方 scml 编译器生成）
	Asset("ANIM", "anim/wanda_haste_watch.zip"),
	-- 物品栏图标：必须显式声明 ATLAS + IMAGE。
	-- Asset("INV_IMAGE", "名字") 是给原版图集用的：mainfunctions.lua:96 的 ShouldIgnoreResolve
	-- 会把 INV_IMAGE 的文件名原样（不带 mod 路径）交给引擎，引擎只在原版 inventoryimages1~4
	-- 里找，找不到就不会加载任何资源 → 渲染时报 "Invalid resource handle for atlas
	-- '../mods/<mod>/images/inventoryimages/x.xml', did you remember to load the asset?"，图标空白。
	Asset("ATLAS", "images/inventoryimages/wanda_haste_watch.xml"),
	Asset("IMAGE", "images/inventoryimages/wanda_haste_watch.tex"),
}

local prefabs = {}

local PocketWatchCommon = require("prefabs/pocketwatch_common")
local Age = require("wanda_planar_age")

local TIERS = Age.HASTE_TIERS
local MOD_KEY = "wanda_haste_watch"
local ON_TAG = "wanda_watch_on"

-- 需求 1（地面/手持外观与溯源表区分）：工程量最小的做法是乘法着色，不新增 anim build
-- （仓库里没有 Spriter / 编译链，anim/*.zip 造不出来）。
-- SetMultColour 是渲染属性，地面、手持、装备栏（世界内模型）都吃这套，不需要额外同步。
-- 配色以 .scratch/wanda-planar-plan/v4/palette.md §1 为准（已对齐 w-art 定稿）。
local TINT = { 0.40, 1.00, 0.86 } -- 薄荷青绿（w-art 定稿 palette.md §1）

--------------------------------------------------------------------------
-- 两端都要跑的部分（客户端也要正确显示名字 / 颜色）
--------------------------------------------------------------------------

local function DisplayName(inst)
	-- 客户端拿不到服务端的 _tier 字段，档位靠 net_byte 同步（见 common_postinit）
	local tier = inst._tiernet ~= nil and inst._tiernet:value() or inst._tier or 1
	local pct = Age.HastePercent(tier)
	local base = STRINGS.NAMES.WANDA_HASTE_WATCH or inst.name or "加速表"
	if pct > 0 then
		-- 需求（v5）：加速表激活时名字变成「加速表 30%」（空格分隔，不带横杠）
		return string.format("%s %d%%", base, math.floor(pct * 100 + 0.5))
	end
	return base
end

local function common_postinit(inst)
	-- 档位同步给客户端（显示名要用）。net_byte 必须在 SetPristine 之前建好。
	inst._tiernet = net_byte(inst.GUID, "wanda_haste_watch.tier", "wanda_haste_watchtierdirty")
	inst._tier = 1
	inst._is_on = false

	-- 用 displaynamefn 而不是直接覆盖 GetDisplayName：
	-- GetBasicDisplayName（entityscript.lua:687）优先取它，外层 GetAdjectivedName 的
	-- 潮湿/破损等形容词逻辑仍然保留。
	inst.displaynamefn = DisplayName

	-- 已有独立 build（青绿表盘），不再需要着色
	if TINT ~= nil then inst.AnimState:SetMultColour(1, 1, 1, 1) end

	-- 施法特效颜色：客户端预测的施法特效也要用这个颜色（见 slow_watch 的同款注释）
	inst.castfxcolour = { 136 / 255, 235 / 255, 214 / 255 }
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

-- 把玩家当前档位写进这块表（缓存 + 客户端 net 变量 + tag）
local function SyncWatch(inst, player)
	local tier = Age.GetHasteTier(player)
	inst._tier = tier
	inst._is_on = tier > 1
	inst._tiernet:set(tier)
	-- 记下主人：这块表的缓存只对同一个玩家有“种回去”的价值（见 Refresh）
	inst._state_userid = player.userid
	-- 契约：状态变化时同步 tag（tag 本身会同步到客户端，w-main 的右键文案读它）
	inst:AddOrRemoveTag(ON_TAG, inst._is_on)
end

-- 玩家身上登记的加速表（含已丢到地上的：它们也要跟着玩家档位显示）
local function RefreshWatches(player)
	local watches = player._wanda_haste_watches
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

-- 玩家身上的实际效果：移速（老化由 Age.RefreshOldAge 统一算）
local function ApplySpeed(player)
	local locomotor = player.components ~= nil and player.components.locomotor or nil
	if locomotor == nil then
		return
	end
	local pct = Age.HastePercent(Age.GetHasteTier(player))
	if pct > 0 then
		locomotor:SetExternalSpeedMultiplier(player, MOD_KEY, 1 + pct)
	else
		locomotor:RemoveExternalSpeedMultiplier(player, MOD_KEY)
	end
end

-- 档位一变：刷所有同类表 + 重算玩家效果
local function OnPlayerStateChanged(player)
	RefreshWatches(player)
	ApplySpeed(player)
end
Age.AddApplier(OnPlayerStateChanged)

-- 从玩家名下摘掉一块表。
-- 摘掉后如果这个玩家**名下最后一块**加速表也没了（拆解 / 烧毁 / 被吞 / 送给别人），
-- 就按「没有表就不再持有该状态」把档位归 1 并撤掉效果；
-- 丢到地上 / 放进背包或钟表袋**不**走这里（那些路径保留登记，效果保留）——
-- onremove 只在实体真被删除时触发（EntityScript:Remove），丢地上不会触发。
local function Unregister(inst)
	local player = inst._state_owner
	inst._state_owner = nil
	if player == nil or not player:IsValid() or player._wanda_haste_watches == nil then
		return
	end

	local watches = player._wanda_haste_watches
	watches[inst] = nil
	if next(watches) == nil then
		player._wanda_haste_watches = nil
		-- 最后一块没了：关掉档位（移速 / 老化一起回 1）
		Age.SetHasteTier(player, 1)
		Age.NotifyChanged(player)
	end
end

local function Register(inst, player)
	if inst._state_owner ~= nil and inst._state_owner ~= player then
		-- 换主人：从旧玩家的登记表里摘掉，档位改为跟随新玩家
		Unregister(inst)
	end
	inst._state_owner = player
	player._wanda_haste_watches = player._wanda_haste_watches or {}
	player._wanda_haste_watches[inst] = true
end

-- 进背包 / 出背包 / 换手 / 读档时重算这块表"跟谁走"
local function Refresh(inst)
	local player = GetOwner(inst)
	if player == nil then
		-- 不在任何人身上（丢地上，或躺在地上的钟表袋里）：保留上一次的持有者与缓存，
		-- 效果本来就在玩家身上，名称 / tag 也继续跟着那个玩家的档位走。
		return
	end

	local fresh_player = not player._wanda_planar_state_init
	Age.EnsurePlayer(player)
	if fresh_player then
		-- 本次会话第一次接触加速表。如果读档时玩家名下没有任何同类表（比如表都收在箱子里），
		-- 玩家的 OnSave 挂在当时根本没人装，存档里的档位不会被读回来 —— 这时用表自己的缓存种回去。
		-- 只在同一玩家（userid 一致）时种，避免把 A 的档位带给捡了 A 掉的表的 B。
		local cached = inst._tier or 1
		if cached > 1
			and (inst._state_userid == nil or inst._state_userid == player.userid)
			and Age.GetHasteTier(player) <= 1
		then
			Age.SetHasteTier(player, cached)
			Age.NotifyChanged(player)
		end
	end

	Register(inst, player)
	SyncWatch(inst, player)
	-- 玩家可能是这次会话第一次接触加速表（懒挂钩刚装好）：确保效果已按档位生效
	ApplySpeed(player)
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
	-- 循环切档：0% → 30% → 50% → 100% → 0%
	Age.SetHasteTier(player, (Age.GetHasteTier(player) % #TIERS) + 1)
	Age.NotifyChanged(player)

	if doer ~= nil and doer.components ~= nil and doer.components.talker ~= nil then
		local pct = Age.HastePercent(Age.GetHasteTier(player))
		doer.components.talker:Say(pct > 0
			and string.format("加速表：%d%%", math.floor(pct * 100 + 0.5))
			or "加速表：已停用")
	end
	return true
end

local function OnSave(inst, data)
	-- 只是缓存：读档后如果玩家就在旁边，Refresh 会用玩家身上的档位把它覆盖掉
	data.tier = inst._tier
	data.userid = inst._state_userid
end

local function OnLoad(inst, data)
	if data ~= nil and data.tier ~= nil then
		inst._tier = Age.HASTE_TIERS[data.tier] ~= nil and data.tier or 1
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
	inst.components.inventoryitem.atlasname = "images/inventoryimages/wanda_haste_watch.xml"
	inst.components.inventoryitem.imagename = "wanda_haste_watch"

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
	local inst = PocketWatchCommon.common_fn("wanda_haste_watch", "wanda_haste_watch", DoCastSpell, true,
		nil, common_postinit, master_postinit)
	return inst
end

return Prefab("wanda_haste_watch", fn, assets, prefabs)
