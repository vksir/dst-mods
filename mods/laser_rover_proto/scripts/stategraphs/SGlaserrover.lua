-- 激光犬状态图：搬 SGwx78_drone_zap 的动画（idle/run_*/atk_*），简化为 locomotor 驱动 + 即时命中攻击
-- attack state：timeline 第 6 帧生成激光 FX + combat:DoAttack（无武器 ⇒ 当帧结算，research/02 §5.3）
-- 注意：不做面向（FaceTarget 不是组件方法，原版攻击态也不做面向；激光指向由 FX 数学计算）

local RADIANS = 180 / math.pi

local function SpawnBeam(inst, target)
	if target == nil or not target:IsValid() then
		return
	end
	local x1, _, z1 = inst.Transform:GetWorldPosition()
	local x2, _, z2 = target.Transform:GetWorldPosition()
	local dx, dz = x2 - x1, z2 - z1
	local fx = SpawnPrefab("laser_rover_beam")
	fx.Transform:SetPosition((x1 + x2) * .5, 0, (z1 + z2) * .5)
	fx.Transform:SetRotation(math.atan2(-dz, dx) * RADIANS) -- 全 DST 通用朝向公式
	fx:SetBeam(math.sqrt(dx * dx + dz * dz))
end

local events =
{
	EventHandler("locomote", function(inst)
		if not inst.sg:HasStateTag("busy") and inst.components.locomotor ~= nil then
			local moving = inst.components.locomotor:WantsToMoveForward()
			if moving and not inst.sg:HasStateTag("moving") then
				inst.sg:GoToState("run_start")
			elseif not moving and inst.sg:HasStateTag("moving") then
				inst.sg:GoToState("run_stop")
			end
		end
	end),
	EventHandler("doattack", function(inst, data)
		if not inst.sg:HasStateTag("busy") and inst.components.combat ~= nil then
			local target = (data ~= nil and data.target or nil) or inst.components.combat.target
			if target ~= nil and target:IsValid() then
				inst.sg:GoToState("attack", target)
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
			inst.Transform:SetNoFaced()
			inst.AnimState:PlayAnimation("idle", true)
			inst.components.locomotor:StopMoving()
		end,
	},

	State{
		name = "run_start",
		tags = { "moving", "running", "canrotate" },

		onenter = function(inst)
			inst.Transform:SetFourFaced()
			inst.components.locomotor:RunForward() -- 真正驱动移动的调用（CommonStates 同款）
			inst.AnimState:PlayAnimation("run_pre")
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg.statemem.running = true
					inst.sg:GoToState("run")
				end
			end),
		},

		onexit = function(inst)
			if not inst.sg.statemem.running then
				inst.Transform:SetNoFaced()
			end
		end,
	},

	State{
		name = "run",
		tags = { "moving", "running", "canrotate" },

		onenter = function(inst)
			inst.Transform:SetFourFaced()
			inst.components.locomotor:RunForward() -- CommonStates 每次进 run 都重申
			inst.AnimState:PlayAnimation("run_loop", true)
		end,

		onexit = function(inst)
			if not inst.sg.statemem.running then
				inst.Transform:SetNoFaced()
			end
		end,
	},

	State{
		name = "run_stop",
		tags = { "idle", "canrotate" },

		onenter = function(inst)
			inst.components.locomotor:StopMoving()
			inst.Transform:SetFourFaced()
			inst.AnimState:PlayAnimation("run_pst")
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg:GoToState("idle")
				end
			end),
		},

		onexit = function(inst)
			inst.Transform:SetNoFaced()
		end,
	},

	State{
		name = "attack",
		tags = { "attack", "busy" },

		onenter = function(inst, target)
			inst.components.locomotor:Stop()
			inst.components.combat:StartAttack()
			inst.AnimState:PlayAnimation("atk_pre")
			inst.AnimState:PushAnimation("atk")
			inst.AnimState:PushAnimation("atk_pst", false)
			inst.SoundEmitter:PlaySound("rifts5/wagdrone_stationary/beep_hurt")
			inst.sg.statemem.target = target -- 面向交给激光 FX 的数学计算
		end,

		timeline =
		{
			TimeEvent(6 * FRAMES, function(inst)
				local target = inst.sg.statemem.target
				if target ~= nil and target:IsValid() then
					SpawnBeam(inst, target)
					inst.components.combat:DoAttack(target) -- 即时命中：当帧结算
				end
			end),
		},

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

return StateGraph("laser_rover", states, events, "idle")
