local TheNet = GLOBAL.TheNet
local IsServer = TheNet:GetIsServer() or TheNet:IsDedicated()
local TUNING = GLOBAL.TUNING

local houndstooth = {"houndstooth"}		--狗牙
local stinger = {"stinger"}				--蜂刺
local guano = {"guano"}					--鸟屎
local poop = {"poop"}					--便便
local spoiled_food = {"spoiled_food"}	--腐烂食物
local rottenegg = {"rottenegg"}			--腐烂鸡蛋
local winter_ornament =					--节日挂饰
{
	"winter_ornament_fancy1",			--节日挂饰
	"winter_ornament_fancy2",			--节日挂饰
	"winter_ornament_fancy3",			--节日挂饰
	"winter_ornament_fancy4",			--节日挂饰
	"winter_ornament_fancy5",			--节日挂饰
	"winter_ornament_fancy6",			--节日挂饰
	"winter_ornament_fancy7",			--节日挂饰
	"winter_ornament_fancy8",			--节日挂饰
	"winter_ornament_plain1",			--节日挂饰
	"winter_ornament_plain2",			--节日挂饰
	"winter_ornament_plain3",			--节日挂饰
	"winter_ornament_plain4",			--节日挂饰
	"winter_ornament_plain5",			--节日挂饰
	"winter_ornament_plain6",			--节日挂饰
	"winter_ornament_plain7",			--节日挂饰
	"winter_ornament_plain8",			--节日挂饰
	"winter_ornament_plain9",			--节日挂饰
	"winter_ornament_plain10",			--节日挂饰
	"winter_ornament_plain11",			--节日挂饰
	"winter_ornament_plain12"			--节日挂饰
}
local winter_ornament_boss =			--豪华装饰
{
	"winter_ornament_boss_bearger",
	"winter_ornament_boss_deerclops",
	"winter_ornament_boss_moose",
	"winter_ornament_boss_dragonfly",
	"winter_ornament_boss_beequeen",
	"winter_ornament_boss_toadstool",
	"winter_ornament_boss_antlion",
	"winter_ornament_boss_fuelweaver",
	"winter_ornament_boss_klaus",
	"winter_ornament_boss_malbatross",
	"winter_ornament_boss_krampus",
	"winter_ornament_boss_noeyered",
	"winter_ornament_boss_noeyeblue",
	"winter_ornament_boss_crabking",
	"winter_ornament_boss_crabkingpearl",
	"winter_ornament_boss_hermithouse",
	"winter_ornament_boss_minotaur",
	"winter_ornament_boss_pearl",
	"winter_ornament_boss_toadstool_misery"
}
local winter_food =						--冬季零食
{
	"winter_food1",						--姜饼人
	"winter_food2",						--糖屑曲奇
	"winter_food3",						--拐杖糖
	"winter_food4",						--不朽的水果蛋糕
	"winter_food5",						--巧克力原木蛋糕
	"winter_food6",						--干果布丁
	"winter_food7",						--苹果酒
	"winter_food8",						--热可可
	"winter_food9"						--神圣的蛋奶酒
}
local winter_ornament_light =			--圣诞彩灯
{
	"winter_ornament_light1",
	"winter_ornament_light2",
	"winter_ornament_light3",
	"winter_ornament_light4",
	"winter_ornament_light5",
	"winter_ornament_light6",
	"winter_ornament_light7",
	"winter_ornament_light8"
}
local halloween_ornament =				--万圣节装饰
{
	"halloween_ornament_1",
	"halloween_ornament_2",
	"halloween_ornament_3",
	"halloween_ornament_4",
	"halloween_ornament_5",
	"halloween_ornament_6"
}
local halloweencandy =					--万圣节糖果
{
	"halloweencandy_1",
	"halloweencandy_2",									
	"halloweencandy_3",					
	"halloweencandy_4",				
	"halloweencandy_5",	
	"halloweencandy_6",				
	"halloweencandy_7",					
	"halloweencandy_8",					
	"halloweencandy_9",				
	"halloweencandy_10",				
	"halloweencandy_11",				
	"halloweencandy_12",				
	"halloweencandy_13",				
	"halloweencandy_14"				
}
local sketch =                          -- Boss 图纸
{
	"chesspiece_moosegoose_sketch",
	"chesspiece_dragonfly_sketch",
	"chesspiece_bearger_sketch",
	"chesspiece_deerclops_sketch",
	"chesspiece_crabking_sketch",
	"chesspiece_malbatross_sketch",
	"chesspiece_antlion_sketch",
	"chesspiece_beequeen_sketch",
	"chesspiece_klaus_sketch",
	"chesspiece_minotaur_sketch",
	"chesspiece_stalker_sketch",
	"chesspiece_toadstool_sketch",
	"oceanfishingbobber_goose_tacklesketch"
}
local myth_toy =                          -- 神话书说玩具
{
	"myth_toy_chineseknot",
	"myth_toy_featherbundle",
	"myth_toy_tigerdoll",
	"myth_toy_tumbler",
	"myth_toy_twirldrum"
}

local function GetCleanList()
	local cleanList = {}
	local function AddCleanList(t)
	    for _,v in pairs(t) do
	    	table.insert(cleanList,v)
	    end
	end

	if GetModConfigData("houndstooth") then
		AddCleanList(houndstooth)		
	end
	if GetModConfigData("stinger") then
		AddCleanList(stinger)		
	end
	if GetModConfigData("guano") then
		AddCleanList(guano)					
	end
	if GetModConfigData("poop") then
		AddCleanList(poop)					
	end
	if GetModConfigData("spoiled_food") then
		AddCleanList(spoiled_food)			
	end
	if GetModConfigData("rottenegg") then
		AddCleanList(rottenegg)			
	end

	if GetModConfigData("winter_ornament") then
		AddCleanList(winter_ornament)		
	end
	if GetModConfigData("winter_ornament_boss") then
		AddCleanList(winter_ornament_boss)
	end
	if GetModConfigData("winter_food") then
		AddCleanList(winter_food)		
	end
	if GetModConfigData("winter_ornament_light") then
		AddCleanList(winter_ornament_light)		
	end
	if GetModConfigData("halloween_ornament") then
		AddCleanList(halloween_ornament)
	end
	if GetModConfigData("halloweencandy") then
		AddCleanList(halloweencandy)		
	end
	if GetModConfigData("sketch") then
		AddCleanList(sketch)		
	end
	if GetModConfigData("myth_toy") then
		AddCleanList(myth_toy)
	end
	return cleanList
end

local function IsCleanList(name)
	local cleanList = GetCleanList()
    for _,v in pairs(cleanList) do
        if string.find(name, v) then
            return true
        end
    end
    return false
end

local function Clean(inst)
    for _,v in pairs(GLOBAL.Ents) do
        if v.prefab ~= nil then
			if IsCleanList(v.prefab) and not v.inlimbo then
				v:Remove()
			end
        end
    end
end

local function CleanDelay(inst)
    if GetModConfigData("lang") then
        TheNet:Announce("服务器将于 30 秒后清理！")
    else
        TheNet:Announce("30s until server clean")
    end
    inst:DoTaskInTime(30, Clean)
end

GLOBAL.DoClean = Clean

if IsServer then
    AddPrefabPostInit("world", function(inst)
        inst:DoPeriodicTask(GetModConfigData("interval") * TUNING.TOTAL_DAY_TIME, CleanDelay)
    end)
end