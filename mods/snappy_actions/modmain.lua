-- Snappy Actions：入口。
-- modmain 沙箱只有白名单库（pairs/ipairs/print/math/table/type/string/tostring/require/Class/GLOBAL），
-- 见 docs/dst-modming-pitfalls.md §1：这里不用 next/pcall/tonumber 等，逻辑全部在 scripts/snappy/
-- （require 后运行在游戏全局环境，标准库完整）。
local api = {
    modname = modname,
    AddComponentPostInit = AddComponentPostInit,
    AddStategraphPostInit = AddStategraphPostInit,
    AddPlayerPostInit = AddPlayerPostInit,
}
local config = {
    mode = GetModConfigData("mode"),
    margin = GetModConfigData("margin"),
    lab = GetModConfigData("lab"),
    key = GetModConfigData("key"),
}
GLOBAL.require("snappy/main").Boot(api, config)
