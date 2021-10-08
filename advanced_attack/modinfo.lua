--The name of the mod displayed in the 'mods' screen.
name = "Advanced Attack"

--A description of the mod.
description = [[
优点：消除因切换武器造成的人物停顿，使在移动中切换武器更丝滑。
不足：无法消除连续攻击不同目标之间的人物停顿。这意味着刷鸟打鸟的时候，依旧打得很慢。

默认占用 F 键，启用此 mod 前请将游戏默认攻击键改为其它按键。

提取自07大佬的 Happy Cheating，侵删。
]]
author = "Villkiss"

--A version number so you can ask people if they are running an old version of your mod.
version = "1.1"

--This lets other players know if your mod is out of date. This typically needs to be updated every time there's a new game update.
api_version = 6
api_version_dst = 10
priority = 0

--Compatible with both the base game and Reign of Giants
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
dst_compatible = true

--This lets clients know if they need to get the mod from the Steam Workshop to join the game
all_clients_require_mod = false

--This determines whether it causes a server to be marked as modded (and shows in the mod list)
client_only_mod = true

--This lets people search for servers with this mod by these tags
server_filter_tags = {}

icon_atlas = "modicon.xml"
icon = "modicon.tex"
local string = ""
local keys = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","LAlt","RAlt","LCTRL","RCTRL","LSHIFT","RSHIFT","TAB","CAPSLOCK","SPACE","MINUS","EQUALS","BACKSPACE","INSERT","HOME","DELETE","END","PAGEUP","PAGEDOWN","PRINT","SCROLLOCK","PAUSE","PERIOD","SLASH","SEMICOLON","LEFTBRACKET","RIGHTBRACKET","BACKSLASH","UP","DOWN","LEFT","RIGHT"}
local keylist = {}
for i = 1, #keys do
  keylist[i] = {description = keys[i], data = "KEY_"..string.upper(keys[i])}
end
keylist[#keylist + 1] = {description = "Disabled", data = false}
local function AddConfig(label, name, options, default, hover)
  return {label = label, name = name, options = options, default = default, hover = hover or ""}
end
configuration_options =
{
  AddConfig("Attack key", "Attack_key", keylist, "KEY_F","发动攻击"),
}