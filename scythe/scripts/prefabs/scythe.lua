local assets=
{ 
    Asset("ANIM", "anim/scythe.zip"),
    Asset("ANIM", "anim/swap_scythe.zip"), 

    Asset("ATLAS", "images/inventoryimages/scythe.xml"),
    Asset("IMAGE", "images/inventoryimages/scythe.tex"),
}

local prefabs = 
{
}



    local function OnEquip(inst, owner) 
        --owner.AnimState:OverrideSymbol("swap_object", "swap_scythes", "purplestaff")
        owner.AnimState:OverrideSymbol("swap_object", "swap_scythe", "scythe")
        owner.AnimState:Show("ARM_carry") 
        owner.AnimState:Hide("ARM_normal") 
    end

    local function OnUnequip(inst, owner) 
        owner.AnimState:Hide("ARM_carry") 
        owner.AnimState:Show("ARM_normal") 
    end

local function fn(Sim)


    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)
    
    inst.AnimState:SetBank("scythe")
    inst.AnimState:SetBuild("scythe")
    inst.AnimState:PlayAnimation("idle")
	
	--my input
	
	inst:AddTag("sharp")
	inst:AddTag("mower")      --Ìí¼ÓtagÎªÁ­µ¶


------------  don't know use
   if not TheWorld.ismastersim then
		return inst
	end
inst.entity:SetPristine()
-----------


    inst:AddComponent("weapon")
    inst.components.weapon:SetDamage(0.8*TUNING.SCYTHE_DAMAGE)
    
    -------
   --inst:AddComponent("tool")          --test
   -- inst.components.tool:SetAction(ACTIONS.MOWDOWN,1) 

    inst:AddComponent("finiteuses")
    inst.components.finiteuses:SetMaxUses(TUNING.SCYTHE_USES)   --50
    inst.components.finiteuses:SetUses(TUNING.SCYTHE_USES)
	inst.components.finiteuses:SetOnFinished(inst.Remove)
	inst.components.finiteuses:SetConsumption(ACTIONS.PICK, 0.4)       --原本是 ACTIONS.MOWDOWN 不知道为何不会掉耐久，应是只执行ACTIONS.PICK 所以通过该动作来消耗耐久

	inst:AddComponent("inspectable")


    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.imagename = "scythe"
    inst.components.inventoryitem.atlasname = "images/inventoryimages/scythe.xml"

	
	--------------------------------For add tool function--------------------------------
--Not exactly sure why, but it is necessary here.       --dont konw why it will cause crash 
--------ÒÔÉÏÁ½¾ä×¢ÊÍµôÒÔºó£¬²Â²âÊÇ²»»áÓÐ¸î²Ý×¨ÓÃµÄAction
	
	--inst.components.finiteuses:SetMaxUses(TUNING.PICKAXE_USES)
   -- inst.components.finiteuses:SetUses(TUNING.PICKAXE_USES)
   --inst.components.finiteuses:SetOnFinished(inst.Remove) 
    --Adjust the speed of consumption durability as the tool. Now is 125 uses.
	--------------------------------For add tool function--------------------------------
	
	--end

    
    inst:AddComponent("equippable")
    inst.components.equippable:SetOnEquip( OnEquip )
    inst.components.equippable:SetOnUnequip( OnUnequip )

      -- MakeHauntableLaunch(inst) ---test             貌似是循环动作 （比如chop ~chop~chop~）

    return inst
end

----------------------------------------------------------------
return  Prefab("common/inventory/scythe", fn, assets, prefabs)