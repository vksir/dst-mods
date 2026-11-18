-- 动作时间线：条目创建（包装 RemoteActionButton）、本地提前收尾（包装状态 onupdate）、
-- 连拍节奏（包装 DoActionButton，把服务端还没空受理的按键推迟到 FreeAt）。
--
-- 关键事实（已核对游戏源码，2026 build）：
--   · RemoteActionButton 在 doshortaction/dolongaction 的 onenter 内部被调用
--     （PerformPreviewBufferedAction → preview_cb），此刻 sg.currentstate 已经是目标状态、
--     statemem 有效——条目直接挂到 statemem 上即可。
--   · GoToState("idle", true) 的 pushanim=true 分支会把 idle_loop 排队到当前动画之后：
--     "补播 pickup_pst + GoToState(idle, true)" = 原版拒绝分支的平滑起身收尾。
--   · 状态由我们提前结束后，实体标签自然回到 idle，无需遮蔽 busy/doing。
local util = require("snappy/util")
local session = require("snappy/session")

local F = util.F

local A = {}

local function state_name(sg)
    return (sg ~= nil and sg.currentstate ~= nil) and sg.currentstate.name or nil
end

-- 这次按键是否纳入时间线；返回 nil = 交还原版
function A.SpecFor(state, action)
    if action == nil or action.action == nil then
        return nil
    end
    if state == "doshortaction" then
        return {
            kind = "short",
            hide = action.action == ACTIONS.PICKUP, -- 捡物品：本地时间线上让目标先"消失"
            button_free = session.SHORT.doing_end + 1, -- 处理顺序 1 帧
        }
    elseif state == "dolongaction" then
        return {
            kind = "long",
            hide = false, -- 采草等外观由快照驱动，无法伪造"已采"
            button_free = session.LongT() + session.LONG.head,
        }
    end
    return nil
end

---------------------------------------------------------------- 条目创建

-- 校验"对目标位置按下左键"是否得到同一动作；通过则返回点击坐标（LeftClick 通道需要）
function A.ClickPoint(inst, target, action)
    if inst.replica.inventory ~= nil and inst.replica.inventory:GetActiveItem() ~= nil then
        return nil -- 手上有持用物品时左键语义不同
    end
    local picker = inst.components.playeractionpicker
    if picker == nil or target.Transform == nil then
        return nil
    end
    local x, _, z = target.Transform:GetWorldPosition()
    local ok, lmb = pcall(picker.DoGetMouseActions, picker, Vector3(x, 0, z), target)
    if ok and lmb ~= nil and lmb.action == action and lmb.target == target then
        return x, z
    end
    return nil
end

function A.OnRemoteActionButton(pc, old, action, isreleased)
    if not session.Usable(pc) then
        return old(pc, action, isreleased)
    end
    local inst = pc.inst
    local sg = inst.sg
    local state = state_name(sg)
    local target = (action ~= nil) and action.target or nil
    local spec = A.SpecFor(state, action)
    if spec == nil or target == nil or not target:IsValid() then
        return old(pc, action, isreleased)
    end

    local mem = sg.statemem
    local entry = {
        state = state,
        target = target,
        hide = spec.hide,
        mem = mem,
        cancelled = false,
        verified = false,
        ended = false,
        sent = nil,
        predict_end = nil,
        pending = nil,
    }
    mem.snappy = entry

    -- 链式成员：点击点校验通过时改用 LeftClick 发送——服务端在第 6 帧解除 busy 即受理，
    -- 比空格走的 ActionButton（第 10 帧后）早 4 帧，连拍节奏直接受益（与 BLC 同款技巧）
    if session.ChainLive(util.Now()) then
        local cx, cz = A.ClickPoint(inst, target, action.action)
        if cx ~= nil then
            if pc.remote_controls ~= nil then
                pc.remote_controls[CONTROL_PRIMARY] = nil
            end
            SendRPCToServer(RPC.LeftClick, action.action.code, cx, cz, target, true, nil, nil,
                action.action.mod_name, nil, false)
            if session.s == nil then
                return
            end
            session.RecordSend(entry, session.SHORT.busy_end + 1)
            if session.cfg.lab then
                util.Log("链式成员改用 LeftClick 发送（受理提前 4 帧）")
            end
            return
        end
    end

    -- 原版发送（此刻仍在 onenter 内：RPC 经引擎分帧上行）
    old(pc, action, isreleased)
    if session.s == nil then
        return
    end
    session.RecordSend(entry, spec.button_free)
end

---------------------------------------------------------------- 本地时间线收尾

-- 状态 onupdate 的接管逻辑（true = 已处理，原版 onupdate 不跑）
function A.UpdateState(inst, entry)
    if entry.cancelled then
        return false
    end
    if entry.sent == nil then
        -- 理论上到不了这里（发送不排队），保险：别让原版提前收尾
        if inst.bufferedaction == nil then
            entry.cancelled = true
            return false
        end
        return true
    end
    if not entry.ended then
        local now = util.Now()
        -- 服务端开始被观测到（确认早于预测时刻）→ 立即收尾；否则按预测时刻收尾
        if entry.verified or (entry.predict_end ~= nil and now >= entry.predict_end) then
            A.EndState(inst, entry)
        end
    end
    return not entry.ended
end

function A.EndState(inst, entry)
    if entry.ended then
        return
    end
    local sg = inst.sg
    if sg == nil or sg.statemem ~= entry.mem then
        entry.ended = true
        return -- 状态已被别的顶掉（受击/走路等）：不插手
    end
    -- 原版完成时必须 FlattenMovementPrediction（提交预测位移缓冲）。提前收尾也必须做，
    -- 否则缓冲持续累积，引擎稍后强制落账时表现为周期性的"卡一下"。
    if not inst.entity:FlattenMovementPrediction() and (entry.flatten_retry or 0) < 6 then
        entry.flatten_retry = (entry.flatten_retry or 0) + 1
        return -- 缓冲暂不可提交：下帧重试（状态继续占住）
    end
    entry.ended = true
    -- 提前解除 0.5 秒重复冷却（BUTTON_REPEAT_COOLDOWN）
    local pc = inst.components.playercontroller
    if pc ~= nil and pc.remote_controls ~= nil and pc.remote_controls[CONTROL_ACTION] ~= nil then
        pc.remote_controls[CONTROL_ACTION] = 0
    end
    -- 捡物品：在本地时间线上让目标先"消失"（服务端随后真实移除；回滚路径负责放回）
    if entry.hide and entry.pending ~= nil and entry.target:IsValid()
        and not entry.target:HasTag("INLIMBO") then
        entry.pending.hidden = true
        if session.s ~= nil then
            session.s.hidden[entry.target] = true
        end
        entry.target:Hide()
    end
    -- 收尾 = 原版完成视觉，只是发生在我方的早期时间线上：
    -- GoToState("idle","noanim") 保留当前动画（pickup_lag 的完整弧线：弯腰→抓住→起身→站立），
    -- 动画自然播完停在站立帧 —— 与原版确认后的视觉完全一致，只是不等快照、且已解锁状态与冷却。
    -- 不额外播 pickup_pst：它会插在 pickup_lag 的弧线中间，被下一个弯腰打断时看起来像"抖两下"。
    sg:GoToState("idle", "noanim")
    local s = session.s
    if s ~= nil then
        s.stats.ended_early = s.stats.ended_early + 1
        if session.cfg.lab then
            util.Log("收尾：动画自然续播至站立（原版完成视觉）")
        end
    end
end

---------------------------------------------------------------- 控制器补丁

function A.Patch(pc)
    if pc.snappy_patched then
        return
    end
    pc.snappy_patched = true

    local old_remote = pc.RemoteActionButton
    pc.RemoteActionButton = function(self, action, isreleased)
        if session.s == nil then
            return old_remote(self, action, isreleased)
        end
        local ok, err = pcall(A.OnRemoteActionButton, self, old_remote, action, isreleased)
        if not ok then
            util.Log("error in action hook: " .. tostring(err))
            session.Disable("hook error")
            return old_remote(self, action, isreleased)
        end
    end

    -- 连拍节奏：下一次动作（新按或补发）最早在 max(服务端受理, 原版 0.5s 重复冷却) 之后；
    -- 队列补发前要求动作键仍被按住（松键即原版语义：没有下一个动作）。
    -- 只拦动作分支（self.placer == nil），建造放置流程不受影响
    local old_dab = pc.DoActionButton
    pc.DoActionButton = function(self, ...)
        if self.placer == nil and session.s ~= nil and session.s.inst == self.inst and session.s.enabled then
            local now = util.Now()
            if session.ChainLive(now) then
                -- fresh = 用户刚重新按下按键（主动新按，只等服务端受理），或队列补发的主动按键
                local fresh = (session.s.fire_fresh == true)
                    or ((session.s.key_down_t ~= nil) and (now - session.s.key_down_t <= 2 * F))
                local at = session.FireDue(fresh)
                session.s.fire_fresh = nil
                if at ~= nil and at > now + F * 0.5 then
                    session.QueuePress(self, at, fresh)
                    return
                end
            end
        end
        return old_dab(self, ...)
    end
end

---------------------------------------------------------------- 状态图补丁

function A.PatchStategraph(sg)
    local patched = 0
    for _, name in ipairs({ "doshortaction", "dolongaction" }) do
        local state = (sg.states ~= nil) and sg.states[name] or nil
        if state ~= nil then
            -- 不回落原版 onupdate：stategraph.lua:766 的 ServerStateMatches 对 server_states
            -- 不判空，实测有其他 mod（动作/操作类）会让它变 nil，原版分支直接崩
            -- （client_log 7485 行：attempt to index field 'server_states'）。
            -- 这里用安全复刻替代：先判空再比对，行为与原版一致。
            state.onupdate = function(inst, dt)
                local sg2 = inst.sg
                local entry = sg2.statemem.snappy
                if entry ~= nil then
                    local ok, handled = pcall(A.UpdateState, inst, entry)
                    if not ok then
                        util.Log("error in state hook: " .. tostring(handled))
                        sg2.statemem.snappy = nil
                    elseif handled then
                        return
                    end
                end
                if sg2.server_states == nil and not A.warned_no_server_states then
                    A.warned_no_server_states = true
                    util.Log("检测到 " .. name .. " 的 server_states 为空（本局有其他 mod 改动了状态图），已用安全分支处理")
                end
                if sg2.server_states ~= nil and sg2:ServerStateMatches() then
                    if inst.entity:FlattenMovementPrediction() then
                        sg2:GoToState("idle", "noanim")
                    end
                elseif inst.bufferedaction == nil then
                    local pst = session.SHORT.pst
                    if state.name == "dolongaction" then
                        pst = sg2.statemem.dohighaction and session.LONG.high_pst or session.LONG.pst
                    end
                    inst.AnimState:PlayAnimation(pst)
                    sg2:GoToState("idle", true)
                end
            end
            patched = patched + 1
        else
            util.Log("客户端状态图缺少 " .. name .. "：对应动作不加速")
        end
    end
    if patched == 0 then
        session.Disable("stategraph mismatch")
    end
end

return A
