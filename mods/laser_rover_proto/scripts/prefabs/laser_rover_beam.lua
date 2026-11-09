-- 一次性激光束 FX（V1 方案，research/03）：服务端 spawn 网络化实体
-- 中点 + atan2 旋转（Transform 自动同步）+ 长度 net_byte 量化 → 客户端 dirty 时本地 SetScale
-- 不依赖 AnimState:SetScale 网络同步（原版可变长度一律走标量 net 变量）

local assets = {
	Asset("ANIM", "anim/wagdrone_laserwire_fx.zip"),
}

local MAX_LEN = 15 -- 与 wagdrone_laserwire 一致
local SEG_LEN = 2  -- beam 动画原生 2 世界单位长（fence_electric_field 注释：150px = 1 世界单位）

local function OnLenDirty(inst)
	local len = inst.len:value() / 255 * MAX_LEN
	if len > 0 then
		inst.AnimState:PlayAnimation("beam_" .. tostring(math.random(1, 4)))
		inst.AnimState:SetScale(len / SEG_LEN, 1)
	end
end

-- master 侧调用：设置长度（旋转/位置由 Transform 同步，不在这里处理）
local function SetBeam(inst, len)
	len = math.clamp(len, 0.1, MAX_LEN)
	inst.len:set_local(0) -- 强制 dirty：同值重复设置也要触发（laserwire 同款）
	inst.len:set(math.floor(len / MAX_LEN * 255 + .5))
end

local function fn()
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()
	inst.entity:AddNetwork()

	inst.AnimState:SetBank("wagdrone_laserwire_fx")
	inst.AnimState:SetBuild("wagdrone_laserwire_fx")
	inst.AnimState:PlayAnimation("beam_1")
	inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround) -- 贴地光束（原型接受）
	inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
	inst.AnimState:SetLightOverride(1)

	inst:AddTag("FX")
	inst:AddTag("NOCLICK")

	inst.len = net_byte(inst.GUID, "laser_rover_beam.len", "lendirty")

	inst:ListenForEvent("lendirty", OnLenDirty) -- 构造期监听：server/client 都吃到

	inst:ListenForEvent("animover", function(inst)
		if inst.AnimState:AnimDone() then
			inst:Remove()
		end
	end)

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	inst.persists = false
	inst.SetBeam = SetBeam
	inst:DoTaskInTime(1, inst.Remove) -- 兜底：dedicated server 无 animover，定时删

	return inst
end

return Prefab("laser_rover_beam", fn, assets)
