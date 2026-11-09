-- 护卫犬 K-9 本体（4 形态共享 commonfn）：
--   arc_k9        基础（伤害 68）
--   arc_k9_crown  启迪（伤害 142）
--   arc_k9_spark  火花（伤害 68 + 位面 68）
--   arc_k9_apex   终阶（伤害 142 + 位面 68）
--
-- 核心机制（出处见 .scratch/arc-k9/research/01~03 与实测迭代记录）：
-- · 炮台语义（05 实测定稿）：狗永远贴主人（brain 只有 Follow），不追击不贴敌，
--   电弧由周期任务在射程内结算（Abigail aura 模式，research/01 §4.3）；
-- · 索敌双通道（06 实测反馈）：monster/hostile tag（主动敌）+ 正在攻击主人/主人宠物的
--   单位（威胁，不限阵营 tag——中立生物反击也打）；
-- · 射程 = 眼球塔 TUNING.EYETURRET_RANGE（15，实测反馈 5）；
-- · 视觉弹道（实测反馈 6）：自制 arc_k9_shot 视觉弹（直线飞行追踪 + 眼塔命中 FX），
--   伤害仍即时结算；主跳从狗发源，连锁跳从上一目标发源。
--   ⚠ 两个引擎崩教训（实测迭代 2/3）：Transform:SetPosition 缺参引擎崩且无 Lua 堆栈
--   （三值必须完整展开）；projectile:Hit 内建把弹体当 weapon 传 DoAttack，无 weapon
--   组件的弹体在 CalcDamage:891 崩——纯视觉弹勿挂 projectile 组件；
-- · 形态（实测反馈 7 修订）：悬浮眼球构造体 = eyeofterror_mini（官方浮游眼球宠物
--   critter_eyeofterror 同款，prefabs/critters.lua:384）+ 蓝白月亮化染色 + 眼塔攻击弹，
--   视觉主题全自洽；六向 SetSixFaced（critters.lua face=6）；
-- · 电弧连锁：DoAttack(targ,nil,nil,"electric",衰减)，潮湿加成干 1.5x/湿 2.5x 内建
--   （combat.lua:1198-1213）；位面伤害走 planardamage 组件（research/03 §3）。

local assets = {
	Asset("ANIM", "anim/eyeofterror_mini_basic.zip"),  -- 悬浮眼球本体（bank eyeofterror_mini）
	Asset("ANIM", "anim/eyeball_turret_attack.zip"),   -- 视觉弹道（eye_charge）
}

local prefabs = {
	"arc_k9_shot",
	"electrichitsparks",
	"eyeofterror_arrive_fx",
	"eye_charge_hit",
}

---------------------------------------------------------------------
-- 参数表（一处调参；68 = 黑剑档 wilson×2，research/03 §3.5）
---------------------------------------------------------------------

local CFG = {
	ARC_PERIOD = 2,     -- 电弧结算周期（秒）＝攻击冷却（aura 式，research/01 §2.4 方案 a）
	CHAIN_HOPS = 3,     -- 主目标之后的连锁跳数
	CHAIN_RANGE = 7,    -- 每跳的搜索半径（从上一目标出发）
	HOP_DECAY = 0.7,    -- 每跳伤害系数（instancemult：1 → 0.7 → 0.49 → 0.343）
	HOP_DELAY = 11,     -- 跳间隔（帧），照抄 ELECTROCUTE_FORK_DELAY（tuning.lua:8661）
	ATTACK_RANGE = 15,  -- 放电射程 = 眼球塔 TUNING.EYETURRET_RANGE（实测反馈 5）
	RETARGET_PERIOD = 1,
	SCAN_RANGE = 15,    -- 索敌半径（以狗为中心，FindEntities 按距离升序取最近）
	MASTER_RANGE = 15,  -- 目标距主人上限（超出即丢目标，保证狗跟主人走）
	RUN_SPEED = 8,      -- 实测反馈 3：快于玩家 6、慢于骑牛 9
	WALK_SPEED = 4,
}

-- 4 形态参数（defaultdamage 与 planardamage 分开配，research/03 §3.4）
local TIERS = {
	[1] = { prefab = "arc_k9", damage = 68, planar = 0 },        -- 基础
	[2] = { prefab = "arc_k9_crown", damage = 142, planar = 0 }, -- 启迪
	[3] = { prefab = "arc_k9_spark", damage = 68, planar = 68 }, -- 火花
	[4] = { prefab = "arc_k9_apex", damage = 142, planar = 68 }, -- 终阶
}

-- 索敌过滤（cant：不打玩家/护卫/猎物/昆虫等）
local RETARGET_MUST_TAGS = { "_combat", "_health" }
local RETARGET_CANT_TAGS = { "INLIMBO", "player", "companion", "notarget", "noattack", "prey", "insect" }

-- 连锁跳过滤（照抄 DoFork 的 NOPVP 集合 + 护卫补充，electrocute_fx.lua:45-46）
local HOP_MUST_TAGS = { "_combat", "_health" }
local HOP_CANT_TAGS = { "INLIMBO", "flight", "invisible", "notarget", "noattack", "FX", "player", "wall", "structure", "companion" }

local function GetMaster(inst)
	return inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
end

---------------------------------------------------------------------
-- 索敌双通道：威胁主人（任意阵营）或 monster/hostile tag
---------------------------------------------------------------------

local function IsThreateningMaster(v, master)
	if master == nil then
		return false
	end
	local t = v.components.combat.target
	return t == master
		or (t ~= nil and master.components.petleash ~= nil and master.components.petleash:IsPet(t))
end

local function RetargetFn(inst)
	local target = inst.components.combat.target
	if target ~= nil and inst:IsNear(target, CFG.SCAN_RANGE) then
		return nil -- 现目标还在带内，不折腾（投石机同款）
	end
	local master = GetMaster(inst)
	local x, y, z = inst.Transform:GetWorldPosition()
	local ents = TheSim:FindEntities(x, y, z, CFG.SCAN_RANGE,
		RETARGET_MUST_TAGS, RETARGET_CANT_TAGS, nil)
	for _, v in ipairs(ents) do
		if v ~= inst
			and v.entity:IsVisible()
			and inst.components.combat:CanTarget(v)
			and not inst.components.combat:IsAlly(v)
			and (master == nil or master:IsNear(v, CFG.MASTER_RANGE))
			and (v:HasTag("monster") or v:HasTag("hostile") or IsThreateningMaster(v, master))
		then
			return v
		end
	end
	return nil
end

local function KeepTargetFn(inst, target)
	local master = GetMaster(inst)
	return inst.components.combat:CanTarget(target)
		and inst:IsNear(target, CFG.SCAN_RANGE)
		and (master == nil or master:IsNear(target, CFG.MASTER_RANGE))
end

-- PvP 闸门（原型照搬）
local function ShouldAggro(inst, target)
	if target:HasTag("player") then
		return TheNet:GetPVPEnabled()
	end
	return true
end

---------------------------------------------------------------------
-- 电弧连锁（即时伤害 + eye_charge 视觉弹道）
---------------------------------------------------------------------

local function DoChainHop(inst, target, from, mult)
	-- 诊断（临时，验证通过后移除）
	print(string.format("[arc_k9] hop=%.3f targ=%s from=%s", mult, tostring(target.prefab), from ~= nil and tostring(from.prefab) or "self"))
	-- 视觉弹道：自制 arc_k9_shot（⚠ 勿用 projectile:Throw——Hit 内建把弹体当 weapon 传
	-- DoAttack，无 weapon 组件的弹体在 CalcDamage:891 崩，实测迭代 3 根因；纯视觉飞行）
	local fx = SpawnPrefab("arc_k9_shot")
	fx:Launch(from ~= nil and from or inst, target)

	-- 结算本跳
	inst.components.combat:DoAttack(target, nil, nil, "electric", mult)
	print("[arc_k9] doattack done")
	SpawnElectricHitSparks(inst, target, true) -- componentutil.lua:1023-1029
	print("[arc_k9] sparks done")

	-- 找下一跳：上一目标位置附近最近的合格敌人
	local hopsleft = inst._chainhops
	if hopsleft <= 0 then
		return
	end
	inst._chainhops = hopsleft - 1

	local x, y, z = target.Transform:GetWorldPosition()
	local ents = TheSim:FindEntities(x, y, z, CFG.CHAIN_RANGE, HOP_MUST_TAGS, HOP_CANT_TAGS)
	local next1, nextdistsq = nil, nil
	for _, v in ipairs(ents) do
		if v ~= inst and not inst._chainhits[v] and v:IsValid()
			and inst.components.combat:CanTarget(v)
			and not inst.components.combat:IsAlly(v)
		then
			local dx, dy, dz = v.Transform:GetWorldPosition()
			local d = (dx - x) * (dx - x) + (dz - z) * (dz - z)
			if nextdistsq == nil or d < nextdistsq then
				next1, nextdistsq = v, d
			end
		end
	end
	if next1 ~= nil then
		inst._chainhits[next1] = true
		inst:DoTaskInTime(CFG.HOP_DELAY * FRAMES, function(inst)
			if next1:IsValid() and inst:IsValid() then -- 实体销毁时任务自动取消，双保险
				DoChainHop(inst, next1, target, mult * CFG.HOP_DECAY)
			end
		end)
	end
end

local function DoArcAttack(inst)
	local target = inst.components.combat.target
	if target == nil or not target:IsValid() or not inst.components.combat:CanTarget(target) then
		return
	end
	if not inst:IsNear(target, CFG.ATTACK_RANGE) then
		return -- 炮台语义：目标超出射程就不打（狗不追，贴主人由 brain 的 Follow 保证）
	end
	print("[arc_k9] arc attack begin, targ=" .. tostring(target.prefab))
	inst._chainhits = { [target] = true }
	inst._chainhops = CFG.CHAIN_HOPS
	inst.SoundEmitter:PlaySound("dontstarve/common/together/electricity/electrocute_med")
	DoChainHop(inst, target, nil, 1)
	print("[arc_k9] arc attack end")
end

---------------------------------------------------------------------
-- 本体 commonfn
---------------------------------------------------------------------

local function commonfn(tier)
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()
	inst.entity:AddLight() -- 月光自发光（月风暴静电蓝紫，moonstorm_spark.lua:173-179）
	inst.Light:SetColour(111 / 255, 111 / 255, 227 / 255)
	inst.Light:SetIntensity(.6)
	inst.Light:SetRadius(2)
	inst.Light:SetFalloff(.7)
	inst.Light:Enable(true)

	inst.entity:AddNetwork()

	-- 飞行物理：critters.lua flying 分支 mass 1 配方（原型实测；MakeFlyingCharacterPhysics 勿用，spec §4 坑 3）
	inst.entity:AddPhysics()
	inst.Physics:SetMass(1)
	inst.Physics:SetFriction(0)
	inst.Physics:SetDamping(5)
	inst.Physics:SetCollisionGroup(COLLISION.CHARACTERS)
	inst.Physics:SetCollisionMask(
		TheWorld:CanFlyingCrossBarriers() and COLLISION.GROUND or COLLISION.WORLD,
		COLLISION.FLYERS,
		COLLISION.CHARACTERS
	)
	inst.Physics:SetCapsule(.5, 1)

	-- 悬浮眼球本体（critter_eyeofterror 官方同款：bank/build 六向，critters.lua:384/131-154）
	inst.Transform:SetSixFaced()
	inst.AnimState:SetBank("eyeofterror_mini")
	inst.AnimState:SetBuild("eyeofterror_mini_basic")
	inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")      -- gestalt 系强发光（gestalt.lua:143）
	inst.AnimState:SetLightOverride(.3)
	inst.AnimState:SetMultColour(.85, .9, 1.05, 1)               -- 月亮蓝白化（moonstorm_ground_lightning_fx.lua:82 手法，蓝色分量略提）

	inst:AddTag("companion")
	inst:AddTag("flying")
	inst:AddTag("ignorewalkableplatformdrowning")
	inst:AddTag("notarget") -- 无敌且不可被瞄准（上张图 05 定稿），死亡分支整条不存在
	inst:AddTag("noattack")
	inst:AddTag("arc_k9")

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	inst:AddComponent("inspectable")

	inst:AddComponent("locomotor") -- 飞行：不受路面减速、可过海（原型实测配置）
	inst.components.locomotor:EnableGroundSpeedMultiplier(false)
	inst.components.locomotor:SetTriggersCreep(false)
	inst.components.locomotor.walkspeed = CFG.WALK_SPEED
	inst.components.locomotor.runspeed = CFG.RUN_SPEED
	inst.components.locomotor.pathcaps = { allowocean = true, ignorecreep = true }

	inst:AddComponent("follower")
	inst.components.follower:KeepLeaderOnAttacked() -- abigail.lua:882-885
	inst.components.follower.keepdeadleader = true
	-- leader 由主人 petleash:LinkPet 自动接上（跨 shard 重生后同样自动）

	inst:AddComponent("combat")
	inst.components.combat:SetDefaultDamage(tier.damage)
	inst.components.combat:SetRange(CFG.ATTACK_RANGE)
	inst.components.combat:SetAttackPeriod(CFG.ARC_PERIOD) -- 直调 DoAttack 不检查它，保持一致仅供 UI/参照
	inst.components.combat:SetRetargetFunction(CFG.RETARGET_PERIOD, RetargetFn)
	inst.components.combat:SetKeepTargetFunction(KeepTargetFn)
	inst.components.combat:SetShouldAggroFn(ShouldAggro)
	inst.components.combat.playerdamagepercent = 0 -- 保险：误打到玩家也不掉血
	inst.components.combat.ignorehitrange = true  -- 连锁跳可能跑远，跳过距离校验（research/01 §2.4）

	if tier.planar > 0 then
		-- 位面伤害：护甲后结算天然穿透（research/03 §3；宠物先例 gestalt_guard_evolved.lua:265-267）
		inst:AddComponent("planardamage")
		inst.components.planardamage:SetBaseDamage(tier.planar)
	end

	-- 出场：眼球传送门 FX（research/02：eyeofterror_portal arrive，一次性网络化）
	local fx = SpawnPrefab("eyeofterror_arrive_fx")
	local px, py, pz = inst.Transform:GetWorldPosition()
	fx.Transform:SetPosition(px, py, pz)

	-- Abigail 式移动攻击：伤害由周期任务结算，SG 无攻击态（research/01 §4.3）
	inst:DoPeriodicTask(CFG.ARC_PERIOD, DoArcAttack)

	inst:SetBrain(require("brains/arc_k9brain"))
	inst:SetStateGraph("SGarc_k9")

	inst.persists = false -- 生命周期由主人 petleash 内联托管（migrationpets 跨 shard）
	inst.Physics:SetDontRemoveOnSleep(true)

	return inst
end

---------------------------------------------------------------------
-- 视觉弹（arc_k9_shot）：直线飞行追踪目标，到达出眼塔命中 FX。
-- 无 projectile 组件（Hit 内建结算陷阱，见 DoChainHop 注释）；
-- 贴图复用眼塔攻击弹 eyeball_turret_attack。
---------------------------------------------------------------------

local SHOT_SPEED = 25 -- 世界单位/秒
local SHOT_PERIOD = 1 / 30

local function ShotFn()
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddNetwork()

	inst.Transform:SetFourFaced()
	inst.AnimState:SetBank("eyeball_turret_attack")
	inst.AnimState:SetBuild("eyeball_turret_attack")
	inst.AnimState:PlayAnimation("idle", true)
	inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
	inst.AnimState:SetLightOverride(.5)
	inst.AnimState:SetMultColour(.85, .9, 1.05, 1) -- 与本体同款月亮蓝白

	inst:AddTag("FX")
	inst:AddTag("NOCLICK")

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	inst.persists = false

	inst.Launch = function(inst, from, to)
		local x, y, z = from.Transform:GetWorldPosition()
		local sx, sy, sz = x, y + .5, z
		inst.Transform:SetPosition(sx, sy, sz)
		local dist = math.max(from:GetDistanceSqToInst(to) ^ .5, .1)
		local traveled = 0
		inst:DoPeriodicTask(SHOT_PERIOD, function(inst)
			if not (inst:IsValid() and to:IsValid()) then
				return -- 失效即停飞（下方 3 秒兜底 Remove 收尾）
			end
			local tx, ty, tz = to.Transform:GetWorldPosition() -- 追踪目标实时位置
			traveled = traveled + SHOT_SPEED * SHOT_PERIOD
			local t = math.min(traveled / dist, 1)
			inst.Transform:SetPosition(sx + (tx - sx) * t, sy + (ty - sy) * t, sz + (tz - sz) * t)
			inst:ForceFacePoint(tx, ty, tz)
			if t >= 1 then
				local hx, hy, hz = inst.Transform:GetWorldPosition()
				SpawnPrefab("eye_charge_hit").Transform:SetPosition(hx, hy, hz)
				inst:Remove()
			end
		end)
	end

	inst:DoTaskInTime(3, inst.Remove) -- 兜底：目标中途消失等场景防残留

	return inst
end

return Prefab("arc_k9", function() return commonfn(TIERS[1]) end, assets, prefabs),
	Prefab("arc_k9_crown", function() return commonfn(TIERS[2]) end, assets, prefabs),
	Prefab("arc_k9_spark", function() return commonfn(TIERS[3]) end, assets, prefabs),
	Prefab("arc_k9_apex", function() return commonfn(TIERS[4]) end, assets, prefabs),
	Prefab("arc_k9_shot", ShotFn)
