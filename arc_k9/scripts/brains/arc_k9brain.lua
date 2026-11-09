-- 护卫犬 K-9 脑（05 实测定稿：炮台语义）：
--   Follow（贴身 1/3/5，永远最高优先）→ StandStill
-- 无追击节点：狗不贴敌不追击，电弧由 prefab 侧周期任务在射程内自动结算
-- （Abigail aura 模式，research/01 §4.3；伤害与索敌全在 combat 组件层）。

require "behaviours/follow"
require "behaviours/standstill"

local FOLLOW_MIN = 2    -- 实测反馈 3：时刻跟随但别太近（1 → 2，停下时离玩家至少 2 格）
local FOLLOW_TARGET = 4
local FOLLOW_MAX = 6

local function GetLeader(inst)
	return inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
end

local ArcK9Brain = Class(Brain, function(self, inst)
	Brain._ctor(self, inst)
end)

function ArcK9Brain:OnStart()
	local root = PriorityNode(
	{
		WhileNode(function() return GetLeader(self.inst) ~= nil end, "有主人 → 贴身跟随",
			Follow(self.inst, GetLeader, FOLLOW_MIN, FOLLOW_TARGET, FOLLOW_MAX, true)),
		StandStill(self.inst),
	}, .25)

	self.bt = BT(self.inst, root)
end

return ArcK9Brain
