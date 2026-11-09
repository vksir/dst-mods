-- 激光犬脑（research/02 §5.1：索敌在 combat 组件层，脑只两个动作节点）
-- 结构 = Abigail 式：ChaseAndAttack（有目标）→ Follow（有主人）→ StandStill

require "behaviours/follow"
require "behaviours/chaseandattack"
require "behaviours/standstill"

local FOLLOW_MIN = 0    -- 贴身
local FOLLOW_TARGET = 5 -- 舒适距离
local FOLLOW_MAX = 10   -- 超过即追

local function GetLeader(inst)
	return inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
end

local LaserRoverBrain = Class(Brain, function(self, inst)
	Brain._ctor(self, inst)
end)

function LaserRoverBrain:OnStart()
	-- 诊断（原型阶段）：确认脑已启动且 leader 已绑定
	print(string.format("[laser_rover] brain start, leader=%s", tostring(GetLeader(self.inst))))

	local root = PriorityNode(
	{
		WhileNode(function() return self.inst.components.combat.target ~= nil end, "有目标 → 攻击",
			ChaseAndAttack(self.inst, 10)),
		WhileNode(function() return GetLeader(self.inst) ~= nil end, "有主人 → 跟随",
			Follow(self.inst, GetLeader, FOLLOW_MIN, FOLLOW_TARGET, FOLLOW_MAX)),
		StandStill(self.inst),
	}, .25)

	self.bt = BT(self.inst, root)
end

return LaserRoverBrain
