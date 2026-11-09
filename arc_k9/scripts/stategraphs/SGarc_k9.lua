-- 护卫犬 K-9 状态图：eyeofterror_mini bank（悬浮眼球，SGcritter_common 动画名：
-- idle_loop / walk_pre / walk_loop / walk_pst，SGcritter_common.lua:59/481/502/517）。
-- 极简 locomote + arrive 出场 FX 在 prefab 侧；无攻击态——伤害由周期任务直调 DoAttack
-- （绕开 SG），攻击永不打断移动。
-- 坑档案（spec §4）：onenter 必须无错（报错会卡死 busy 态）；run 态必须调 RunForward 挂电机。

local events =
{
	EventHandler("locomote", function(inst)
		if not inst.sg:HasStateTag("busy") and inst.components.locomotor ~= nil then
			local moving = inst.components.locomotor:WantsToMoveForward()
			if moving and not inst.sg:HasStateTag("moving") then
				inst.sg:GoToState("walk_start")
			elseif not moving and inst.sg:HasStateTag("moving") then
				inst.sg:GoToState("walk_stop")
			end
		end
	end),
}

local states =
{
	State{
		name = "idle",
		tags = { "idle", "canrotate" },

		onenter = function(inst)
			inst.AnimState:PlayAnimation("idle_loop", true)
			inst.components.locomotor:StopMoving()
		end,
	},

	State{
		name = "walk_start",
		tags = { "moving", "running", "canrotate" },

		onenter = function(inst)
			if inst.AnimState:AnimDone() or inst.AnimState:GetCurrentAnimationLength() == 0 then
				inst.sg:GoToState("walk")
			else
				inst.components.locomotor:RunForward()
				inst.AnimState:PlayAnimation("walk_pre")
			end
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg:GoToState("walk")
				end
			end),
		},
	},

	State{
		name = "walk",
		tags = { "moving", "running", "canrotate" },

		onenter = function(inst)
			inst.components.locomotor:RunForward() -- 真正驱动移动（CommonStates 同款，spec §4 坑 2）
			inst.AnimState:PlayAnimation("walk_loop", true)
		end,
	},

	State{
		name = "walk_stop",
		tags = { "idle", "canrotate" },

		onenter = function(inst)
			inst.components.locomotor:StopMoving()
			inst.AnimState:PlayAnimation("walk_pst")
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg:GoToState("idle")
				end
			end),
		},
	},
}

return StateGraph("SGarc_k9", states, events, "idle")
