-- 激光犬本体：飞行悬浮 + 跟随主人 + 自动索敌即时命中激光（原型，机制出处见 .scratch/laser-rover/research/）
-- 结构：petleash 托管生命周期（主人玩家实例上）+ follower（leader=主人）+ combat 索敌攻击 + 独立 SG/脑

local assets = {
	Asset("ANIM", "anim/wx78_drone_zap.zip"), -- 占位贴图：WX-78 护卫无人机（05 定稿）
}

local prefabs = {
	"laser_rover_beam",
}

---------------------------------------------------------------------
-- 占位数值表（05 定稿：一处调参）
---------------------------------------------------------------------
local CFG = {
	DAMAGE = 10,         -- 单发伤害（占位）
	ATTACK_RANGE = 10,   -- 射程：攻击发起与结算距离（SetRange 单参 ⇒ attack=hit）
	ATTACK_PERIOD = 1,   -- 攻击冷却（秒）
	RETARGET_PERIOD = 1, -- 索敌重定向周期（秒，护卫类原版 ≤1s）
	SCAN_RANGE = 15,     -- 索敌半径（以狗为中心）
	MASTER_RANGE = 15,   -- 目标距主人上限（Abigail 双条件式）
	RUN_SPEED = 7,       -- 移速（玩家 6，骑牛 9）
}

-- 索敌过滤（research/02 §5.2 草案照抄 + noattack 补充）
local RETARGET_MUST_TAGS = { "_combat", "_health" }
local RETARGET_CANT_TAGS = { "INLIMBO", "player", "companion", "notarget", "noattack", "prey", "insect" }
local RETARGET_MUSTONEOF = { "monster", "hostile" } -- 「会主动攻击玩家的单位」最小 tag 集

local function GetMaster(inst)
	return inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
end

local function RetargetFn(inst)
	local target = inst.components.combat.target
	if target ~= nil and inst:IsNear(target, CFG.SCAN_RANGE + 3) then
		return nil -- 现目标还在带内，不折腾（投石机同款）
	end
	local master = GetMaster(inst)
	local x, y, z = inst.Transform:GetWorldPosition()
	local ents = TheSim:FindEntities(x, y, z, CFG.SCAN_RANGE + 3,
		RETARGET_MUST_TAGS, RETARGET_CANT_TAGS, RETARGET_MUSTONEOF)
	for _, v in ipairs(ents) do
		if v ~= inst
			and v.entity:IsVisible()
			and inst.components.combat:CanTarget(v)
			and not inst.components.combat:IsAlly(v)
			and (master == nil or master:IsNear(v, CFG.MASTER_RANGE)) -- 目标须在主人周围
		then
			return v
		end
	end
	return nil
end

local function KeepTargetFn(inst, target)
	local master = GetMaster(inst)
	return inst.components.combat:CanTarget(target)
		and inst:IsNear(target, CFG.SCAN_RANGE + 5)
		and (master == nil or master:IsNear(target, CFG.MASTER_RANGE + 5))
end

-- PvP 闸门：玩家仅在开 PvP 时可被仇恨（投石机三件套之一）
local function ShouldAggro(inst, target)
	if target:HasTag("player") then
		return TheNet:GetPVPEnabled()
	end
	return true
end

local function fn()
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()
	inst.entity:AddNetwork()

	-- 飞行物理：抄 critters.lua flying 分支（官方把 MakeFlyingCharacterPhysics 注释弃用了——
	-- 那套 mass 50 是给 SG 手动速度积分用的，locomotor 电机驱动要 mass 1 才推得动）
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

	inst.AnimState:SetBank("wx78_drone_zap")
	inst.AnimState:SetBuild("wx78_drone_zap")
	inst.AnimState:PlayAnimation("idle", true)
	-- 发光符号（原版无人机同款点缀）
	inst.AnimState:OverrideSymbol("bolt_c", "wagdrone_projectile", "bolt_c")
	inst.AnimState:SetSymbolBloom("bolt_c")
	inst.AnimState:SetSymbolLightOverride("bolt_c", 1)
	inst.AnimState:SetSymbolLightOverride("light_yellow_on", 0.5)
	inst.AnimState:SetSymbolBloom("light_yellow_on")

	inst:AddTag("companion") -- 其它护卫（Abigail 等）不打它
	inst:AddTag("flying")
	inst:AddTag("ignorewalkableplatformdrowning")
	inst:AddTag("notarget")  -- 05 定稿：无敌且不可被瞄准，死亡分支整条砍掉
	inst:AddTag("noattack")
	inst:AddTag("laser_rover")

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	inst:AddComponent("inspectable")

	inst:AddComponent("locomotor") -- 飞行：不受路面减速、不触发蛛网、可过海寻路
	inst.components.locomotor:EnableGroundSpeedMultiplier(false)
	inst.components.locomotor:SetTriggersCreep(false)
	inst.components.locomotor.walkspeed = CFG.RUN_SPEED
	inst.components.locomotor.runspeed = CFG.RUN_SPEED
	inst.components.locomotor.pathcaps = { allowocean = true, ignorecreep = true }

	inst:AddComponent("follower") -- critter 三件套（minigame 项原型省略）
	inst.components.follower:KeepLeaderOnAttacked()
	inst.components.follower.keepdeadleader = true
	-- leader 由 petleash:LinkPet 自动 AddFollower（= 持有项圈的主人），跨 shard 重生后同样自动接上

	inst:AddComponent("combat")
	inst.components.combat:SetDefaultDamage(CFG.DAMAGE)
	inst.components.combat:SetRange(CFG.ATTACK_RANGE) -- 即时命中：无武器，DoAttack 当帧结算
	inst.components.combat:SetAttackPeriod(CFG.ATTACK_PERIOD)
	inst.components.combat:SetRetargetFunction(CFG.RETARGET_PERIOD, RetargetFn)
	inst.components.combat:SetKeepTargetFunction(KeepTargetFn)
	inst.components.combat:SetShouldAggroFn(ShouldAggro)
	inst.components.combat.playerdamagepercent = 0 -- 保险：误打到玩家也不掉血

	inst:SetBrain(require("brains/laserroverbrain"))
	inst:SetStateGraph("SGlaserrover")

	inst.persists = false -- 存档由主人 petleash 内联托管（migrationpets 随玩家跨 shard）
	inst.Physics:SetDontRemoveOnSleep(true) -- critter 同款：物理不因睡眠剔除，配合 TryPorting 兜底

	return inst
end

return Prefab("laser_rover", fn, assets, prefabs)
