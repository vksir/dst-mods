-- 钟表袋 / Watchkeeper Bag
--
-- 参照极地熊獾桶（prefabs/beargerfur_sack.lua）：放在物品栏即可打开、无需装备。
-- 需求额外要求"像背包一样长时间开启"，所以覆盖 Container:OnUpdate：
--   原版 components/container.lua:1059 对 portablestorage 容器，只要玩家不在
--   keep_pocket_rummage 状态（走动/做动作即退出该状态）就会自动 Close。
--   这里把该实例的 OnUpdate 换成只在 opencount == 0 时停更，于是"走动不关闭"；
--   被覆盖掉的"丢出/换手后关闭"由下面的 CloseBag 监听补回（见 master_postinit）。
--
-- 容器面板复用原版 ui_krampusbag_2x8.zip（2 列 x 8 行 = 16 格）。
-- 因为自定义 prefab 不在 scripts/containers.lua 的 params 里，客户端拿不到布局，
-- 所以 modmain 里同时包裹了 containers.widgetsetup（两端都要生效）。

local assets =
{
    -- 容器面板底图（原版 2 列 x 8 行那套）
    Asset("ANIM", "anim/ui_krampusbag_2x8.zip"),
    -- MakeInventoryFloatable 的 bank "backpack1" 来自 backpack.zip（掉水里时的浮沉动画）
    -- 注意：这几个都是**原版**资源，按路径引用即可，引擎会回退到游戏本体；mod 里没有同名文件是正常的
    Asset("ANIM", "anim/backpack.zip"),
    -- 自定义地面/手持外观（tools/gen_item_build.py 生成）
    Asset("ANIM", "anim/wanda_watch_bag.zip"),
    -- 图标资源必须显式 ATLAS + IMAGE（ASSET INV_IMAGE 只认原版图集，原因见 wanda_haste_watch.lua）
    Asset("ATLAS", "images/inventoryimages/wanda_watch_bag.xml"),
    Asset("IMAGE", "images/inventoryimages/wanda_watch_bag.tex"),
}

local prefabs = {}

-- 需求 1（地面外观与克劳斯背包区分）：现在三个物品都直接借用原版 build
-- （本袋子用 swap_krampus_sack），丢在地上和原版克劳斯袋一模一样。
-- 仓库里没有 Spriter / 编译链，造不出新的 anim build，所以改用乘法着色做区分：
-- SetMultColour 是渲染属性，地面 / 手持都会生效，两端都在这里设置（客户端也要看到）。
-- 配色以 .scratch/wanda-planar-plan/v4/palette.md §1 为准（已对齐 w-art 定稿）。
local TINT = { 1.00, 0.60, 0.38 } -- 暖皮革棕（w-art 定稿 palette.md §1）

-- 注意：Container:CanTakeItemInSlot 以冒号调用 itemtestfn（container.lua:295），
-- 所以签名是 (container, item, slot)，不是 (item, slot)
local function IsWatch(container, item, slot)
    return item ~= nil and item:HasTag("pocketwatch")
end

-- 需求 2（v5）：开关钟表袋播"背包同款"音效，见 master_postinit。
-- 原版音效按优先级取（components/container.lua:639-647 开 / :694-700 关，客户端对应
-- components/container_replica.lua:501-509 / :525-532）：
--   SKIN_SOUND_FX → widget.opensound/closesound → IsSideWidget() 的背包音效 → 通用 HUD 音效
-- 背包 / 克劳斯袋等 side widget 默认就是 dontstarve/wilson/backpack_open|close。
local BACKPACK_OPEN_SND = "dontstarve/wilson/backpack_open"
local BACKPACK_CLOSE_SND = "dontstarve/wilson/backpack_close"

-- 需求 3（v5）：钟表袋只有旺达能用。
-- 判角色一律用 doer.prefab，不用 HasTag("clockmaker")——那是配方的 builder tag，
-- 可能被别的角色 mod 复用，不代表本人就是旺达。
local WANDA_PREFAB = "wanda"

local function CloseBag(inst)
    if inst.components.container ~= nil then
        inst.components.container:Close()
    end
end

local function master_postinit(inst)
    inst.components.inventoryitem.atlasname = "images/inventoryimages/wanda_watch_bag.xml"
    inst.components.inventoryitem.imagename = "wanda_watch_bag"
    inst.components.inventoryitem:SetOnPutInInventoryFn(CloseBag)

    inst:AddComponent("container")
    -- itemtestfn 属于 container 的 widgetprops（WidgetSetup 末尾会被 makereadonly），
    -- 必须在 WidgetSetup 之前赋值，否则后续赋值会触发 "Cannot change read only property"
    inst.components.container.itemtestfn = IsWatch
    inst.components.container:WidgetSetup("wanda_watch_bag")

    -- 需求 2（v5）：开关音效。
    -- 原来是 skipopensnd / skipclosesnd = true，把容器音效整个关掉了（Container 的
    -- opensound/closesound 属性 setter 会把开关同步到 replica 的 net_bool，
    -- container.lua:7-13 / container_replica.lua:285-298），删掉即可恢复默认音效。
    -- 本袋在 modmain 里是 side widget（widgetsetup 里 issidewidget = true），默认就是背包音效；
    -- 另外把 widget.opensound/closesound 也显式指成背包音效：
    -- "融合背包"布局会把本袋改成非 side widget（modmain 的布局逻辑），那时 IsSideWidget()
    -- 分支走不到，只有 widget.opensound 这一层能保证仍是背包同款。
    -- widget 表由 modmain 的 containers.widgetsetup 给出、两端共用；widget 字段本身是只读的
    -- （WidgetSetup 末尾 makereadonly），但表内容可写。
    local widget = inst.components.container.widget
    if widget ~= nil then
        widget.opensound = BACKPACK_OPEN_SND
        widget.closesound = BACKPACK_CLOSE_SND
    end

    -- 顺带确认：原版 Open/Close 的音效是在 doer.HUD 存在时经 TheFocalPoint.SoundEmitter 播的
    -- （container.lua:639-647 / :694-700），专用服务器上的玩家没有 HUD，实际由客户端的 replica 播
    -- （container_replica.lua:501-509 / :525-532）；下面的 Close 包装不拦 nil doer 的广播路径，
    -- 而广播路径内部递归的 Close(opener) 在 _wanda_closing 为真时放行，所以关袋音效不会被挡掉。
    inst.components.container.droponopen = true

    -- 走动不自动关闭：只保留"没有开启者时停更"的逻辑。
    -- 代价是原本由 OnUpdate 兜底的"丢出/死亡后关闭"也消失了，所以显式补上。
    inst.components.container.OnUpdate = function(self, dt)
        if self.opencount == 0 then
            self.inst:StopUpdatingComponent(self)
        end
    end
    -- "只有再次右键才关闭"的兜底闸：
    -- 原版所有自动关闭路径（Container:OnUpdate 的 rummage 判定、StateGraph 退出
    -- keep_pocket_rummage、开别的容器等）都是 Close(doer)，而本 mod 自己发起的关闭
    -- 一律走广播式 Close()（丢出、换手、死亡、右键关闭动作）。
    -- 所以这里直接把"带 doer 的 Close"全部挡掉，剩下的路径就只剩广播式关闭。
    local OldClose = inst.components.container.Close
    inst.components.container.Close = function(self, doer, ...)
        -- 注意：原版 Close(nil) 内部会递归调用 self:Close(各 opener)，
        -- 所以广播式关闭必须放行它的递归，否则自己也关不掉（实测 opencount 一直是 1）。
        if doer ~= nil and not self._wanda_closing then
            return
        end
        self._wanda_closing = true
        local r = OldClose(self, doer, ...)
        self._wanda_closing = nil
        return r
    end

    -- 需求 3（v5）：钟表袋只有旺达能"用"。
    -- 配方端的 builder_tag = "clockmaker" 只限制"能不能做"，别人捡起来仍可打开，
    -- 所以把容器入口钉死。动作在 modmain 注册（WANDA_TOGGLE_WATCH_BAG），它的 fn 里调的
    -- 就是 container:Open(doer)（原版 RUMMAGE 服务端最终也是 container:Open(act.doer)，
    -- actions.lua:1131/2500/2568），所以拦住 Open 就够了。
    --
    -- 为什么不同时包 CanOpen：Container:CanOpen() 是**无参**函数（container.lua:735，只判
    -- openlimit/opencount），调用方一律不传 doer（actions.lua:1101/2497/2519），
    -- 而且 Container:Open 本身也不调 CanOpen（container.lua:617），包了就是永远不生效的死代码。
    --
    -- doer 可能为 nil（部分广播/内部路径），nil 一律放行，避免误伤掉落、换手、关袋等流程。
    local OldOpen = inst.components.container.Open
    inst.components.container.Open = function(self, doer, ...)
        if doer ~= nil and doer.prefab ~= WANDA_PREFAB then
            return
        end
        return OldOpen(self, doer, ...)
    end
    -- 补充（不属于本文件职责）：客户端上"非旺达看不到‘开启’提示"由 modmain 的 INVENTORY 动作
    -- 条件决定，它只能用 replica.container:CanBeOpened()——该值是整实体 netvar、且方法不带 doer，
    -- 局部无法按玩家区分；真正的拦截只靠上面这层 Open（服务端权威）。
    -- 隐藏动作的干净做法已转 w-main：在 modmain 动作条件里加 doer.prefab ~= "wanda"。

    inst:ListenForEvent("ondropped", CloseBag)
    inst:ListenForEvent("onownerdropped", CloseBag)

    MakeHauntableLaunchAndDropFirstItem(inst)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("wanda_watch_bag")
    inst.AnimState:SetBuild("wanda_watch_bag")
    inst.AnimState:PlayAnimation("anim")
    -- 已有独立 build，不再着色
    if TINT ~= nil then inst.AnimState:SetMultColour(1, 1, 1, 1) end

    inst:AddTag("portablestorage")

    MakeInventoryFloatable(inst, "med", 0.1, 0.65, nil, nil, { bank = "backpack1", anim = "anim" })

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")
    inst:AddComponent("inventoryitem")

    master_postinit(inst)

    return inst
end

return Prefab("wanda_watch_bag", fn, assets, prefabs)
