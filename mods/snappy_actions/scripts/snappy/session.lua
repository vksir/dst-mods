-- 会话状态与时间线数学：实测基线、待验证队列、回滚/退避、统计。
--
-- 时间模型（详见笔记/博客：延迟补偿分析）：
--   服务端 doshortaction：第 6 帧执行动作并解除 busy，第 10 帧回 idle（帧 = 1/30s 常数，与 tick_rate 无关）。
--   服务端 dolongaction：第 4 帧解除 busy，T 帧执行动作（脚本默认 30 帧 = 1s；domediumaction 等
--   入口实际更短，客户端只看得到 dolongaction 一个 hash，故按观测时长取近期最大值）。
--   原版客户端完成条件 = 快照里看到服务端"进入"状态（≈ 一个 RTT + 两次量化）。
--   本 mod 的收尾 = sent + 实测基线（激进档再钳制到零延迟物理下限），不再依赖快照准时。
local util = require("snappy/util")

local F = util.F

local S = { s = nil }

-- 模块级开关（Boot/Disable/Configure 写；会话级开关 s.enabled 由热键切换）
S.enabled_mod = true
S.active = true

-- 配置（Boot 时写入；Configure 里校验）
S.cfg = { mode = "conservative", margin = 1, lab = true, repeat_cd = 0.5, key = nil }

-- 服务端状态时长（帧，SGwilson 2026 build；帧 = 1/30 秒常数）
S.SHORT = {
    perform = 6,     -- 第 6 帧执行动作
    doing_end = 10,  -- 第 10 帧回 idle（ActionButton 此刻才被服务端受理）
    pst = "pickup_pst",
    floor = 7,       -- 激进档下限：零延迟理想网络的执行时刻 = 执行点 6 帧 + tick 排队 1 帧
}
S.LONG = {
    t_default = 30,  -- 脚本默认 1s；实测观测覆盖
    head = 5,        -- 执行到受理的间隔：pst 4 帧 + 处理顺序 1 帧
    pst = "build_pst",
    high_pst = "construct_pst",
}
S.BACKOFF = 3          -- 秒：回滚后退回原版行为的时长
S.MAX_EXTRA = 4        -- 回滚惩罚的额外余量上限（帧）
S.BASELINE_WINDOW = 15 -- 秒：基线样本的有效窗口
S.REPEAT_CD = 0.5      -- 秒：连拍补发的最小间隔 = 原版 BUTTON_REPEAT_COOLDOWN（防误触的关键）

function S.Configure(cfg)
    if cfg.mode == "conservative" or cfg.mode == "aggressive" or cfg.mode == "off" then
        S.cfg.mode = cfg.mode
    end
    if type(cfg.margin) == "number" then
        S.cfg.margin = math.max(0, math.min(3, math.floor(cfg.margin)))
    end
    S.cfg.lab = cfg.lab ~= false
    S.cfg.key = cfg.key
    if type(cfg.repeat_cd) == "number" then
        S.cfg.repeat_cd = math.max(0.2, math.min(1.0, cfg.repeat_cd))
    end
    if S.cfg.mode == "off" then
        S.enabled_mod = false
    end
end

function S.Disable(reason)
    S.enabled_mod = false
    if S.s ~= nil then
        S.s.enabled = false
    end
    util.Log("已停用（" .. tostring(reason) .. "）")
end

function S.Toggle()
    local s = S.s
    if s == nil then
        return false
    end
    s.enabled = not s.enabled
    if not s.enabled then
        s.last_send = nil
        s.chain_until = 0
    end
    util.Log("跟手动作：" .. (s.enabled and "开" or "关"))
    return s.enabled
end

function S.StatusText()
    local s = S.s
    if s == nil or not s.enabled then
        return "跟手动作：关"
    end
    return "跟手动作：开（" .. S.cfg.mode .. "）"
end

---------------------------------------------------------------- 会话生命周期

local function new_state(inst)
    return {
        inst = inst,
        enabled = true,
        pendings = {},   -- target -> pending
        hidden = {},     -- target -> true（已预测隐藏、尚未被快照证实）
        samples = {},    -- 基线样本 { t, d }（d = 发送→观测到服务端开始，秒）
        long_obs = {},   -- dolongaction 服务端持续时长观测（帧）
        long_enter = nil,
        last_send = nil,
        last_button_free = nil,
        chain_until = 0,
        seen_state = nil,
        extra = 0,       -- 回滚惩罚的额外余量（帧）
        backoff_until = 0,
        ping = 0.2,
        tick = 0,
        queued = nil,    -- 推迟的按键 { task }
        key = nil,            -- 热键数值（轮询用）
        key_was_down = false,
        key_down_t = nil,     -- 最近一次按键按下的时刻（判断"主动新按"用）
        stats = { sent = 0, ended_early = 0, ok = 0, miss = 0, unverified = 0, queued = 0 },
    }
end

function S.Start(inst)
    if S.s ~= nil then
        S.Stop(S.s.inst)
    end
    S.s = new_state(inst)
    S.s.key = (S.cfg.key ~= nil and type(S.cfg.key) == "string") and rawget(_G, S.cfg.key) or nil
    -- 状态名 → player_classified.currentstate 的 hash
    local h = rawget(_G, "hash")
    S.HASH = {}
    for _, name in ipairs({ "doshortaction", "dolongaction" }) do
        S.HASH[name] = h ~= nil and h(name) or nil
    end
    S.s.on_pause = function() util.SafeCall("snappy pause", S.OnPause) end
    inst:ListenForEvent("cancelmovementprediction", S.s.on_pause)
    S.s.task = inst:DoPeriodicTask(F, function() util.SafeCall("snappy watch", S.Watch) end)
    util.Log(string.format("开始跟随 %s：%s 档，余量 %d 帧，日志 %s",
        tostring(inst.prefab), S.cfg.mode, S.cfg.margin, S.cfg.lab and "开" or "关"))
end

function S.Stop(inst)
    local s = S.s
    if s == nil or (inst ~= nil and inst ~= s.inst) then
        return
    end
    for target in pairs(s.hidden) do
        if target:IsValid() and not target:HasTag("INLIMBO") then
            target:Show()
        end
    end
    if s.queued ~= nil and s.queued.task ~= nil then
        s.queued.task:Cancel()
    end
    if s.task ~= nil then
        s.task:Cancel()
    end
    if s.inst:IsValid() then
        s.inst:RemoveEventCallback("cancelmovementprediction", s.on_pause)
    end
    util.Log(string.format("停止。累计：发送 %d，提前收尾 %d，确认 %d，回滚 %d，未确认 %d",
        s.stats.sent, s.stats.ended_early, s.stats.ok, s.stats.miss, s.stats.unverified))
    S.s = nil
end

---------------------------------------------------------------- 查询与时间线数学

-- 本 mod 是否对这次按键生效
function S.Usable(pc)
    local s = S.s
    return s ~= nil and s.enabled and S.enabled_mod and pc.inst == s.inst
end

function S.PingFrames()
    local s = S.s
    return (s ~= nil and s.ping or 0.2) / F
end

-- 实测基线：窗口内最快的"发送→观测到服务端开始"；没有样本 = nil
function S.Baseline()
    local s = S.s
    if s == nil then
        return nil
    end
    local now = util.Now()
    local best = nil
    for _, f in ipairs(s.samples) do
        if now - f.t <= S.BASELINE_WINDOW then
            best = (best == nil) and f.d or math.min(best, f.d)
        end
    end
    return best
end

-- 基线估计：实测优先，冷启动用 ping 估计（上传分帧 3 帧 + tick 1 帧 + 快照 2 帧）
function S.BaselineEst()
    local b = S.Baseline()
    if b ~= nil then
        return b
    end
    return (S.PingFrames() / 2 + 6) * F
end

function S.MarginFrames()
    local s = S.s
    return S.cfg.margin + (s ~= nil and s.extra or 0)
end

-- dolongaction 的服务端时长（帧）：近期观测的最大值，缺省用脚本值
function S.LongT()
    local s = S.s
    local t = S.LONG.t_default
    if s ~= nil then
        for _, frames in ipairs(s.long_obs) do
            if frames > t then
                t = frames
            end
        end
    end
    return t
end

-- 链式窗口是否活跃：上一个请求还在服务端"消化"中
function S.ChainLive(now)
    local s = S.s
    return s ~= nil and s.last_send ~= nil and now < s.chain_until
end

-- 下一个请求最早可以发出的本地时刻；nil = 无在途请求
function S.FreeAt()
    local s = S.s
    if s == nil or s.last_send == nil then
        return nil
    end
    return s.last_send + (s.last_button_free + S.MarginFrames()) * F
end

-- 下一次动作最早允许的时刻：
--   fresh=true（用户刚刚重新按下按键，主动意图明确）：只需服务端能受理（FreeAt）
--   否则（按住重复）：必须满连拍间隔（默认 = 原版 0.5s 重复冷却，防误触的关键）
function S.FireDue(fresh)
    local s = S.s
    if s == nil or s.last_send == nil then
        return nil
    end
    local due = s.last_send + (fresh and 0 or S.cfg.repeat_cd)
    local fa = S.FreeAt()
    if fa ~= nil and fa > due then
        due = fa
    end
    return due
end

-- 本次动作的本地收尾时刻（秒，绝对时刻）
function S.ComputeEnd(entry)
    local wait = S.BaselineEst()
    if entry.state == "doshortaction" and S.cfg.mode == "aggressive" then
        -- 激进档：钳制在零延迟理想网络的物理下限（再快必错，详见笔记"激进档的时刻怎么定"）
        wait = math.min(wait, S.SHORT.floor * F)
    end
    return entry.sent + wait + S.MarginFrames() * F
end

---------------------------------------------------------------- 记录与验证

-- RPC 已发出（old() 调用完成后立刻调用）
function S.RecordSend(entry, button_free)
    local s = S.s
    if s == nil then
        return
    end
    local now = util.Now()
    entry.sent = now
    entry.predict_end = S.ComputeEnd(entry)
    local p = {
        target = entry.target,
        entry = entry,
        state_hash = S.HASH[entry.state],
        sent = now,
        verified = false,
        excused = false,
        hidden = false,
        deadline = now + math.max(2 * s.ping, 1.2),
    }
    s.pendings[entry.target] = p
    entry.pending = p
    s.last_send = now
    s.last_button_free = button_free
    s.chain_until = now + (button_free + S.MarginFrames() + S.PingFrames() * 2 + 16) * F
    s.stats.sent = s.stats.sent + 1
    if S.cfg.lab then
        util.Log(string.format("发送#%d %s %s（按键保持=%s，基线=%.0fms，预计收尾=+%.0fms）",
            s.stats.sent, entry.state, tostring(entry.target.prefab),
            S.ActionKeyHeld() and "是" or "否", (S.Baseline() or 0) * 1000,
            ((entry.predict_end or now) - now) * 1000))
    end
end

-- 放弃一个还没发出的动作（状态被打断等）
function S.DropUnsent(entry)
    entry.cancelled = true
end

-- 服务端卡顿（cancelmovementprediction）：一切在途请求按"被原谅"处理
function S.OnPause()
    local s = S.s
    if s == nil then
        return
    end
    local classified = s.inst.player_classified
    local frames = (classified ~= nil and classified.pausepredictionframes ~= nil)
        and classified.pausepredictionframes:value() or 0
    local now = util.Now()
    s.last_send = nil
    s.chain_until = 0
    for target, p in pairs(s.pendings) do
        p.excused = true
        p.deadline = math.min(p.deadline, now + 0.5)
        if p.hidden then
            p.hidden = false
            s.hidden[target] = nil
            if target:IsValid() and not target:HasTag("INLIMBO") then
                target:Show()
            end
        end
    end
    if frames > 0 then
        s.backoff_until = math.max(s.backoff_until, now + 1)
    end
end

-- 动作键是否仍被按住（空格 / 手柄动作键）：松键就不补发，防止“按长一点点连检两个”的误触
function S.ActionKeyHeld()
    local input = TheInput
    if input == nil then
        return false
    end
    if input:IsControlPressed(CONTROL_ACTION) then
        return true
    end
    return CONTROL_CONTROLLER_ACTION ~= nil and input:IsControlPressed(CONTROL_CONTROLLER_ACTION) or false
end

-- 推迟一次按键到允许时刻（连拍节奏）；fresh=用户主动的新按键（只等服务端受理，不受 0.5s 节流）
function S.QueuePress(pc, at, fresh)
    local s = S.s
    if s == nil then
        return
    end
    if s.queued ~= nil and s.queued.task ~= nil then
        s.queued.task:Cancel()
    end
    local due = at - util.Now()
    s.queued = {
        fresh = fresh and true or false,
        task = pc.inst:DoTaskInTime(due, function()
            local s2 = S.s
            if s2 == nil or s2.queued == nil then
                return
            end
            local qfresh = s2.queued.fresh
            s2.queued = nil
            -- 松键不补发：原版语义（松键就没有下一个动作）
            if not S.ActionKeyHeld() then
                if S.cfg.lab then
                    util.Log("补发跳过：按键已松开")
                end
                return
            end
            if pc.inst:IsValid() then
                local sg2 = pc.inst.sg
                if sg2 ~= nil and (sg2:HasStateTag("idle") or sg2:HasStateTag("moving")) then
                    if S.cfg.lab then
                        util.Log(qfresh and "补发执行（主动新按，只等服务端受理）"
                            or "补发执行（按键保持，已满连拍间隔）")
                    end
                    s2.fire_fresh = qfresh
                    util.SafeCall("snappy queued press", function() pc:DoActionButton() end)
                end
            end
        end),
    }
    s.stats.queued = s.stats.queued + 1
end

---------------------------------------------------------------- 每 tick 观测/验证/回滚

function S.Watch()
    local s = S.s
    if s == nil then
        return
    end
    -- 热键轮询（AddKeyDownHandler 的分发在部分环境下收不到 F 键事件，改用状态轮询，30Hz 足够）
    if s.key ~= nil and TheInput ~= nil then
        local down = TheInput:IsKeyDown(s.key)
        if down and not s.key_was_down then
            s.key_was_down = true
            s.key_down_t = util.Now()
            local screen = (TheFrontEnd ~= nil) and TheFrontEnd:GetActiveScreen() or nil
            if screen ~= nil and screen.name == "HUD" then
                S.Toggle()
                local text = S.StatusText()
                local talker = (s.inst.components ~= nil) and s.inst.components.talker or nil
                if talker ~= nil then
                    pcall(talker.Say, talker, text)
                end
                util.Log("热键切换（轮询）→ " .. text)
            end
        elseif not down then
            s.key_was_down = false
        end
    end
    local now = util.Now()
    s.ping = (util.Ping() or 200) / 1000
    local classified = s.inst.player_classified
    local v = (classified ~= nil and classified.currentstate ~= nil)
        and classified.currentstate:value() or nil

    -- 服务端状态变化 → 尝试与在途请求配对（reach 过滤掉客户端自己写入的值）
    if v ~= s.seen_state then
        s.seen_state = v
        if v == S.HASH.dolongaction then
            s.long_enter = now
        elseif s.long_enter ~= nil then
            local frames = math.floor((now - s.long_enter) / F + 0.5)
            s.long_enter = nil
            if frames >= 10 and frames <= 90 then
                table.insert(s.long_obs, frames)
                if #s.long_obs > 3 then
                    table.remove(s.long_obs, 1)
                end
            end
        end
        if v ~= nil and v ~= 0 then
            local reach = now - math.max(2 * F, 0.5 * s.ping)
            local best = nil
            for _, p in pairs(s.pendings) do
                if not p.verified and p.state_hash == v and p.sent <= reach
                    and (best == nil or p.sent > best.sent) then
                    best = p
                end
            end
            if best ~= nil then
                best.verified = true
                if best.entry ~= nil then
                    best.entry.verified = true
                end
                local d = now - best.sent
                if d >= 3 * F and d <= 90 * F then
                    table.insert(s.samples, { t = now, d = d })
                    if #s.samples > 8 then
                        table.remove(s.samples, 1)
                    end
                end
                s.stats.ok = s.stats.ok + 1
                -- 连续顺利后逐步退还惩罚余量
                if s.extra > 0 and s.stats.ok % 10 == 0 then
                    s.extra = s.extra - 1
                end
            end
        end
    end

    -- 校验与回滚
    for target, p in pairs(s.pendings) do
        local gone = target == nil or not target:IsValid() or target:HasTag("INLIMBO")
        if p.verified or gone then
            s.pendings[target] = nil
            s.hidden[target] = nil
        elseif now >= p.deadline then
            s.pendings[target] = nil
            if p.hidden then
                s.hidden[target] = nil
                if target:IsValid() and not target:HasTag("INLIMBO") then
                    target:Show()
                end
                s.stats.miss = s.stats.miss + 1
                s.extra = math.min(s.extra + 1, S.MAX_EXTRA)
                s.backoff_until = now + S.BACKOFF
                if S.cfg.lab then
                    util.Log(string.format("回滚：%s 没被服务端执行（%.0fms 前发出）——物品已放回，退回原版 %ds，余量 %d 帧",
                        tostring(target.prefab), (now - p.sent) * 1000, S.BACKOFF, S.MarginFrames()))
                end
            else
                -- 没有视觉承诺（未隐藏）：多为快照跳过 idle 造成的漏配对，不惩罚
                s.unverified = s.unverified + 1
            end
        end
    end

    -- 每分钟小结
    s.tick = s.tick + 1
    if S.cfg.lab and s.tick % (30 * 60) == 0 then
        util.Log(string.format(
            "小结：发送 %d，提前收尾 %d，确认 %d，回滚 %d，未确认 %d，排队补发 %d｜当前余量 %d 帧%s",
            s.stats.sent, s.stats.ended_early, s.stats.ok, s.stats.miss, s.stats.unverified,
            s.stats.queued, S.MarginFrames(),
            now < s.backoff_until and "｜退避中" or ""))
    end
end

return S
