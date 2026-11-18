-- Snappy Actions 装配：把游戏钩子接到各模块上，管理生命周期与热键。
local util = require("snappy/util")
local session = require("snappy/session")
local actions = require("snappy/actions")

local M = { conflict_checked = false }

local function OnActivated(inst)
    if inst ~= util.Player() then
        return -- 只关心本地玩家
    end
    if not M.conflict_checked then
        M.conflict_checked = true
        -- 与 Better Lag Compensation 互斥：它的钩子同样覆盖动作时间线，同时开会互相干扰
        if package.loaded["blc/main"] ~= nil then
            util.Log("检测到 Better Lag Compensation，本 mod 本次不生效（二选一）")
            session.Disable("BLC present")
            return
        end
    end
    if not session.enabled_mod then
        return
    end
    if session.s == nil then
        util.SafeCall("snappy start", session.Start, inst)
    end
end

function M.Boot(api, cfg)
    session.Configure(cfg)
    if not session.enabled_mod then
        util.Log("已关闭（mode=off），不挂任何钩子")
        return
    end

    api.AddComponentPostInit("playercontroller", function(pc)
        util.SafeCall("patch controller", actions.Patch, pc)
    end)
    api.AddStategraphPostInit("wilson_client", function(sg)
        util.SafeCall("patch stategraph", actions.PatchStategraph, sg)
    end)
    api.AddPlayerPostInit(function(inst)
        inst:ListenForEvent("playeractivated", function()
            util.SafeCall("playeractivated", OnActivated, inst)
        end)
        inst:ListenForEvent("playerdeactivated", function()
            if session.s ~= nil and session.s.inst == inst then
                util.SafeCall("playerdeactivated", session.Stop, inst)
            end
        end)
    end)

    -- 游戏内开关热键（用于和原版手感对比）
    -- 热键不再用 AddKeyDownHandler（部分环境收不到 F 键事件），改为 Watch 任务轮询 IsKeyDown；
    -- 配置的键名由 session.Configure/Start 解析。

    util.Log(string.format("已加载：%s 档，余量 %d 帧，连拍间隔 %.2fs，日志 %s，热键 %s",
        tostring(cfg.mode), tostring(cfg.margin), tostring(session.cfg.repeat_cd),
        cfg.lab and "开" or "关", cfg.key and tostring(cfg.key) or "无"))
end

return M
