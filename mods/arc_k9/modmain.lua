-- 护卫犬 K-9 正式版：只注册 prefab / 文案 / 配方。
-- modmain 沙箱白名单：pairs/ipairs/print/math/table/type/string/tostring/require/Class/GLOBAL——不碰其他标准库。
-- 出处：配方照抄 recipes.lua:811（eyeturret_item：远古祭坛）与 :858-860（月亮锻造三连）。

PrefabFiles = {
	"arc_k9",
	"arc_k9_collar",
}

---------------------------------------------------------------------
-- 文案（prefab 名 → STRINGS 键：arc_k9_collar → ARC_K9_COLLAR）
---------------------------------------------------------------------

local STRINGS = GLOBAL.STRINGS

STRINGS.NAMES.ARC_K9 = "护卫犬 K-9"
STRINGS.NAMES.ARC_K9_CROWN = "护卫犬 K-9·启迪"
STRINGS.NAMES.ARC_K9_SPARK = "护卫犬 K-9·火花"
STRINGS.NAMES.ARC_K9_APEX = "护卫犬 K-9·终阶"

STRINGS.NAMES.ARC_K9_COLLAR = "K-9 项圈"
STRINGS.NAMES.ARC_K9_COLLAR_CROWN = "K-9 项圈（启迪）"
STRINGS.NAMES.ARC_K9_COLLAR_SPARK = "K-9 项圈（火花）"
STRINGS.NAMES.ARC_K9_COLLAR_APEX = "K-9 项圈（终阶）"

STRINGS.RECIPE_DESC.ARC_K9_COLLAR = "召唤一只电弧护卫犬。"
STRINGS.RECIPE_DESC.ARC_K9_COLLAR_CROWN = "用电弧狗的旧项圈与启迪之冠锻造。"
STRINGS.RECIPE_DESC.ARC_K9_COLLAR_SPARK = "用电弧狗的旧项圈与满火花柜锻造。"
STRINGS.RECIPE_DESC.ARC_K9_COLLAR_APEX = "锻造终极护卫犬。"
STRINGS.RECIPE_DESC.ARC_K9_COLLAR_APEX_FROM_SPARK = "锻造终极护卫犬。"

STRINGS.CHARACTERS.GENERIC.DESCRIBE.ARC_K9 = "电弧汪。"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.ARC_K9_CROWN = "眼睛更亮了。"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.ARC_K9_SPARK = "噼啪作响。"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.ARC_K9_APEX = "月亮的看门狗。"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.ARC_K9_COLLAR = "它在看着我。"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.ARC_K9_COLLAR_CROWN = "项圈上镶着王冠。"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.ARC_K9_COLLAR_SPARK = "柜子里的雷。"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.ARC_K9_COLLAR_APEX = "满月之犬。"

---------------------------------------------------------------------
-- 配方（全部照抄原版站位，出处见文件头）
---------------------------------------------------------------------

local Ingredient = GLOBAL.Ingredient
local TECH = GLOBAL.TECH

-- 基础项圈：完整远古祭坛（TECH.ANCIENT_FOUR + nounlock，同 eyeturret_item）
AddRecipe2("arc_k9_collar", {
	Ingredient("deerclops_eyeball", 1),
	Ingredient("minotaurhorn", 1),
	Ingredient("glommerwings", 1),
	Ingredient("thulecite", 5),
}, TECH.ANCIENT_FOUR, { nounlock = true })

-- 升级线：月亮锻造台（TECH.LUNARFORGING_TWO + station_tag，同熊皮袋三连；消耗旧项圈，product 解耦配方名与产物）
AddRecipe2("arc_k9_collar_crown", {
	Ingredient("arc_k9_collar", 1),
	Ingredient("alterguardianhat", 1),
}, TECH.LUNARFORGING_TWO, { nounlock = true, station_tag = "lunar_forge" })

AddRecipe2("arc_k9_collar_spark", {
	Ingredient("arc_k9_collar", 1),
	Ingredient("security_pulse_cage_full", 1),
}, TECH.LUNARFORGING_TWO, { nounlock = true, station_tag = "lunar_forge" })

-- 终阶两条殊途：启迪线补火花 / 火花线补启迪（product 同为 apex 项圈）
AddRecipe2("arc_k9_collar_apex", {
	Ingredient("arc_k9_collar_crown", 1),
	Ingredient("security_pulse_cage_full", 1),
}, TECH.LUNARFORGING_TWO, { nounlock = true, station_tag = "lunar_forge" })

AddRecipe2("arc_k9_collar_apex_from_spark", {
	Ingredient("arc_k9_collar_spark", 1),
	Ingredient("alterguardianhat", 1),
}, TECH.LUNARFORGING_TWO, { nounlock = true, station_tag = "lunar_forge", product = "arc_k9_collar_apex" })
