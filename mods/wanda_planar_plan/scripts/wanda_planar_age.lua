-- 档位 / 玩家级状态 / 老化速率（加速表、减速表共用）
--
-- 环境：本文件是被 require 的普通模块，跑在 _G 里（docs/dst-modding-pitfalls.md §13）：
--   GLOBAL 代理不存在、mod API（AddPlayerPostInit / AddPrefabPostInit）不可用，
--   print / math / table / setmetatable 等可以裸写。
--   名字带 wanda_planar_ 前缀：mods.lua:528 会把每个 mod 的 scripts/ 都塞进 package.path，
--   通用的名字（如 wanda_age）可能被别的 mod 的同名文件抢先生效。
--
-- 设计（v4 需求 5）：**档位是玩家属性，不是物品属性。表只是遥控器。**
--   player._wanda_haste_tier  1..3（0% / 30% / 50%）
--   player._wanda_slow_tier   1..3（关闭 / 30% / 50%）
--   - 效果（移动速度、老化、减速光环）全部挂在玩家身上，与表在背包 / 钟表袋 / 地上无关；
--   - 同一个玩家的所有同类表读到同一个档位（丢到地上再捡起来也是同一份状态）；
--   - 但「没有表就不再持有该状态」：名下**最后一块**同类表被删除（拆解 / 烧毁 / 被吞）
--     或送给了别人时，档位归 1 并撤掉效果（两个 prefab 的 Unregister 负责）；
--     丢到地上 / 放进背包或钟表袋**不算消失**（登记保留，效果保留）。
--   - 物品上的 _tier / _is_on 只是"玩家状态的缓存"，只用于显示名与 tag（契约 wanda_watch_on）。
--
-- 落库：玩家实体 OnSave / OnLoad 里存这两个字段（见 EnsurePlayer）。
--   ⚠️ 为什么不用 AddPlayerPostInit：scripts/ 下的 prefab 文件由
--   mainfunctions.LoadPrefabFile 以 **_G 环境**加载（mods.lua:646 直接引用全局
--   LoadPrefabFile），拿不到 AddPlayerPostInit 这类 modmain 环境注入的接口。
--   所以改成“首次接触即安装”的懒挂钩，并且在读档时依然赶得上：
--     components/inventory.lua:293 Inventory:OnLoad 先把背包物品放回去（触发
--     onputininventory → EnsurePlayer 装挂钩），EntityScript:SetPersistData
--     在**所有组件 OnLoad 之后**才调用 inst.OnLoad（entityscript.lua:1992→2011）。
--   代价：读档时如果玩家名下（含钟表袋/背包、不包括箱子）一块同类表都没有，这一轮就没人
--   来装挂钩。两个 prefab 在 Refresh 里对此做了兼容：玩家第一次接触表且身上还是空档时，
--   用这块表自己的存档缓存（_tier）把状态种回去 —— 只用 userid 一致的（别人丢下的表不认），
--   避免把前一个主人的档位带过来。
--   想让挂钩在玩家出生时就装好（彻底避开上面的边角），可以请 w-main 在 modmain 里加一行：
--     AddPlayerPostInit(function(inst)
--         if GLOBAL.TheWorld ~= nil and GLOBAL.TheWorld.ismastersim then
--             GLOBAL.require("wanda_planar_age").EnsurePlayer(inst)
--         end
--     end)
--   EnsurePlayer 是幂等的，和懒挂钩重复调用没有副作用（见 pending-tests.md）。
--
-- oldager.rate 是旺达的老化倍率字段（components/oldager.lua:13，逐帧乘在 base_rate 上）。
-- 多件物品都要改它，各自直写会互相覆盖，所以统一从这里算。
-- v7 需求：两种表的老化加速**加算叠加**（不是相乘）：
--     rate = 1 + 加速档位 + 减速档位
--   例：加速表 50% + 减速表 50% → rate = 2.0（老化时间加快 100%）。

local Age = {}

-- 档位表：下标即档位（1 起）。1 档 = 关闭。
Age.HASTE_TIERS = { 0, 0.30, 0.50 } -- v7 需求：0% / 30% / 50%（只有两档）
Age.SLOW_TIERS = { 0, 0.30, 0.50 }  -- v7 需求：关闭 / 减速 30% / 减速 50%
Age.HASTE_TIER_COUNT = #Age.HASTE_TIERS
Age.SLOW_TIER_COUNT = #Age.SLOW_TIERS

local function ClampTier(value, count)
	value = tonumber(value)
	if value == nil then
		return nil
	end
	value = math.floor(value)
	if value < 1 then
		return 1
	elseif value > count then
		return count
	end
	return value
end

function Age.GetHasteTier(player)
	return (player ~= nil and ClampTier(player._wanda_haste_tier, Age.HASTE_TIER_COUNT)) or 1
end

function Age.GetSlowTier(player)
	return (player ~= nil and ClampTier(player._wanda_slow_tier, Age.SLOW_TIER_COUNT)) or 1
end

-- 只写字段，不派发效果：改动后由调用方统一 Age.NotifyChanged，避免一次切换跑两遍
function Age.SetHasteTier(player, tier)
	local t = ClampTier(tier, Age.HASTE_TIER_COUNT) or 1
	if player ~= nil then
		player._wanda_haste_tier = t
	end
	return t
end

function Age.SetSlowTier(player, tier)
	local t = ClampTier(tier, Age.SLOW_TIER_COUNT) or 1
	if player ~= nil then
		player._wanda_slow_tier = t
	end
	return t
end

function Age.HastePercent(tier)
	return Age.HASTE_TIERS[tier] or 0
end

function Age.SlowPercent(tier)
	return Age.SLOW_TIERS[tier] or 0
end

--------------------------------------------------------------------------
-- 效果派发：档位一变，就重算"所有登记过的表的表现" + "玩家身上的效果"
--
-- 每个钟表 prefab 在加载时登记自己的 applier（Age.AddApplier），
-- 由本模块负责在 状态变化 / 读档 / 玩家首次接触表 时统一调用。
--------------------------------------------------------------------------

local appliers = {}
local applier_set = {}

function Age.AddApplier(fn)
	if fn == nil or applier_set[fn] then
		return
	end
	applier_set[fn] = true
	table.insert(appliers, fn)
end

function Age.NotifyChanged(player)
	if player == nil or not player:IsValid() then
		return
	end
	for i = 1, #appliers do
		appliers[i](player)
	end
	Age.RefreshOldAge(player)
end

-- 只有旺达有 oldager（components/oldager.lua），其他角色调用是空操作
function Age.RefreshOldAge(player)
	local components = player ~= nil and player.components or nil
	local oldager = components ~= nil and components.oldager or nil
	if oldager == nil then
		return
	end

	local haste = Age.HastePercent(Age.GetHasteTier(player))
	local slow = Age.SlowPercent(Age.GetSlowTier(player))
	-- 加算叠加（v7 需求）：50% + 50% → 2.0，即老化加快 100%
	oldager.rate = 1 + haste + slow
end

--------------------------------------------------------------------------
-- 玩家状态初始化 + 存档（幂等，可以反复调用）
--------------------------------------------------------------------------

function Age.EnsurePlayer(player)
	if player == nil or not player:IsValid() or not player:HasTag("player") then
		return nil
	end
	if player._wanda_planar_state_init then
		return player
	end
	player._wanda_planar_state_init = true

	player._wanda_haste_tier = ClampTier(player._wanda_haste_tier, Age.HASTE_TIER_COUNT) or 1
	player._wanda_slow_tier = ClampTier(player._wanda_slow_tier, Age.SLOW_TIER_COUNT) or 1

	-- 合并而不是覆盖：player_common 自己也挂了 OnSave / OnLoad（prefabs/player_common.lua:2937），
	-- 先留旧函数的引用，两个都跑，旧函数的返回值（引用表）原样传回去。
	local OldOnSave = player.OnSave
	player.OnSave = function(inst, data)
		local refs = OldOnSave ~= nil and OldOnSave(inst, data) or nil
		if data ~= nil then
			data.wanda_haste_tier = inst._wanda_haste_tier
			data.wanda_slow_tier = inst._wanda_slow_tier
		end
		return refs
	end

	local OldOnLoad = player.OnLoad
	player.OnLoad = function(inst, data)
		if OldOnLoad ~= nil then
			OldOnLoad(inst, data)
		end
		if data ~= nil then
			inst._wanda_haste_tier = ClampTier(data.wanda_haste_tier, Age.HASTE_TIER_COUNT) or Age.GetHasteTier(inst)
			inst._wanda_slow_tier = ClampTier(data.wanda_slow_tier, Age.SLOW_TIER_COUNT) or Age.GetSlowTier(inst)
		end
		-- 读到档位后立刻把效果装回去（移速 / 老化 / 减速光环），不等玩家再去碰表
		Age.NotifyChanged(inst)
	end

	-- 首次接触（新捡起一块表、或读档时背包物品先一步归位）：按当前档位装效果
	Age.NotifyChanged(player)
	return player
end

return Age
