name = "Winter Feast Clean"
description = "To clean winter feast items and halloween items.\n拥有可配置清理列表。可清理冬季盛宴杂物，及万圣节杂物。"
author = "Villkiss"
version = "1.1.3"
forumthread = ""
api_version = 10
icon_atlas = "modicon.xml"
icon = "modicon.tex"
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
dst_compatible = true
client_only_mod = false
all_clients_require_mod = true
server_filter_tags = {"winter feast", "clean"}

local none = {{description = "", data = false}}
local toggle = {{description = "Yes", data = true}, {description = "No", data = false}}

configuration_options =
{
	{ name = "", label = "General Settings", options = none, default = false },
    {
        name = "lang",
        label = "Language(语言)",
        options =
        {
            {description = "中文", data = true},
            {description = "English", data = false}
        },
        default = true
    },
    {
        name = "interval",
        label = "Interval(清理间隔)",
        hover = "How many days cleans up?\n多少天清理一次？",
        options =
        {
            {description = "1", data = 1},
            {description = "3", data = 3},
            {description = "5", data = 5},
            {description = "10", data = 10},
            {description = "20", data = 20}
        },
        default = 5
    },

    { name = "", label = "Clean List", options = none, default = false },
    {
        name = "houndstooth",
        label = "Houndstooth(狗牙)",
        hover = "Whether to clean houndstooth?\n是否清理狗牙？",
        options = toggle,
        default = true
    },
    {
        name = "stinger",
        label = "Stinger(蜂刺)",
        hover = "Whether to clean stinger?\n是否清理蜂刺？",
        options = toggle,
        default = true
    },
    {
        name = "guano",
        label = "Guano(鸟屎)",
        hover = "Whether to clean guano?\n是否清理鸟屎？",
        options = toggle,
        default = true
    },
    {
        name = "poop",
        label = "Poop(便便)",
        hover = "Whether to clean poop?\n是否清理便便？",
        options = toggle,
        default = true
    },
    {
        name = "spoiled_food",
        label = "Spoiled food(腐烂食物)",
        hover = "Whether to clean spoiled food?\n是否清理腐烂食物？",
        options = toggle,
        default = true
    },
    {
        name = "rottenegg",
        label = "rottenegg(腐烂鸡蛋)",
        hover = "Whether to clean rottenegg?\n是否清理腐烂鸡蛋？",
        options = toggle,
        default = false
    },
    {
        name = "winter_ornament",
        label = "Winter ornament(节日挂饰)",
        hover = "Whether to clean winter ornament?\n是否清理节日挂饰？",
        options = toggle,
        default = true
    },
    {
        name = "winter_ornament_boss",
        label = "Winter ornament boss(豪华装饰)",
        hover = "Whether to clean winter ornament boss?\n是否清理豪华装饰？",
        options = toggle,
        default = true
    },
    {
        name = "winter_food",
        label = "Winter food(冬季零食)",
        hover = "Whether to clean winter food?\n是否清理冬季零食？",
        options = toggle,
        default = true
    },
    {
        name = "winter_ornament_light",
        label = "Winter ornament light(圣诞彩灯)",
        hover = "Whether to clean winter ornament light?\n是否清理圣诞彩灯？",
        options = toggle,
        default = false
    },
    {
        name = "halloween_ornament",
        label = "Halloween ornament(万圣节装饰)",
        hover = "Whether to clean halloween ornament?\n是否清理万圣节装饰？",
        options = toggle,
        default = true
    },
    {
        name = "halloweencandy",
        label = "Halloweencandy(万圣节糖果)",
        hover = "Whether to clean halloweencandy?\n是否清理万圣节糖果？",
        options = toggle,
        default = true
    },
    {
        name = "sketch",
        label = "Boss Sketch(Boss 雕像图纸))",
        hover = "Whether to clean boss sketch?\n是否清理 Boss 雕像图纸？",
        options = toggle,
        default = true
    }
}