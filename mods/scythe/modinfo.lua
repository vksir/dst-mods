name = "Scythe: More harvestable items"
description = [[
Original mod: https://steamcommunity.com/sharedfiles/filedetails/?id=1557738886&searchtext=scythe

在原 mod 的基础上新增了四种可收获项目：
石果树
海带
月岛树苗
咖啡（如果启用三合一）

侵删
]]
author = "Villkiss"
version = "1.1"

forumthread = " "

api_version = 10
all_clients_require_mod = true
client_only_mod = false
dst_compatible = true



icon_atlas = "scythe.xml"
icon = "scythe.tex"


configuration_options = {

{
		name = "picking_rate",
		label = "Picking Rate",
		hover = "You can choose how fast you want picking with scythes",
		options = {	
			{description = "Crazy", data = "crazy", hover = "ya,you are crazy!"},
			{description = "Very fast", data = "veryfast", hover = "so fast that you cant see what happend"},
			{description = "Fast", data = "fast", hover = "oh,saving my time"},
			{description = "Normal", data = "normal", hover = "faster then usual picking"},
			{description = "Slow", data = "slow", hover = "little faster then usual picking"},
			
		},
		default = "fast"
	},
{
		name = "difficulty",
		label = "Recipe",
		hover = "How hard is it to make Scythe",
		options = {	
			{description = "Original", data = "original", hover = "Very easy"},
			{description = "Balanced", data = "balanced", hover = "Some effort required"},
			
		},
			default = "original"
	},
{
		name = "enabledberries",
		label = "Berry Bush Picking",
		hover = "Use Scythe on bushes",
		options = {	
			{description = "Original", data = "forbid", hover = "Scythe does not work on bushes"},
			{description = "Allow", data = "allow", hover = "Scythe can pick bushes"},
			
		},
		default = "forbid"
	},

}
