-- K-9 项圈（4 形态共享 commonfn，一一对应 4 个狗 prefab）：
--   arc_k9_collar        → arc_k9        基础（68）
--   arc_k9_collar_crown  → arc_k9_crown  启迪（142）
--   arc_k9_collar_spark  → arc_k9_spark  火花（68 + 位面 68）
--   arc_k9_collar_apex   → arc_k9_apex   终阶（142 + 位面 68）
--
-- 绑定语义（原型实测直迁）：项圈最终持有者是玩家 → 狗存在；否则 despawn。
-- 升级 = 配方消耗旧项圈（OnRemoveEntity 拆旧狗）+ 产物新项圈入手（EnsureDog 建新狗），天然无缝。
--
-- 图标链路（实测迭代 4 定案，两次踩坑后以源码为据）：
--   ① 必须用 `inventoryitem.imagename = "名"` 走属性 setter（inventoryitem.lua:5-7 onimagename
--      → replica:SetImage → classified net 变量同步）；`ChangeImageName` 绕过 setter 只改
--      原始字段+推 imagechange（:470-472），永不同步，客户端读不到；
--   ② **不要**设 atlasname：GetAtlas（inventoryitem_replica.lua:163-168）兜底调
--      GetInventoryItemAtlas(GetImage())，而该兜底只查 inventoryimages1~4.xml
--      （simutil.lua:675-685）；显式 atlasname 走 resolvefilepath 对 zip 内资源不可靠，
--      反而盖掉兜底 → 空白图标；
--   ③ 图标名必须在 atlas 1~4 里真实存在（已用 images.zip 的 Element 名逐个核实，
--      "mooneye.tex" 并不存在，是 "bluemooneye.tex"——踩过）。

local assets = {
	Asset("ANIM", "anim/gears.zip"), -- 掉落/世界内的占位外观
}

-- 各形态：狗 prefab + 官方图标名（均取自 inventoryimages1~4，07 票可换自制美术）
local FORMS = {
	{ collar = "arc_k9_collar", dog = "arc_k9", image = "eyeturret_item" },          -- 月亮眼球塔套件（= 悬浮眼球护卫）
	{ collar = "arc_k9_collar_crown", dog = "arc_k9_crown", image = "alterguardianhat" }, -- 启迪之冠
	{ collar = "arc_k9_collar_spark", dog = "arc_k9_spark", image = "security_pulse_cage_full" }, -- 满火花柜
	{ collar = "arc_k9_collar_apex", dog = "arc_k9_apex", image = "purebrilliance" }, -- 纯辉（终阶）
}

-- 幂等取狗：优先旧引用；迁移/读档后引用失效则向当前主人查询（petleash 自动重生的那只）
local function GetDog(inst, dogprefab)
	if inst.dog ~= nil and inst.dog:IsValid() then
		return inst.dog
	end
	inst.dog = nil
	local owner = inst.components.inventoryitem ~= nil and inst.components.inventoryitem:GetGrandOwner() or nil
	if owner ~= nil and owner.components.petleash ~= nil then
		local pets = owner.components.petleash:GetPetsWithPrefab(dogprefab)
		if pets ~= nil then
			inst.dog = pets[1]
		end
	end
	return inst.dog
end

local function DespawnDog(inst, dogprefab)
	local dog = GetDog(inst, dogprefab)
	inst.dog = nil
	if dog ~= nil then
		local leader = dog.components.follower ~= nil and dog.components.follower:GetLeader() or nil
		if leader ~= nil and leader.components.petleash ~= nil then
			leader.components.petleash:DespawnPet(dog)
		else
			dog:Remove()
		end
	end
end

local function EnsureDog(inst, dogprefab)
	local owner = inst.components.inventoryitem ~= nil and inst.components.inventoryitem:GetGrandOwner() or nil
	if owner == nil or not owner:HasTag("player") then
		DespawnDog(inst, dogprefab) -- 不在任何玩家手里 → 狗消失
		return
	end

	local dog = GetDog(inst, dogprefab)
	if dog ~= nil then
		local leader = dog.components.follower ~= nil and dog.components.follower:GetLeader() or nil
		if leader ~= owner then
			DespawnDog(inst, dogprefab) -- 换主人：先拆旧的（下方立刻重建）
		else
			return
		end
	end

	-- 必须先注册 prefab 限额再生成（SpawnPetAt 满员返回 nil）
	owner.components.petleash:SetMaxPetsForPrefab(dogprefab, 1)
	local x, y, z = owner.Transform:GetWorldPosition()
	inst.dog = owner.components.petleash:SpawnPetAt(x, y, z, dogprefab)
	print(string.format("[arc_k9] spawn %s owner=%s ok=%s",
		dogprefab, tostring(owner), tostring(inst.dog ~= nil)))
end

local function commonfn(form)
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddNetwork()

	MakeInventoryPhysics(inst)

	-- 世界内可见的掉落形态：复用眼塔攻击弹贴图太怪，改用齿轮占位（背包图标另走 imagename）
	inst.AnimState:SetBank("gears")
	inst.AnimState:SetBuild("gears")
	inst.AnimState:PlayAnimation("idle")

	inst:AddTag("arc_k9_collar")

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	inst:AddComponent("inspectable")

	inst:AddComponent("inventoryitem")
	inst.components.inventoryitem.imagename = form.image -- 属性 setter → replica:SetImage（图标核心）

	inst:ListenForEvent("onputininventory", function(inst) EnsureDog(inst, form.dog) end)
	inst:ListenForEvent("ondropped", function(inst) DespawnDog(inst, form.dog) end)
	inst.OnRemoveEntity = function(inst) DespawnDog(inst, form.dog) end

	return inst
end

local ret = {}
for _, form in ipairs(FORMS) do
	table.insert(ret, Prefab(form.collar, function() return commonfn(form) end, assets))
end
return unpack(ret)
