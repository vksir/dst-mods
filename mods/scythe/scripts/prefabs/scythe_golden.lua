local assets=
{ 
    Asset("ANIM", "anim/scythe_golden.zip"),
    Asset("ANIM", "anim/swap_scythe_golden.zip"), 

    Asset("ATLAS", "images/inventoryimages/scythe_golden.xml"),
    Asset("IMAGE", "images/inventoryimages/scythe_golden.tex"),
}

local prefabs = 
{
}



    local function OnEquip(inst, owner) 
        --owner.AnimState:OverrideSymbol("swap_object", "swap_scythes", "purplestaff")
       owner.AnimState:OverrideSymbol("swap_object", "swap_scythe_golden", "scythe")   --don't konw why
        --owner.AnimState:OverrideSymbol("swap_object", "swap_scythe", "scythe")
    owner.SoundEmitter:PlaySound("dontstarve/wilson/equip_item_gold")     ----
        owner.AnimState:Show("ARM_carry") 
        owner.AnimState:Hide("ARM_normal") 
    end

    local function OnUnequip(inst, owner) 
        owner.AnimState:Hide("ARM_carry") 
        owner.AnimState:Show("ARM_normal") 
    end

local function fn(Sim)   --------


    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)
    
    inst.AnimState:SetBank("scythe_golden")            ------------dont't konw why   (设置的旋转中心？）
    inst.AnimState:SetBuild("scythe_golden")           -------------         （猜测是设置的使用哪个 .zip?)
    inst.AnimState:PlayAnimation("idle")
	
	--my input
	
	inst:AddTag("sharp")
	inst:AddTag("mower")      --添加tag为镰刀

if not TheWorld.ismastersim then
        return inst
    end
inst.entity:SetPristine()  
				----

    inst:AddComponent("weapon")
    inst.components.weapon:SetDamage(0.8*TUNING.SCYTHE_DAMAGE)
    
    -------
    
    inst:AddComponent("finiteuses")
    inst.components.finiteuses:SetMaxUses(TUNING.GOLDENSCYTHE_USES)  --300
    inst.components.finiteuses:SetUses(TUNING.GOLDENSCYTHE_USES)
	inst.components.finiteuses:SetOnFinished(inst.Remove)
    inst.components.finiteuses:SetConsumption(ACTIONS.PICK, 0.4)

	inst:AddComponent("inspectable")
	
	--------------------------------For add tool function--------------------------------
	----inst:AddComponent("tool")
	----inst.components.tool:SetAction(ACTIONS.MOWDOWN, 1) --Not exactly sure why, but it is necessary here.       --dont konw why it will cause crash
	
	--inst.components.finiteuses:SetMaxUses(TUNING.PICKAXE_USES)
    --inst.components.finiteuses:SetUses(TUNING.PICKAXE_USES)
   -- inst.components.finiteuses:SetOnFinished(inst.Remove) 
 --Adjust the speed of consumption durability as the tool. Now is 500 uses.
	--------------------------------For add tool function--------------------------------
	
	--end

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.imagename = "scythe_golden"
    inst.components.inventoryitem.atlasname = "images/inventoryimages/scythe_golden.xml"
    
    inst:AddComponent("equippable")
    inst.components.equippable:SetOnEquip( OnEquip )
    inst.components.equippable:SetOnUnequip( OnUnequip )


    return inst
end

----------------------------------------------------------------
return  Prefab("common/inventory/scythe_golden", fn, assets, prefabs)