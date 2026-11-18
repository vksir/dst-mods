-- 小工具。本文件经 require 运行在游戏全局环境（非 modmain 沙箱），标准库完整。
local M = {}

M.F = rawget(_G, "FRAMES") or 1 / 30

function M.Now()
    -- 模拟时钟：客户端单调、1/30s 步进。GetTimeRealSeconds() 在当前版本只按整秒走，不能用。
    return GetTime()
end

function M.Log(text)
    print("[SnappyActions] " .. text)
end

function M.SafeCall(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        M.Log("error in " .. what .. ": " .. tostring(err))
    end
    return ok, err
end

-- 本机到服务器的 ping（毫秒）；本机开世界 = 0；拿不到 = nil
function M.Ping()
    local net = TheNet
    if net == nil then
        return nil
    end
    local ok, is_server = pcall(function() return net:GetIsServer() end)
    if ok and is_server then
        return 0
    end
    for _, name in ipairs({ "GetAveragePing", "GetPing" }) do
        local fn = net[name]
        if type(fn) == "function" then
            local ok2, v = pcall(fn, net)
            if ok2 and type(v) == "number" and v >= 0 then
                return v
            end
        end
    end
    return nil
end

function M.Player()
    return ThePlayer
end

return M
