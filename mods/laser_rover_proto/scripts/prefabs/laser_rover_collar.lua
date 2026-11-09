-- 激光项圈（绑定物品）：拾入物品栏 → 主人 petleash 生成激光犬；离开玩家（丢弃/进无主箱子）→ despawn
-- 已知原型缺口：项圈放在背包里、背包被整个丢弃时 onputininventory 不触发，狗会多留一阵（下轮拿放即修正）

local assets = {
	Asset("ANIM", "anim/gears.zip"), -- 占位贴图：齿轮
}

local ROVER_PREFAB = "laser_rover"

-- 幂等取狗：优先旧引用；迁移/读档后引用失效则向当前主人查询（petleash 自动重生的那只）
local function GetRover(inst)
	if inst.rover ~= nil and inst.rover:IsValid() then
		return inst.rover
	end
	inst.rover = nil
	local owner = inst.components.inventoryitem ~= nil and inst.components.inventoryitem:GetGrandOwner() or nil
	if owner ~= nil and owner.components.petleash ~= nil then
		local pets = owner.components.petleash:GetPetsWithPrefab(ROVER_PREFAB)
		if pets ~= nil then
			inst.rover = pets[1]
		end
	end
	return inst.rover
end

local function DespawnRover(inst)
	local rover = GetRover(inst)
	inst.rover = nil
	if rover ~= nil then
		local leader = rover.components.follower ~= nil and rover.components.follower:GetLeader() or nil
		if leader ~= nil and leader.components.petleash ~= nil then
			leader.components.petleash:DespawnPet(rover)
		else
			rover:Remove()
		end
	end
end

local function EnsureRover(inst)
	local owner = inst.components.inventoryitem ~= nil and inst.components.inventoryitem:GetGrandOwner() or nil
	if owner == nil or not owner:HasTag("player") then
		DespawnRover(inst) -- 物品不在任何玩家手里 → 狗消失
		return
	end

	local rover = GetRover(inst)
	if rover ~= nil then
		local leader = rover.components.follower ~= nil and rover.components.follower:GetLeader() or nil
		if leader ~= owner then
			DespawnRover(inst) -- 换主人：先拆旧的（下方立刻重建）
		else
			return
		end
	end

	-- 必须先注册 prefab 限额再生成（SpawnPetAt 满员返回 nil）
	owner.components.petleash:SetMaxPetsForPrefab(ROVER_PREFAB, 1)
	local x, y, z = owner.Transform:GetWorldPosition()
	inst.rover = owner.components.petleash:SpawnPetAt(x, y, z, ROVER_PREFAB)
	-- 诊断（原型阶段）：确认生成链路正常
	print(string.format("[laser_rover_collar] spawn rover=%s owner=%s leader=%s",
		tostring(inst.rover), tostring(owner),
		inst.rover ~= nil and tostring(inst.rover.components.follower ~= nil and inst.rover.components.follower:GetLeader() or nil) or "-"))
end

local function fn()
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddNetwork()

	MakeInventoryPhysics(inst)

	inst.AnimState:SetBank("gears")
	inst.AnimState:SetBuild("gears")
	inst.AnimState:PlayAnimation("idle")

	inst:AddTag("laser_rover_collar")

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	inst:AddComponent("inspectable")

	inst:AddComponent("inventoryitem")
	inst.components.inventoryitem:ChangeImageName("gears") -- 占位图标：官方齿轮（global atlas 按名可查）

	-- 绑定规则（05 定稿）：物品最终持有者是玩家 → 狗存在；否则立刻 despawn，重拾重新生成
	inst:ListenForEvent("onputininventory", EnsureRover)
	inst:ListenForEvent("ondropped", DespawnRover)
	inst.OnRemoveEntity = DespawnRover

	return inst
end

return Prefab("laser_rover_collar", fn, assets)
