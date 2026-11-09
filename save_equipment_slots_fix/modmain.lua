-- Lua built-ins that are only accessible through GLOBAL
local require = GLOBAL.require
local setmetatable = GLOBAL.setmetatable
local unpack = GLOBAL.unpack

-- [本地修改] 额外需要的全局对象
-- 注意: DST 的 mod 沙箱不提供 next/tonumber/pcall 等内置函数，必须从 GLOBAL 取
local json = GLOBAL.json
local TheNet = GLOBAL.TheNet
local next = GLOBAL.next
local pcall = GLOBAL.pcall
local tonumber = GLOBAL.tonumber

-- [修复] 引擎全局：按名查官方物品图集。mod 沙箱是显式白名单环境
-- (mods.lua CreateEnvironment 无 __index 转发)，裸用恒为 nil，
-- 导致 client 模式按名推断从未生效(物品不在身上的槽位图标全部方块)，
-- 也让 FlushIconStore 的 inferable 判断永远为 false(数字坏条目入盘)
local GetInventoryItemAtlas = GLOBAL.GetInventoryItemAtlas

-- [修复] 引擎 hash 函数(C binding)：用于 net_hash 数字反解(见 fn.UnhashTex)
local hash = GLOBAL.hash

-- DS globals
local CreateEntity = GLOBAL.CreateEntity
local TheSim = GLOBAL.TheSim
local Ents = GLOBAL.Ents
local TheInput = GLOBAL.TheInput
local ACTIONS = GLOBAL.ACTIONS
local CONTROLS = {
  LB = GLOBAL.CONTROL_ROTATE_LEFT,
  RB = GLOBAL.CONTROL_ROTATE_RIGHT,
}

local ImageButton = require("widgets/imagebutton")
local Text = require("widgets/text")
local DisplayNames = GLOBAL.STRINGS and GLOBAL.STRINGS.NAMES
local PlayerHud = require("screens/playerhud")

-- Represents an object used to occupy an inventory slot temporarily
-- when we are moving items around
local OCCUPIED = { components = {}, HasTag = function() return false end }
-- Another object we use to block an inventory slot, this one is used to reserve
-- saved slots when looking for an empty inventory slot for a new item
local RESERVED = { components = {}, HasTag = function() return false end }

-- entity to run tasks with, necessary to gain access to DoTaskInTime()
local tasker = CreateEntity()

-- Table to hold all local state of this mod.
local state = {
  -- Initialized in fn.InitConfig()
  config = {},

  -- saved slot -> [item.prefab]
  items = {},

  -- item.prefab -> saved slot
  slots = {},

  -- item.prefab -> image button widget of item
  image_buttons = {},

  -- MasterInventory or ClientInventory
  inventory = nil,
  -- Client Mode only: ClientContainer for the current backpack item
  overflow = nil,
  -- HUD inventorybar
  inventorybar = nil,

  -- When > 0, signals that this mod is moving items around.
  -- Controlled with fn.Lock() / fn.Unlock() and can be read with fn.IsLocked()
  -- Used to prevent updating saved slots during this time when items arrive in new slots.
  locks = 0,

  -- true for all cases except when connected to a remote host in DST
  is_mastersim = true,

  -- Detect Don't Starve Together
  is_dst = TheSim:GetGameID() == "DST",

  -- true if we are currently in the process of equipping some equipment
  is_equipping = false,

  -- Keeps track of equipment that is being manually moved,
  -- in which case the saved slots might have to be updated.
  manually_moved = {},

  -- DST Client Mode: GUIDs of items that have already been processed
  -- when their clientside "itemget" event was raised.
  client_processed = {},

  -- ClientMode only -- durability per item as it is only communicated through the "percentusedchange" event
  -- and not accessible anymore through a finiteuses component which is only available to the mastersim
  durability = {
    -- Durability per item, key is item.GUID
    items = {},
    -- Listener functions per item, key is item.GUID
    listeners = {}
  },

  -- Whether or not saving slots is currently disabled
  disable_save_slots = false,

  -- Text widget to display current status of Disable Save Slots option
  disable_save_slots_text_widget = nil,

  -- Animation callback
  disable_save_slots_animation = nil,

  -- Cache of prefab name -> { atlas, image } of icon
  atlas_image_cache = {},

  -- [本地修改] prefab -> true：该 prefab 的槽位图标当前渲染成 fallback 方块。
  -- 图标缓存就绪时据此精确替换方块，避免把正常图标也重画一遍
  fallback_buttons = {},

  -- [本地修改] 图标引用磁盘缓存的防抖写盘任务 / 已加载标记
  icon_store_flush_task = nil,
  icon_store_loaded = nil,

  -- [本地修改] prefab -> true：该 prefab 当前按钮已成功重建过一次。
  -- 防止资源就绪后的重建循环(新按钮仍是推断/磁盘来源会再次挂上重建任务)
  rerendered_buttons = {},
}

-- All functions will be stored in this table,
-- in this way we can bypass the Lua limitation that
-- a function X can only call other local functions that
-- are declared before X is declared.
-- When storing them all in a table, this limitation is removed.
local fn = {}

-- Table to hold the classes used by this mod;
-- MasterInventory, ClientInventory and ClientContainer
local new = {}

function fn.Lock()
  state.locks = state.locks + 1
end

function fn.Unlock()
  state.locks = state.locks - 1
end

function fn.IsLocked()
  return state.locks > 0
end

function fn.GetPlayer()
  if state.is_dst then
    return GLOBAL.ThePlayer
  else
    return GLOBAL.GetPlayer()
  end
end

-- Generates a table of item.prefab -> slot,
-- based on the current contents of the items variable
function fn.GetItemSlots()
  local slots = {}

  for slot, prefabs in pairs(state.items) do
    for _, prefab in ipairs(prefabs) do
      slots[prefab] = slot
    end
  end

  return slots
end

function fn.EachSavedSlot(callback)
  for slot, prefabs in pairs(state.items) do
    if #prefabs > 0 then
      callback(slot)
    end
  end
end

function fn.ReserveSavedSlots(inventory)
  fn.EachSavedSlot(function(slot)
    if not inventory.itemslots[slot] then
      inventory.itemslots[slot] = RESERVED
    end
  end)
end

function fn.UndoReserveSavedSlots(inventory)
  fn.EachSavedSlot(function(slot)
    local item = inventory.itemslots[slot]
    if item == RESERVED then
      inventory.itemslots[slot] = nil
    end
  end)
end

function fn.MaybeSetAtlasAndImageCache(prefab, compute_fn)
  local _, _, source = fn.GetAtlasAndImageFromCache(prefab)
  if state.atlas_image_cache[prefab] and source == nil then
    -- 已有本会话真实来源缓存，无需重算
    return
  end

  local atlas, image = compute_fn()
  -- [修复] 过滤空字符串与非字符串：classified 的 net_string 在同步完成前为 ""
  -- (空字符串在 Lua 中为真值)，某些路径还可能给出数字，
  -- 一旦缓存会导致图标渲染成 fallback 方块或空白
  if  atlas and image and
      type(atlas) == "string" and type(image) == "string" and
      atlas ~= "" and image ~= "" then
    fn.SetAtlasAndImageCache(prefab, atlas, image)
    -- [修复] 数据升级后立即重画对应按钮(方块->真实 / 基础->皮肤)
    fn.RefreshIconButtonIfAny(prefab)
  end
end

-- [本地修改] 纯客户端图标推断：物品不在身上时无法读取物品实体的 classified，
-- 但官方物品与已注册 atlas 的 mod 物品可以直接按 prefab 名查到图标。
-- no_fallback=true 确保查不到时返回 nil 而不是误拿 images4，
-- 推断失败仍回退 fallback 方块，物品入手后再由真实来源覆盖。
function fn.MaybeSetInferredAtlasAndImageCache(prefab)
  if not prefab or not GetInventoryItemAtlas then
    return
  end

  local image = prefab .. ".tex"
  local atlas = GetInventoryItemAtlas(image, true)
  if atlas then
    fn.SetAtlasAndImageCache(prefab, atlas, image, "inferred")
    return true
  end
end

function fn.GetAtlasAndImageFromCache(prefab)
  return unpack(state.atlas_image_cache[prefab] or {})
end

-- [修复] 验证 atlas/image 引用有效(资源已加载且含该 region)。
-- 关键场景：服务端 mod(all_clients_require_mod)物品常未注册 atlas 查询表，
-- replica 的 GetAtlas 会兜底到 inventoryimages4 的错误路径，渲染成空白；
-- 未验证的错误数据若进了缓存还会以"真实来源"身份污染磁盘图标缓存。
-- AtlasContains 不可用时放行(保守降级)。
function fn.AtlasIsValid(atlas, image)
  return TheSim.AtlasContains == nil or TheSim:AtlasContains(atlas, image)
end

function fn.SetAtlasAndImageCache(prefab, atlas, image, source)
  -- [本地修改] 第三项 source 标记缓存来源：nil=本会话真实来源 / "inferred"=按
  -- prefab 名推断 / "disk"=磁盘缓存。推断与磁盘来源允许被真实图标(皮肤等)
  -- 特殊图标)覆盖；真实来源写入时顺带标记磁盘缓存待写盘
  -- [修复] 不在此处统一验证：真实来源(物品入手/装备/spawn 探测已单独验证)
  -- 的数据引擎自身在用(含皮肤图标, 其皮肤 atlas 可能未注册进查询表,
  -- 会被 AtlasContains 误杀)。磁盘条目在渲染时验证(那时资源已加载)。
  state.atlas_image_cache[prefab] = { atlas, image, source }

  if source == nil then
    fn.MarkIconStoreDirty()
  end
end

-- [本地修改] 图标缓存数据升级后重画对应按钮(kill + 下周期重建)。
-- 升级场景：fallback 方块 -> 真实图标；spawn 探测的基础图标 ->
-- 真实皮肤图标；磁盘/推断来源 -> 真实图标。
-- MaybeSetAtlasAndImageCache 有"真实来源不再重算"保护，每次写入都是
-- 一次真正的数据升级，重画至多一次，无闪烁风暴。
function fn.RefreshIconButtonIfAny(prefab)
  if prefab and state.image_buttons[prefab] then
    local slot = fn.GetSlot(prefab)
    if slot then
      fn.ClearSlotIcon(prefab)
      fn.OnNextCycle(function()
        fn.RenderSlotIcons(slot)
      end)
    end
  end
end

function fn.GetAtlasAndImageFromItem(item)
  if not item then
    return nil
  end

  local inventoryitem = fn.GetComponent(item, "inventoryitem", state.is_dst)
  if inventoryitem == nil then
    return nil
  end

  local atlas, image

  if state.is_mastersim and item.components then
    -- [修复] master 端直读组件明文字段，绕过 net_hash：
    -- 皮肤图标经 ChangeImageName(skinname) 下发，驻留表溢出时
    -- replica GetImage() 返回 hash 数字，而组件字段是明文字符串
    local comp = item.components.inventoryitem
    if comp then
      image = comp.imagename ~= nil and (comp.imagename .. ".tex") or nil
      atlas = comp.atlasname
    end
  else
    atlas, image = inventoryitem:GetAtlas(), inventoryitem:GetImage()
  end

  -- [修复] client 端 net_hash 字符串驻留表溢出(模组多时)时 value()
  -- 返回 hash 数字(king_cane/yellowstaff 实证)，无法渲染且会污染缓存：
  --   * image 数字 → 反解表还原成字符串
  --   * atlas 数字 → 无法反解，丢弃后按还原的 image 名重查官方图集
  if type(image) == "number" then
    image = fn.UnhashTex(image)
  end
  if type(atlas) == "number" then
    atlas = nil
  end

  if type(image) == "string" and image ~= "" then
    if atlas == nil or atlas == "" then
      -- no_fallback=true：查不到返回 nil 而非误拿 images4 错误路径
      atlas = GetInventoryItemAtlas(image, true)
    end
    if type(atlas) == "string" and atlas ~= "" then
      return atlas, image
    end
  elseif state.is_mastersim and item.prefab then
    -- master 端 imagename 为 nil → 无自定义图标 → 按名推断基础图标
    image = item.prefab .. ".tex"
    atlas = GetInventoryItemAtlas(image, true)
    if atlas ~= nil then
      return atlas, image
    end
  end
end

-- [修复] 在身上的物品里查找指定 prefab 的实体(物品栏/背包/装备栏)。
-- 皮肤图标经 inventoryitem 的 imagename 网络变量下发(ChangeImageName)，
-- 只有活体物品能读到最新的皮肤图标；按 prefab 缓存的值可能是过期的基础图标。
function fn.FindLiveItem(prefab)
  if not prefab or not state.inventory then
    return nil
  end

  local found = nil

  if state.inventory.EachItem then
    state.inventory:EachItem(function(item)
      if found == nil and item ~= nil and item.prefab == prefab then
        found = item
      end
    end)
  end

  if found == nil and state.overflow and state.overflow.EachItem then
    state.overflow:EachItem(function(item)
      if found == nil and item ~= nil and item.prefab == prefab then
        found = item
      end
    end)
  end

  if found == nil then
    local inventory = state.inventory.inventory
    if inventory and inventory.GetEquips then
      for _, item in pairs(inventory:GetEquips() or {}) do
        if item ~= nil and item.prefab == prefab then
          found = item
          break
        end
      end
    end
  end

  return found
end

-- [修复] net_hash 数字反解：把 hash(tex名) 还原成 tex 字符串。
-- 数据源：PREFAB_SKINS(官方皮肤名全清单，prefabskins.lua 自动生成)
-- + GLOBAL.Prefabs(全部已注册 prefab，含 mod 物品基础名)。
-- 懒加载(首次遇到数字时构建，此时 prefab 注册已完成)；
-- hash 冲突时保留先见条目，误还原最多表现为显示另一合法图标。
local hash_tex_lookup = nil

function fn.BuildHashTexLookup()
  if hash_tex_lookup ~= nil then
    return hash_tex_lookup
  end

  hash_tex_lookup = {}

  if hash == nil then
    return hash_tex_lookup
  end

  local skins = GLOBAL.PREFAB_SKINS
  if type(skins) == "table" then
    for _, names in pairs(skins) do
      if type(names) == "table" then
        for _, name in ipairs(names) do
          local tex = name .. ".tex"
          local h = hash(tex)
          if hash_tex_lookup[h] == nil then
            hash_tex_lookup[h] = tex
          end
        end
      end
    end
  end

  local prefabs = GLOBAL.Prefabs
  if type(prefabs) == "table" then
    for name, _ in pairs(prefabs) do
      if type(name) == "string" then
        local tex = name .. ".tex"
        local h = hash(tex)
        if hash_tex_lookup[h] == nil then
          hash_tex_lookup[h] = tex
        end
      end
    end
  end

  return hash_tex_lookup
end

function fn.UnhashTex(num)
  if type(num) ~= "number" then
    return nil
  end
  return fn.BuildHashTexLookup()[num]
end

function fn.GetAtlasAndImageFromLiveItem(prefab)
  local item = fn.FindLiveItem(prefab)
  if item == nil then
    return nil
  end

  local atlas, image = fn.GetAtlasAndImageFromItem(item)
  -- [修复] 活体数据必须是字符串：replica GetImage/GetAtlas 走
  -- classified 的 net_hash，引擎字符串驻留表溢出(模组多时)时 value()
  -- 返回 hash 数字(king_cane 等)，数字无法渲染(ImageButton 渲染数字报
  -- "Invalid resource handle for atlas 'FROMNUM'")，且作为"真实来源"
  -- 写缓存后会固化并覆盖磁盘字符串条目。拒绝后由缓存/按名推断兜底
  if  atlas and image and
      type(atlas) == "string" and type(image) == "string" and
      atlas ~= "" and image ~= "" then
    return atlas, image
  end
end

-- [修复] 从身上物品重新同步图标缓存：皮肤同步/换肤可能晚于图标渲染，
-- 发现缓存与活体物品不一致时更新缓存并重画该图标。
function fn.ResyncIconsFromLiveItems()
  if not state.inventory or next(state.items) == nil then
    return
  end

  for _, prefabs in pairs(state.items) do
    for _, prefab in ipairs(prefabs) do
      local atlas, image = fn.GetAtlasAndImageFromLiveItem(prefab)
      if atlas and image then
        local cached_atlas, cached_image = fn.GetAtlasAndImageFromCache(prefab)
        if cached_atlas ~= atlas or cached_image ~= image then
          print("[SES-FIX] icon resync (skin): " .. tostring(prefab) ..
            " " .. tostring(cached_image) .. " -> " .. tostring(image))
          fn.SetAtlasAndImageCache(prefab, atlas, image)
          fn.RefreshIconButtonIfAny(prefab)
        end
      end
    end
  end
end

-- 进入世界后皮肤数据可能延迟下发，分几个时点重同步
function fn.ScheduleIconResync()
  for _, delay in ipairs({ 1, 3, 8, 20, 40 }) do
    tasker:DoTaskInTime(delay, fn.ResyncIconsFromLiveItems)
  end
end

function fn.GetAtlasAndImage(prefab)
  if not prefab then
    return nil
  end

  -- [修复] 优先读身上活体物品的图标：皮肤图标经 imagename 网络变量下发，
  -- 按 prefab 缓存的值可能是过期的无皮肤基础图标；活体数据永远最新
  local live_atlas, live_image = fn.GetAtlasAndImageFromLiveItem(prefab)
  if live_atlas and live_image then
    local cached_atlas, cached_image = fn.GetAtlasAndImageFromCache(prefab)
    if cached_atlas ~= live_atlas or cached_image ~= live_image then
      fn.SetAtlasAndImageCache(prefab, live_atlas, live_image)
      fn.RefreshIconButtonIfAny(prefab)
    end
    return live_atlas, live_image
  end

  local atlas, image, source = fn.GetAtlasAndImageFromCache(prefab)
  if atlas and image then
    -- [修复] 防御性清理非字符串条目(hash 数字污染的旧缓存)，
    -- 清除后 LoadIconStore 的磁盘字符串条目可重新写入；
    -- 磁盘条目在渲染时验证(mod 卸载残留/主菜单阶段无法验证)：
    -- 进世界后 atlas 资源已加载，AtlasContains 结果可靠，
    -- 未通过的视为缓存 miss，退回推断/fallback
    if type(atlas) ~= "string" or type(image) ~= "string" or atlas == "" or image == "" then
      state.atlas_image_cache[prefab] = nil
    elseif source ~= "disk" or fn.AtlasIsValid(atlas, image) then
      return atlas, image
    end
  end

  if not state.is_mastersim then
    -- DST Client Mode cannot spawn a complete prefab so if atlas/image
    -- are not already in the cache we will stop here.
    -- However, every applicable item's atlas + image will be put in the cache
    -- when it is first obtained.
    -- [修复] 物品不在身上时先按 prefab 名推断图标(官方物品与已注册
    -- atlas 的 mod 物品都能直接查到)，避免渲染成 fallback 方块
    if fn.MaybeSetInferredAtlasAndImageCache(prefab) then
      return fn.GetAtlasAndImageFromCache(prefab)
    end
    return nil
  end

  -- Atlas and image will be read from a spawned instance of the prefab.
  atlas, image = fn.FromSpawnedPrefab(prefab, fn.GetAtlasAndImageFromItem)

  -- [修复] spawn 探测结果验证后再采用：未注册 atlas 的服务端 mod 物品会拿到
  -- images4 兜底错误路径(渲染空白)；验证失败退回按名推断，
  -- 仍查不到才渲染成 fallback 方块(等物品入手/磁盘缓存提供真实数据)
  if atlas and image and fn.AtlasIsValid(atlas, image) then
    -- [修复] spawn 探测标记为 "spawn" 来源：spawn 出的是无皮肤基础物品，
    -- 图标必为基础图标；玩家入手/装备带皮肤物品时的真实数据(含皮肤)
    -- 必须能覆盖它，否则皮肤物品永远显示基础图标
    fn.SetAtlasAndImageCache(prefab, atlas, image, "spawn")
    return atlas, image
  end

  -- [修复] spawn 探测失败(无效 prefab 名等，如配置文件残留已却载 mod 的
  -- 物品)时退回按名字推断，仍查不到才渲染成 fallback 方块
  if fn.MaybeSetInferredAtlasAndImageCache(prefab) then
    return fn.GetAtlasAndImageFromCache(prefab)
  end
end

-- Spawns the given prefab and returns the value that is returned by value_fn.
-- Note: DST Client Mode will not return a full instance (it misses many components) so use with care there.
function fn.FromSpawnedPrefab(prefab, value_fn)
  local guid = TheSim:SpawnPrefab(prefab)
  local spawn = Ents[guid]
  if spawn then
    local value = {value_fn(spawn)}
    spawn:Remove()
    return unpack(value)
  end
end

function fn.CreateImageButton(prefab)
  if  not state.inventorybar or
      not state.inventorybar.toprow then
    return
  end

  local atlas, image = fn.GetAtlasAndImage(prefab)

  local image_button
  local is_fallback = false
  if not atlas or not image then
    -- [日志] 仅异常路径打印(方块兜底)，正常渲染不刷屏
    print("[SES-FIX] fallback icon: " .. tostring(prefab))
    image_button = fn.CreateFallbackImageButton(prefab)
    is_fallback = true
  else
    image_button = ImageButton(atlas, image)
    image_button:SetScale(state.config.slot_icon_scale)
    image_button.image:SetTint(1,1,1, state.config.slot_icon_opacity)
  end

  image_button.Kill = fn.ImageButton_Kill(image_button.Kill, prefab)
  state.inventorybar.toprow:AddChild(image_button)

  return image_button, is_fallback
end

function fn.GetPrefabDisplayName(prefab)
  if not prefab or not DisplayNames or type(DisplayNames) ~= "table" then
    return prefab
  end

  return DisplayNames[string.upper(prefab)]
end

function fn.CreateFallbackImageButton(prefab)
  local image_button = ImageButton("images/global.xml", "square.tex")
  local base_opacity = .5
  image_button.image:SetTint(0,0,0, base_opacity * state.config.slot_icon_opacity)
  local base_scale = .6
  image_button:SetScale(base_scale * state.config.slot_icon_scale)

  local display_name = fn.GetPrefabDisplayName(prefab)
  if display_name then
    image_button:SetTooltip(display_name)
  end

  return image_button
end

-- Clears image button cache for the given prefab when the ImageButton is killed
function fn.ImageButton_Kill(original_fn, prefab)
  return function(self)
    -- Original Kill()
    original_fn(self)

    -- Clear cache
    state.image_buttons[prefab] = nil
    -- [本地修改] 同步清除 fallback/重建标记
    state.fallback_buttons[prefab] = nil
    state.rerendered_buttons[prefab] = nil
  end
end

-- Runs the given function on the next processing cycle,
-- after all current threads have finished or yielded
function fn.OnNextCycle(onNextCycle)
  tasker:DoTaskInTime(0, onNextCycle)
end

function fn.RenderSlotIcons(slot)
  if not state.config.show_slot_icons or not state.items[slot] or not state.inventorybar then
    return
  end

  local invslot = state.inventorybar.inv[slot]
  if not invslot then
    return
  end

  for item_index, prefab in ipairs(state.items[slot]) do
    local image_button = state.image_buttons[prefab]
    if not image_button then
      local is_fallback
      image_button, is_fallback = fn.CreateImageButton(prefab)

      if not image_button then
        return
      end

      state.image_buttons[prefab] = image_button

      if is_fallback then
        -- [本地修改] 记录 fallback 状态，供缓存就绪时精确替换
        state.fallback_buttons[prefab] = true
        -- [修复] fallback 方块可能只是图标资源尚未就绪(classified 同步竞态等)，
        -- 安排几次延迟自愈：缓存就绪后自动替换为真实图标
        fn.ScheduleIconHeal(slot)
      else
        -- [修复] 推断/磁盘来源的图标按钮：刚进世界时 atlas 资源可能尚未
        -- 加载完，渲染成空白且引擎不会重试，安排延迟重建。
        -- (spawn 来源已通过 AtlasIsValid 验证，无需重建；皮肤等数据
        -- 升级走 MaybeSetAtlasAndImageCache 的覆盖重画)
        local _, _, source = fn.GetAtlasAndImageFromCache(prefab)
        if source == "inferred" or source == "disk" then
          fn.ScheduleIconRerender(prefab)
        end
      end
    end

    image_button:SetOnClick(function()
      if  state.config.disable_slot_icon_click_when_save_slots_off and
          state.disable_save_slots then
        -- Ignore click in this case
        return
      end

      fn.ClearSlot(prefab, slot)
    end)

    fn.UpdateImageButtonPosition(image_button, item_index, invslot)
  end
end

function fn.UpdateImageButtonPosition(image_button, item_index, invslot)
  local invslot_pos = invslot:GetLocalPosition()

  if invslot_pos and invslot.bgimage then
    local _, invslot_height = invslot.bgimage:GetSize()

    if invslot_height then
      local _, image_button_height = image_button:GetSize()

      if image_button_height then
        -- Respect configured scale
        image_button_height = image_button_height * state.config.slot_icon_scale

        -- Offset between top of inventory bar and start of image button
        local offset = image_button_height / 2
        -- Vertical spacing between icons
        local spacing = image_button_height / 5

        local initial_pos_y = invslot_pos.y + (invslot_height * state.config.slot_icon_offset) + offset
        local delta_y = (item_index - 1) * (spacing + image_button_height)

        image_button:SetPosition(invslot_pos.x, initial_pos_y + delta_y)
        if image_button.o_pos then
          -- The game itself stores some "original position"
          -- when a button is focused and updates the button's position
          -- to that position when the button loses focus.
          -- However, this does not work properly in some cases when we
          -- have already shifted the button position, causing the game
          -- to move the button back to some previous position.
          -- Thus, we also update this (internal) o_pos value when
          -- it has a value.
          image_button.o_pos = image_button:GetLocalPosition()
        end
      end
    end
  end
end

function fn.RefreshImageButtons()
  for prefab, _ in pairs(state.image_buttons) do
    fn.ClearSlotIcon(prefab)
    fn.OnNextCycle(function()
      local slot = fn.GetSlot(prefab)
      if slot then
        fn.RenderSlotIcons(slot)
      end
    end)
  end
end

-- fallback 方块的自愈重试时点(秒)，也用作图标重建时点
local ICON_HEAL_DELAYS = { 1, 3, 8, 20 }

-- [修复] 推断/磁盘来源的图标按钮在刚进世界时可能因 atlas 资源尚未加载完
-- 而渲染成空白(引擎对未就绪纹理不重试，也没有重建机会)。
-- 安排几次延迟重建：AtlasContains 确认资源就绪后重建一次让引擎重新解析
-- 纹理；最末一轮无条件重建兑底(防 AtlasContains 行为异常)。
function fn.ScheduleIconRerender(prefab)
  -- 已成功重建过则不再排任务(按钮 Kill 后标记重置，可再走一轮，
  -- 覆盖 inventorybar 重建后新按钮仍空白的场景)
  if state.rerendered_buttons[prefab] then
    return
  end

  for i, delay in ipairs(ICON_HEAL_DELAYS) do
    tasker:DoTaskInTime(delay, function()
      local entry = state.atlas_image_cache[prefab]
      if  entry ~= nil and state.image_buttons[prefab] ~= nil and
          not state.rerendered_buttons[prefab] then
        local ready = i >= #ICON_HEAL_DELAYS or
          (TheSim.AtlasContains ~= nil and TheSim:AtlasContains(entry[1], entry[2]))

        if ready then
          local slot = fn.GetSlot(prefab)
          if slot ~= nil then
            print("[SES-FIX] rerender: " .. tostring(prefab))
            fn.ClearSlotIcon(prefab)
            -- 重建前设置标记：Kill 钩子会清标记，必须放在 Kill 之后、
            -- 重画之前，防止新按钮再次挂上重建任务形成循环
            state.rerendered_buttons[prefab] = true
            fn.OnNextCycle(function()
              fn.RenderSlotIcons(slot)
            end)
          end
        end
      end
    end)
  end
end

-- [修复] 槽位图标渲染成 fallback 方块后的延迟自愈：
-- 定时从物品栏/装备栏/背包补充图标缓存；缓存就绪(或由推断升级为真实来源)
-- 的 prefab 会经 RefreshFallbackIconIfay 自动重画，本函数只负责喂数据。
-- 仅 client 模式需要(master 模式的 spawn 探测已能即时解析)。
function fn.ScheduleIconHeal(slot)
  -- [修复] master 模式也参与自愈：spawn 探测对未注册 atlas 的服务端
  -- mod 物品不可靠，需要从身上物品补充真实来源缓存
  for _, delay in ipairs(ICON_HEAL_DELAYS) do
    tasker:DoTaskInTime(delay, function()
      local prefabs = state.items[slot]
      if not prefabs then
        return
      end

      -- 所有 prefab 都已有本会话真实来源缓存则无事可做
      local need = false
      for _, prefab in ipairs(prefabs) do
        local _, _, source = fn.GetAtlasAndImageFromCache(prefab)
        if not state.atlas_image_cache[prefab] or source ~= nil then
          need = true
          break
        end
      end

      if need then
        fn.PopulateIconCacheFromInventory()
      end
    end)
  end
end

function fn.ClearSlotIcons()
  for prefab, _ in pairs(state.image_buttons) do
    fn.ClearSlotIcon(prefab)
  end
end

function fn.ShowDisableStatusText(duration)
  if not state.disable_save_slots_text_widget then
    return
  end

  if state.disable_save_slots_animation ~= nil then
    state.disable_save_slots_animation:Cancel()
  end

  state.disable_save_slots_text_widget:SetString("Save Slots - "..(state.disable_save_slots and "OFF" or "ON"))
  state.disable_save_slots_text_widget:Show()

  state.disable_save_slots_animation = tasker:DoTaskInTime(duration, function()
    state.disable_save_slots_text_widget:Hide()
    state.disable_save_slots_animation = nil
  end)
end

function fn.InitDisableSaveSlotsStatusText()
  if not state.inventorybar then return end

  local text = Text(GLOBAL.UIFONT, 42, nil)
  text:Hide()
  text:SetVAlign(GLOBAL.ANCHOR_MIDDLE)
  text:SetHAlign(GLOBAL.ANCHOR_TOP)
  text:SetVAnchor(GLOBAL.ANCHOR_TOP)
  text:SetHAnchor(GLOBAL.ANCHOR_MIDDLE)
  text:SetPosition(0,-100,0)

  state.inventorybar:AddChild(text)

  state.disable_save_slots_text_widget = text
end

function fn.ClearSlotIcon(prefab)
  local image = state.image_buttons[prefab]

  if image then
    image:Kill()
    state.image_buttons[prefab] = nil
  end
end

function fn.RemoveFromTable(tbl, func, one)
  if type(tbl) == "table" then
    for i = #tbl, 1, -1 do
      if func(tbl[i]) then
        table.remove(tbl, i)
        if one then return end
      end
    end
  end
end

function fn.ClearTable(tbl)
  for k, _ in pairs(tbl) do
    tbl[k] = nil
  end
end

function fn.CallOrValue(v, ...)
  if type(v) == "function" then
    return v(...)
  else
    return v
  end
end

function fn.GetComponent(o, component_name, get_replica)
  if o then
    if state.is_mastersim and not get_replica then
      return o.components and o.components[component_name]
    else
      return o.replica and o.replica[component_name]
    end
  end
end

function fn.IfHasComponent(o, component_name, ifFn, ifNot)
  local component = fn.GetComponent(o, component_name)

  if component then
    if type(ifFn) == "function" then
      return ifFn(component)
    else
      return component
    end
  else
    return fn.CallOrValue(ifNot)
  end
end

function fn.GetDurability(item)
  local percent

  if state.is_mastersim then
    percent = fn.IfHasComponent("finiteuses", function(fu)
      return fu:GetPercent()
    end)
  else
    local key = item and item.GUID
    percent = key and state.durability.items[key]
  end

  -- Never return nil, if no percentage is available we treat it as
  -- an item with infinite durability (e.g., Lucy)
  return percent or 1
end

function fn.GetSlot(prefab)
  if prefab then
    return state.slots[prefab]
  end
end

function fn.SaveSlot(prefab, slot)
  local prev_slot = fn.GetSlot(prefab)
  if prev_slot then
    fn.ClearSlot(prefab, prev_slot)
  end

  if not state.items[slot] then
    state.items[slot] = {}
  end

  table.insert(state.items[slot], prefab)

    -- Update slot table as items has been changed
  state.slots = fn.GetItemSlots()

  fn.RenderSlotIcons(slot)

  -- [本地修改] 同步到本地持久化文件
  fn.FlushPersistedSlots()
end

function fn.ClearSlot(prefab, slot)
  if not prefab or not slot or not state.items[slot] then
    return
  end

  -- Remove from items
  fn.RemoveFromTable(state.items[slot], function(p) return p == prefab end, true)

  -- Remove entire key if this was the last item
  if #state.items[slot] == 0 then
    state.items[slot] = nil
  end

  fn.ClearSlotIcon(prefab)

  -- Update slot table as items has been changed
  state.slots = fn.GetItemSlots()

  fn.RenderSlotIcons(slot)

  -- [本地修改] 同步到本地持久化文件
  fn.FlushPersistedSlots()
end

function fn.ClearEntireSlot(slot)
  if type(state.items[slot]) ~= "table" then return end

  for i = #state.items[slot], 1, -1 do
    fn.ClearSlot(state.items[slot][i], slot)
  end
end

function fn.HasSlot(prefab)
  return fn.GetSlot(prefab) ~= nil
end

function fn.ApplyToItem(item)
  if not item then
    return false
  end

  local apply = state.config.apply_to_items
  if apply == "all" then return true end

  if apply.equipment and fn.IsEquipment(item) then return true end
  if apply.food and fn.IsFood(item) then return true end
  if apply.healer and fn.IsHealer(item) then return true end

  return false
end

function fn.IsEquipment(item)
  return fn.GetComponent(item, "equippable") ~= nil
end

function fn.IsFood(item)
  if not item then return false end

  if state.is_mastersim then
    local edible = fn.GetComponent(item, "edible")
    if not edible then return false end
    local player = fn.GetPlayer()
    local eater = player and fn.GetComponent(player, "eater")
    if not eater or type(eater.CanEat) ~= "function" then return false end
    return eater:CanEat(item)
  else
    return fn.ItemHasAction(item, ACTIONS.EAT)
  end
end

function fn.IsHealer(item)
  if state.is_mastersim then
    return fn.GetComponent(item, "healer") ~= nil
  else
    return fn.ItemHasAction(item, ACTIONS.HEAL)
  end
end

function fn.ItemHasAction(item, target_action)
  if not item or type(item.CollectActions) ~= "function" then
    return false
  end

  local player = fn.GetPlayer()
  if not player then return false end

  local actions = {}
  item:CollectActions("INVENTORY", player, actions, true)
  for _, action in ipairs(actions) do
    if action == target_action then
      return true
    end
  end

  return false
end

function fn.GetEquipSlot(item)
  return fn.IfHasComponent(item, "equippable", function(eq)
    local equipslot = eq.EquipSlot and eq:EquipSlot() or eq.equipslot
    return equipslot
  end)
end

function fn.GetOverflowContainer(inventory)
  if not state.is_mastersim then
    return inventory:GetOverflowContainer()
  else
    return fn.IfHasComponent(inventory.overflow, "container")
  end
end

-- Works like Inventory:GetNextAvailableSlot, but first tries to find
-- space outside of the saved slots. When that fails it will revert to the
-- default implementation
function fn.TrySkipSavedSlots(inventory, item, original_fn)
  fn.ReserveSavedSlots(inventory)
  local original_slot, original_container = original_fn(inventory, item)
  fn.UndoReserveSavedSlots(inventory)

  if original_slot == nil and original_container == inventory.itemslots then
    -- Game reports no space, but is unaware of the overflow in most scenarios
    -- so we will check it again ourselves and put the item there if possible
    local container = fn.GetOverflowContainer(inventory)
    local overflow = state.is_dst and container or inventory.overflow

    if container then
      for i = 1, container.numslots do
        if container.slots[i] == nil then
          if container:GiveItem(item, nil, nil, false, true) then
            return 0, overflow
          end
        end
      end
    end

    -- When reserve saved slots is set to "If Free Slots"
    -- we try again since there appear to be no free slots.
    -- The previously reserved saved slots are already unblocked now.
    if state.config.reserve_saved_slots == "if_free_slots" then
      original_slot, original_container = original_fn(inventory, item)
    end
  end

  return original_slot, original_container
end

function fn.Inventory_GetNextAvailableSlot(original_fn)
  return function(self, item)
    local saved_slot = fn.GetSlot(item.prefab)

    if not saved_slot or not fn.ApplyToItem(item) then
      if state.config.reserve_saved_slots then
        return fn.TrySkipSavedSlots(self, item, original_fn)
      else
        return original_fn(self, item)
      end
    end

    if not state.inventory then
      return original_fn(self, item)
    end

    local made_space = state.inventory:MakeSpace(saved_slot, item)

    if not made_space then
      if state.config.reserve_saved_slots then
        return fn.TrySkipSavedSlots(self, item, original_fn)
      else
        -- Let the game decide where to put the new equipment.
        -- This would be the behavior of the normal game
        return original_fn(self, item)
      end
    else
      -- saved_slot is available
      return saved_slot, self.itemslots
    end
  end
end

function fn.Inventory_Equip(original_fn)
  return function(self, item, old_to_active)
    state.is_equipping = true
    local original_return = original_fn(self, item, old_to_active)
    state.is_equipping = false
    return original_return
  end
end

function fn.Player_OnEquip(_, data)
  local item = data.item

  if not fn.ApplyToItem(item) then
    return
  end

  if state.is_mastersim then
    -- There is a strange bug in the base
    -- game where equipment that has ever been in
    -- your backpack will go straight back to the backback
    -- when unequipped, even if you have put it in your regular
    -- inventory afterwards. This is different from the behavior
    -- without a backpack, the game will (even without this mod)
    -- always try to put equipment back where it came from.
    -- We will fix this here by simply clearing the item's prevcontainer
    -- whenever it is equipped, which would point to the backpack when it was ever in there.
    item.prevcontainer = nil

    -- We also clear the item's prevslot to prevent the game from trying
    -- to put it there when unequipping the item, as this is not always
    -- what we would want when we have multiple copies of an equipment.
    -- For example, when we have assigned the Axe to slot 2 but have picked up
    -- a second copy that is now stored in slot 3, we do not want the game
    -- to try to put it back directly to slot 3 when unequipping, as slot 2
    -- might be available at that time. The game bypasses the GetNextAvailableSlot()
    -- function when prevslot has a value and is available, so we clear it here.
    item.prevslot = nil

    -- [修复] master 模式也补真实来源图标缓存(装备事件是可靠来源，
    -- spawn 探测对未注册 atlas 的服务端 mod 物品不可靠)
    fn.MaybeSetAtlasAndImageCache(item.prefab, function()
      return fn.GetAtlasAndImageFromItem(item)
    end)
  else
    -- Client Mode: If we just equipped a container component this is some kind of backpack
    -- so we initialize the proper logic to handle it
    fn.IfHasComponent(item, "container", fn.InitOverflow)
    fn.ListenForDurabilityChanges(item)

    -- [修复] 装备中的物品不在物品栏迭代范围内，趁 equip 事件补充图标缓存；
    -- 跨 shard 迁移/读档时物品直接出现在装备槽，不会经过 itemget
    fn.MaybeSetAtlasAndImageCache(item.prefab, function()
      return fn.GetAtlasAndImageFromItem(item)
    end)
  end
end

function fn.IsMasterSim()
  if not state.is_dst then
    return true
  end

  if GLOBAL.TheWorld then
    return not not GLOBAL.TheWorld.ismastersim
  else
    return true
  end
end

-- ===========================================================================
-- [本地修改] 跨 shard 本地持久化
--
-- DST 的地表与洞穴是两个独立进程(shard)，client-only mod 不会在洞穴端
-- 运行，装备槽配置随世界存档留在地表 shard，导致下洞穴后配置丢失。
--
-- 这里将配置额外保存到本机客户端持久化目录
-- (Documents/Klei/DoNotStarveTogether/<KleiID>/client_save/)：
--   * 文件按"服务器"维度命名，同一集群的地表/洞穴读写同一文件；
--   * Master/Client 两种模式下配置变更都会写回文件；
--   * 加载时世界存档(Inventory.OnLoad)优先，文件仅用于填补空白，
--     作为跨 shard、跨重登的数据载体。
-- ===========================================================================

local PERSIST_FILE_PREFIX = "ses_fix_slots_"
local PERSIST_VERSION = 1

-- [本地修改] 图标引用磁盘缓存：独立于槽位配置，全局一份(图标与服务器无关)。
-- 解决"重上游戏后物品不在身上，且图标未注册进 atlas 查询表的 mod 物品
-- 渲染成 fallback 方块"——入手真实物品时把 atlas/image 引用防抖写盘，
-- 重启后直接复用(mod 已卸载的条目由 AtlasContains 校验自动忽略)
local ICON_STORE_FILE = "ses_fix_icon_cache"
local ICON_STORE_VERSION = 1
local ICON_STORE_MAX_ENTRIES = 500

-- 真实来源图标写入内存缓存后防抖合并写盘
function fn.MarkIconStoreDirty()
  if not state.is_dst then
    return
  end

  if state.icon_store_flush_task == nil then
    state.icon_store_flush_task = tasker:DoTaskInTime(2, function()
      state.icon_store_flush_task = nil
      fn.FlushIconStore()
    end)
  end
end

function fn.FlushIconStore()
  local icons = {}
  local count = 0

  for prefab, entry in pairs(state.atlas_image_cache) do
    if entry[3] == nil then
      -- 只存“推断无法复现”的条目：按名推断只用 prefab..".tex"(基础图标)，
      -- 无法还原皮肤图标(皮肤图像名与 prefab 不同)，因此
      --   * 图像名不是基础名(皮肤图标) -> 必须入盘
      --   * 基础图标但 atlas 未注册(旧式 mod 物品) -> 必须入盘
      --   * 基础图标且推断可命中 -> 跳过(重启后推断即可)
      local base_image = prefab .. ".tex"
      local inferable = GetInventoryItemAtlas ~= nil and
        GetInventoryItemAtlas(base_image, true) ~= nil
      local is_base_image = entry[2] == base_image
      if not inferable or not is_base_image then
        icons[prefab] = { entry[1], entry[2] }
        count = count + 1
        if count >= ICON_STORE_MAX_ENTRIES then
          break
        end
      end
    end
  end

  local ok, encoded = pcall(json.encode, {
    version = ICON_STORE_VERSION,
    icons = icons,
  })

  if ok and encoded then
    TheSim:SetPersistentString(ICON_STORE_FILE, encoded, false)
  end
end

-- 启动时异步加载磁盘图标缓存(可在任意渲染之前或之后完成，两种顺序都闭环)
function fn.LoadIconStore()
  if not state.is_dst or state.icon_store_loaded then
    return
  end
  state.icon_store_loaded = true

  TheSim:GetPersistentString(ICON_STORE_FILE, function(success, str)
    if not (success and str and #str > 0) then
      return
    end

    local ok, decoded = pcall(json.decode, str)
    if not (ok and type(decoded) == "table" and decoded.version == ICON_STORE_VERSION and type(decoded.icons) == "table") then
      return
    end

    local loaded = 0
    for prefab, entry in pairs(decoded.icons) do
      if  type(prefab) == "string" and type(entry) == "table" and
          type(entry[1]) == "string" and type(entry[2]) == "string" and
          entry[1] ~= "" and entry[2] ~= "" then
        -- [修复] 不在加载时校验：主菜单阶段 atlas 尚未加载，AtlasContains
        -- 全为 false 会误拒全部条目。
        -- 磁盘条目统一在渲染时验证(GetAtlasAndImage)。
        local atlas, _, source = fn.GetAtlasAndImageFromCache(prefab)
        -- 不覆盖本会话真实来源(优先线上数据)
        if not atlas or source ~= nil then
          fn.SetAtlasAndImageCache(prefab, entry[1], entry[2], "disk")
          loaded = loaded + 1
        end
      end
    end

    if loaded > 0 then
      print("[SES-FIX] icon store loaded: " .. loaded .. " entries")
      -- 磁盘条目可能升级现有按钮(fallback 方块 / spawn 基础图标 -> 真实图标)
      local pending = {}
      for prefab in pairs(state.image_buttons) do
        table.insert(pending, prefab)
      end
      for _, prefab in ipairs(pending) do
        fn.RefreshIconButtonIfAny(prefab)
      end
    end
  end)
end

local function GetPersistFilename()
  local key = "unknown"

  local server_name = TheNet and TheNet.GetServerName and TheNet:GetServerName() or nil
  if server_name and #server_name > 0 then
    key = server_name:gsub("%s+", ""):gsub("%W", "")
  end

  if #key == 0 then
    key = "unknown"
  end

  -- 文件名长度保护
  if #key > 40 then
    key = key:sub(1, 40)
  end

  return PERSIST_FILE_PREFIX .. key
end

-- 将当前配置写入本地持久化文件(引擎异步写盘，文件极小，开销可忽略)
function fn.FlushPersistedSlots()
  if not state.is_dst then
    return
  end

  local ok, encoded = pcall(json.encode, {
    version = PERSIST_VERSION,
    items = state.items,
  })

  if ok and encoded then
    TheSim:SetPersistentString(GetPersistFilename(), encoded, false)
  end
end

-- 从当前物品栏与装备栏补充图标缓存。
-- client 模式无法凭空生成图标资源(GetAtlasAndImage 仅查缓存)，
-- 且装备中的物品不在普通物品槽迭代范围内，需要单独补充。
function fn.PopulateIconCacheFromInventory()
  if state.inventory and state.inventory.EachItem then
    state.inventory:EachItem(function(item)
      if fn.HasSlot(item.prefab) then
        fn.MaybeSetAtlasAndImageCache(item.prefab, function()
          return fn.GetAtlasAndImageFromItem(item)
        end)
      end
    end)
  end

  -- [修复] 背包(overflow 容器)里的物品也要进缓存：
  -- 上面的 EachItem 只遍历主物品栏，放在背包里的装备(备用手杖等)
  -- 永远补不到缓存，槽位图标会一直是方块
  if state.overflow and state.overflow.EachItem then
    state.overflow:EachItem(function(item)
      if item and item.prefab and fn.HasSlot(item.prefab) then
        fn.MaybeSetAtlasAndImageCache(item.prefab, function()
          return fn.GetAtlasAndImageFromItem(item)
        end)
      end
    end)
  end

  local inventory = state.inventory and state.inventory.inventory
  if inventory and inventory.GetEquips then
    for _, item in pairs(inventory:GetEquips() or {}) do
      if item and item.prefab and fn.HasSlot(item.prefab) then
        fn.MaybeSetAtlasAndImageCache(item.prefab, function()
          return fn.GetAtlasAndImageFromItem(item)
        end)
      end
    end
  end
end

-- 从本地持久化文件恢复配置(异步)。
-- 在 InitInventory 中调用，由回调统一决定最终配置并回写文件：
-- 世界存档(Inventory.OnLoad)已恢复时不动，文件仅用于填补空白。
function fn.LoadPersistedSlots()
  if not state.is_dst then
    return
  end

  TheSim:GetPersistentString(GetPersistFilename(), function(success, str)
    -- 解析文件，把 json 的字符串键还原为数字槽位
    local file_items = nil
    if success and str and #str > 0 then
      local ok, decoded = pcall(json.decode, str)
      if ok and type(decoded) == "table" and decoded.version == PERSIST_VERSION and type(decoded.items) == "table" then
        file_items = {}
        for slot, prefabs in pairs(decoded.items) do
          local num_slot = tonumber(slot)
          if num_slot and type(prefabs) == "table" then
            file_items[num_slot] = prefabs
          end
        end
      end
    end

    local has_current = next(state.items) ~= nil
    local applied = false

    if file_items ~= nil then
      -- 世界存档优先；文件仅用于填补空白(跨 shard 场景)
      if not has_current then
        state.items = file_items
        state.slots = fn.GetItemSlots()
        applied = true
      end
    end
    -- 文件不存在时不做任何重算，槽位配置由后续拾取物品(itemget)自然学习

    if applied then
      fn.PopulateIconCacheFromInventory()

      -- 重画槽位图标(渲染成 fallback 的槽位会由 ScheduleIconHeal 自愈)
      for slot in pairs(state.items) do
        fn.OnNextCycle(function()
          fn.RenderSlotIcons(slot)
        end)
      end
    end

    -- 无论是否应用，都把当前配置同步回文件，供其他 shard/下次登录读取
    fn.FlushPersistedSlots()
  end)
end

function fn.DumpTable(tbl, levels, prefix)
  if type(tbl) ~= "table" then
    print(tostring(tbl))
    return
  end

  if not levels then
    levels = 2
  end

  if levels < 1 then
    -- prevent endless loops on recursive tables
    return
  end

  for k,v in pairs(tbl) do
    local key = (prefix or "")..tostring(k)

    if type(v) == "table" and levels > 1 then
      fn.DumpTable(v, levels - 1, key..".")
    else
      print(key.." = "..tostring(v))
    end
  end
end

function fn.ListenForAllDurabilityChanges(items)
  if type(items) ~= "table" then
    return
  end

  for _, item in ipairs(items) do
    fn.ListenForDurabilityChanges(item)
  end
end

function fn.ListenForDurabilityChanges(item)
  local key = item and item.GUID
  if not key then
    return
  end

  if state.durability.listeners[key] ~= nil then
    -- Already listening
    return
  end

  if not fn.ApplyToItem(item) then
    return
  end

  local function listener(_, data)
    if data and data.percent then
      state.durability.items[key] = data.percent
    end
  end

  item:ListenForEvent("percentusedchange", listener)
  state.durability.listeners[key] = listener

  -- Stop listening and clean up when item is destroyed
  item:ListenForEvent("onremove", function()
    item:RemoveEventCallback("percentusedchange", listener)

    state.durability.listeners[key] = nil
    state.durability.items[key] = nil
  end)
end

function fn.Player_OnItemGet(_, data)
  local item = data.item
  local slot = data.slot

  if not state.is_mastersim then
    if fn.IsDuplicateItemGetEvent(data) then
      -- Client Mode receives some events twice (raised by client and server).
      -- If we have already processed the client version (which is always earlier) we stop.
      return
    end

    if fn.IsEquipment(item) then
      fn.ListenForDurabilityChanges(item)
    end

    if fn.ApplyToItem(item) then
      fn.MaybeSetAtlasAndImageCache(item.prefab, function()
        return fn.GetAtlasAndImageFromItem(item)
      end)
    end
  else
    -- [修复] master 模式入手物品也补真实来源图标缓存：
    -- spawn 探测对未注册 atlas 的服务端 mod 物品不可靠，
    -- 入手事件是最可靠的真实来源(也供磁盘缓存跨会话使用)
    if fn.ApplyToItem(item) then
      fn.MaybeSetAtlasAndImageCache(item.prefab, function()
        return fn.GetAtlasAndImageFromItem(item)
      end)
    end
  end

  if not slot or not state.inventory or fn.IsLocked() then
    return
  end

  if state.is_mastersim then
    fn.MaybeSaveSlot(item, slot, state.inventory)
  else
    fn.MaybeMove(item, slot, state.inventory, function(new_slot, new_container)
      fn.MaybeSaveSlot(item, new_slot, new_container)
    end)
  end
end

function fn.MaybeSaveSlot(item, slot, container)
  if container ~= state.inventory then
    return
  end

  if state.disable_save_slots then
    return
  end

  if not fn.ApplyToItem(item) then
    return
  end

  local _, blocking_item, was_manually_moved = fn.GetItemMeta(item)
  local prefab_is_in_saved_slot = blocking_item and blocking_item.prefab == item.prefab
  local should_save_slot = not prefab_is_in_saved_slot and (was_manually_moved or not fn.HasSlot(item.prefab))

  if should_save_slot then
    fn.SaveSlot(item.prefab, slot)
  end
end

function fn.MaybeMove(item, slot, container, nextFn)
  local should_move = fn.ShouldMove(item, slot, container)
  if not should_move then
    fn.IfFn(nextFn, slot, container)
  else
    fn.Lock()

    local active_item = state.inventory:GetActiveItem()
    container:MoveAway(item, slot, function(new_slot, new_container)
      fn.Unlock()

      local ai_container, ai_slot = state.inventory:FindItemLocation(active_item)
      if ai_container ~= nil and ai_slot ~= nil then
        -- Take back our previously active item
        ai_container:Grab(ai_slot, function()
          fn.IfFn(nextFn, new_slot, new_container)
        end)
      else
        fn.IfFn(nextFn, new_slot, new_container)
      end
    end)
  end
end

function fn.ShouldMove(item, slot, container)
  local saved_slot, blocking_item, was_manually_moved = fn.GetItemMeta(item)

  if was_manually_moved then
    return false
  elseif saved_slot then
    if saved_slot == slot and container == state.inventory then
      return false
    end

    local should_move_blocking_item, _ = fn.ShouldMakeSpace(saved_slot, blocking_item, item)
    if not blocking_item or should_move_blocking_item then
      return true
    end
  end

  -- All other cases: only move when reserving a saved slot
  if not state.config.reserve_saved_slots then
    return false
  else
    local is_in_saved_slot = container == state.inventory and state.items[slot] ~= nil
    if not is_in_saved_slot then
      return false
    elseif state.config.reserve_saved_slots == "always" then
      return true
    elseif state.config.reserve_saved_slots == "if_free_slots" then
      -- Only move if there is a free slot available
      local free_slot = state.inventory:GetFreeSlot() or (state.overflow and state.overflow:GetFreeSlot())
      return free_slot ~= nil
    end
  end
end

function fn.IsDuplicateItemGetEvent(data)
  if not data or not data.item or not data.item.GUID then
    return false
  end

  local item = data.item
  local slot = data.slot
  local is_server_event = not not data.ignore_stacksize_anim

  if is_server_event then
    local processed = state.client_processed[item.GUID]
    if processed and processed.slot == data.slot then
      state.client_processed[item.GUID] = nil
      return true
    end
  else
    state.client_processed[item.GUID] = { slot = slot }
  end

  return false
end

function fn.GetItemMeta(item)
  local saved_slot = fn.GetSlot(item.prefab)
  local blocking_item = saved_slot and state.inventory:GetItem(saved_slot)
  local was_manually_moved = not not state.manually_moved[item.GUID]

  return saved_slot, blocking_item, was_manually_moved
end

function fn.CanEquip(item)
  if state.is_equipping or not fn.IsEquipment(item) then
    return false
  end

  local eslot = fn.GetEquipSlot(item)
  if not eslot then
    return false
  end

  local equipped_item = state.inventory:GetEquippedItem(eslot)
  return not equipped_item
end

function fn.Inventory_OnLoad(original_fn)
  return function(self, data, newents)
    original_fn(self, data, newents)

    if data.save_equipment_slots then
      state.items = data.save_equipment_slots
      state.slots = fn.GetItemSlots()

      -- [本地修改] 同步世界存档中的配置到本地文件，供其他 shard 读取
      fn.FlushPersistedSlots()
    end
  end
end

function fn.Inventory_OnSave(original_fn)
  return function(self)
    local data = original_fn(self)
    data.save_equipment_slots = state.items
    return data
  end
end

function fn.IfFn(value, ...)
  if type(value) == "function" then
    value(...)
  end
end

-- true if the blocking_item in the slot should be moved to make space for item
function fn.ShouldMakeSpace(slot, blocking_item, item)
  if not blocking_item then
    return false
  end

  if blocking_item == OCCUPIED then
    return false
  end

  local blocking_item_saved_slot = fn.GetSlot(blocking_item.prefab)

  if not fn.ApplyToItem(blocking_item) or blocking_item_saved_slot ~= slot then
    return true, "move"
  end

  local equip_blocking_item =
    state.config.allow_equip_for_space and
    fn.CanEquip(blocking_item)

  local move_blocking_item =
    not equip_blocking_item and
    blocking_item.prefab == item.prefab and
    fn.GetDurability(item) < fn.GetDurability(blocking_item)

  if equip_blocking_item then
    return true, "equip"
  elseif move_blocking_item then
    return true, "move"
  else
    return false
  end
end

function fn.CreateMasterInventory()
  local MasterInventory = {}
  MasterInventory.__index = MasterInventory

  function MasterInventory.new(inventory)
    local instance = {
      inventory = inventory
    }

    setmetatable(instance, MasterInventory)

    return instance
  end

  function MasterInventory:GetItem(slot)
    return self.inventory.itemslots[slot]
  end

  function MasterInventory:SetItem(slot, item)
    self.inventory.itemslots[slot] = item
  end

  function MasterInventory:MakeSpace(slot, item)
    local blocking_item = self:GetItem(slot)

    if not blocking_item then
      -- It's already empty
      return true
    end

    -- [修复] 清理已失效的槽位占位：实体可能已被其他 mod（如"漫漫长路"）
    -- 从世界上移除，残留的引用会让后续的 GiveItem/Equip 引擎断言崩溃。
    -- 注意跳过 OCCUPIED：它表示一次进行中的搬运操作，不能动。
    if  blocking_item ~= OCCUPIED and
        blocking_item.IsValid and
        not blocking_item:IsValid() then
      self:SetItem(slot, nil)
      return true
    end

    local should_move, action = fn.ShouldMakeSpace(slot, blocking_item, item)

    if not should_move then
      return false
    end

    if action == "equip" then
      self:Equip(blocking_item)
    elseif action == "move" then
      self:MoveAway(slot)
    end

    return true
  end

  function MasterInventory:MoveAway(from)
    local blocking_item = self:GetItem(from)
    if not blocking_item then
      return
    end

    -- [修复] 与"漫漫长路"等同装时的已知崩溃（社区反馈）：blocking_item 可能
    -- 已被其他 mod 从世界上移除，或槽位里残留着 OCCUPIED 占位对象
    -- （旧代码在 GiveItem 抛错时会泄漏它）。这两种对象都不能交给引擎
    -- GiveItem，否则引擎断言崩溃。此处直接放弃引用并清空槽位。
    -- 注意判断顺序：必须先排除 OCCUPIED，它没有 IsValid 方法。
    if  blocking_item == OCCUPIED or
        not blocking_item.IsValid or
        not blocking_item:IsValid() or
        not blocking_item.components or
        not blocking_item.components.inventoryitem then
      self:SetItem(from, nil)
      return
    end

    -- Before moving the item, we occupy its current slot with the OCCUPIED object
    -- otherwise the game would not move blocking_item at all,
    -- presumably as it is already present in the inventory.
    -- In addition, the OCCUPIED object makes sure this slot will not be touched
    -- again in a recursive call to this method which would otherwise possibly try to
    -- move the this item again or equip it.
    self:SetItem(from, OCCUPIED)

    -- Record the fact we are automatically moving items
    fn.Lock()

    -- [修复] GiveItem 可能在引擎层抛错（实体在转移途中被其他 mod 移除等）。
    -- 用 pcall 保护并保证 Unlock 和槽位清理一定执行，
    -- 否则 OCCUPIED 会永久泄漏在 itemslots 里引发连锁崩溃。
    pcall(function()
      self.inventory:GiveItem(blocking_item, nil, nil, true)
    end)

    fn.Unlock()

    -- The saved_slot is cleared as we have made space by moving away blocking_item.
    -- The game will be putting item in there at a slightly later time
    self:SetItem(from, nil)
  end

  function MasterInventory:Equip(item)
    self.inventory:Equip(item)
  end

  function MasterInventory:GetEquippedItem(eslot)
    return self.inventory:GetEquippedItem(eslot)
  end

  function MasterInventory:EachItem(callback)
    if callback == nil then
      return nil
    end

    local numslots = self.inventory:GetNumSlots()
    if numslots then
      for slot = 1, numslots do
        local item = self:GetItem(slot)
        if item ~= nil then
          callback(item, slot)
        end
      end
    end
  end

  return MasterInventory
end

function fn.CreateClientContainer()
  local ClientContainer = {}
  ClientContainer.__index = ClientContainer

  function ClientContainer.new(container)
    local instance = {
      container = container
    }

    setmetatable(instance, ClientContainer)

    return instance
  end

  local function CancelRefreshTask(container)
    if  container.classified and
        container.classified._refreshtask and
        type(container.classified._refreshtask.Cancel) == "function" then
      container.classified._refreshtask:Cancel()
      container.classified._refreshtask = nil
      container.classified._busy = false
      return true
    else
      return false
    end
  end

  function ClientContainer:IsBusy()
    return  self.container and self.container.classified and
            self.container.classified.IsBusy and self.container.classified:IsBusy()
  end

  function ClientContainer:WhenNotBusy(whenFn, skipCancel)
    if self:IsBusy() then
      local function retry()
        self:WhenNotBusy(whenFn, true)
      end

      if not skipCancel and CancelRefreshTask(self.container) then
        retry()
      else
        fn.OnNextCycle(retry)
      end
    else
      whenFn()
    end
  end

  function ClientContainer:MoveAway(item, slot, nextFn)
    local new_slot, new_container = state.inventory:FindNewSlot(item, slot, self)

    local function callback()
      fn.IfFn(nextFn, new_slot, new_container)
    end

    local dont_move = new_slot == slot and new_container == self
    local move_to_active = new_slot == nil and new_container == nil
    if dont_move then
      callback()
    elseif move_to_active then
      self:Grab(slot, callback)
    else
      -- Moving to new_slot, new_container.
      -- First grab the item so our old slot is made available
      self:Grab(slot, function()
        if new_slot == "equip" then
          state.inventory:EquipActiveItem(callback)
        elseif new_slot then
          local blocking_item = new_container:GetItem(new_slot)
          if blocking_item then
            new_container:MoveAway(blocking_item, new_slot, callback)
          else
            new_container:Put(new_slot, callback)
          end
        else
          callback()
        end
      end)
    end
  end

  function ClientContainer:Grab(slot, nextFn)
    fn.Lock()

    self:WhenNotBusy(function()
      state.inventory:WhenNotBusy(function()
        local active_item = state.inventory:GetActiveItem()

        if active_item then
          self.container:SwapActiveItemWithSlot(slot)
        else
          self.container:TakeActiveItemFromAllOfSlot(slot)
        end

        fn.Unlock()
        fn.IfFn(nextFn)
      end)
    end)
  end

  function ClientContainer:Put(slot, nextFn)
    fn.Lock()

    self:WhenNotBusy(function()
      state.inventory:WhenNotBusy(function()
        local item = self:GetItem(slot)

        if item then
          self.container:SwapActiveItemWithSlot(slot)
        else
          self.container:PutAllOfActiveItemInSlot(slot)
        end

        fn.Unlock()
        fn.IfFn(nextFn)
      end)
    end)
  end

  function ClientContainer:SwapActiveItemWithSlot(slot, nextFn)
    self:WhenNotBusy(function()
      self.container:SwapActiveItemWithSlot(slot)
      fn.IfFn(nextFn)
    end)
  end

  function ClientContainer:Move(from, to, nextFn)
    fn.Lock()
    self:Grab(from, function()
      self:Put(to, function()
        fn.Unlock()
        fn.IfFn(nextFn)
      end)
    end)
  end

  function ClientContainer:Swap(slotA, slotB, nextFn)
    fn.Lock()
    self:Grab(slotA, function()
      self:SwapActiveItemWithSlot(slotB, function()
        self:Put(slotA, function()
          fn.Unlock()
          fn.IfFn(nextFn)
        end)
      end)
    end)
  end

  function ClientContainer:SwapWithInventory(from, inventory, to, nextFn)
    fn.Lock()
    inventory:WhenNotBusy(function()
      self:Grab(from, function()
        inventory:SwapActiveItemWithSlot(to, function()
          inventory:WhenNotBusy(function()
            self:Put(from, function()
              fn.Unlock()
              fn.IfFn(nextFn)
            end)
          end)
        end)
      end)
    end)
  end

  function ClientContainer:MoveToInventory(from, inventory, to, nextFn)
    fn.Lock()

    inventory:WhenNotBusy(function()
      self:Grab(from, function()
        inventory:Put(to, function()
          fn.Unlock()
          fn.IfFn(nextFn)
        end)
      end)
    end)
  end

  function ClientContainer:GetFreeSlot()
    local numslots = self.container:GetNumSlots()
    if numslots then
      for slot = 1, numslots do
        local item = self:GetItem(slot)
        if not item then
          return slot
        end
      end
    end
  end

  function ClientContainer:GetItem(slot)
    return self.container:GetItemInSlot(slot)
  end

  function ClientContainer:FindItemLocation(target_item)
    if target_item == nil then
      return nil
    end

    local numslots = self.container:GetNumSlots()
    if numslots then
      for slot = 1, numslots do
        local item = self:GetItem(slot)
        if item == target_item then
          return self, slot
        end
      end
    end

    if self == state.inventory and state.overflow ~= nil then
      -- Look in overflow
      return state.overflow:FindItemLocation(target_item)
    end
  end

  function ClientContainer:FindItem(predicate)
    if predicate == nil then
      return nil
    end

    local numslots = self.container:GetNumSlots()
    if numslots then
      for slot = 1, numslots do
        local item = self:GetItem(slot)
        if predicate(item) then
          return item
        end
      end
    end

    if self == state.inventory and state.overflow ~= nil then
      -- Look in overflow
      return state.overflow:FindItem(predicate)
    end
  end

  function ClientContainer:EachItem(callback)
    if callback == nil then
      return nil
    end

    local numslots = self.container:GetNumSlots()
    if numslots then
      for slot = 1, numslots do
        local item = self:GetItem(slot)
        if item ~= nil then
          callback(item, slot)
        end
      end
    end
  end

  return ClientContainer
end

function fn.CreateClientInventory(ClientContainer)
  local ClientInventory = {}
  ClientInventory.__index = ClientInventory

  setmetatable(ClientInventory, ClientContainer)

  function ClientInventory.new(inventory)
    local instance = ClientContainer.new(inventory)

    instance.inventory = inventory

    setmetatable(instance, ClientInventory)

    return instance
  end

  function ClientInventory:GetEquippedItem(eslot)
    return self.inventory:GetEquippedItem(eslot)
  end

  function ClientInventory:GetActiveItem()
    return self.inventory:GetActiveItem()
  end

  function ClientInventory:EquipActiveItem(nextFn)
    self:WhenNotBusy(function()
      self.inventory:EquipActiveItem()
      fn.IfFn(nextFn)
    end)
  end

  function ClientInventory:Equip(slot, nextFn)
    state.is_equipping = true
    fn.Lock()
    self:Grab(slot, function()
      self:EquipActiveItem(function()
        state.is_equipping = false
        fn.Unlock()
        fn.IfFn(nextFn)
      end)
    end)
  end

  function ClientInventory:FindNewSlot(item, slot, container)
    local saved_slot, blocking_item, _ = fn.GetItemMeta(item)
    if saved_slot and (saved_slot ~= slot or container ~= state.inventory)  then
      local should_move, _ = fn.ShouldMakeSpace(saved_slot, blocking_item, item)
      if not blocking_item or should_move then
        return saved_slot, self
      end
    end

    if state.config.allow_equip_for_space and fn.CanEquip(item) then
      return "equip", self
    end

    local free_slot = self:GetFreeSlot(state.config.reserve_saved_slots)
    if free_slot then
      return free_slot, self
    elseif state.overflow then
      free_slot = state.overflow:GetFreeSlot()
      if free_slot then
        return free_slot, state.overflow
      end
    elseif state.config.reserve_saved_slots == "if_free_slots" then
      -- When we were reserving saved slots only when we have free slots
      -- we will try again at this point, as there were no free slots available
      free_slot = self:GetFreeSlot(false)
      if free_slot then
        return free_slot, self
      end
    end

    -- No free slot available
    return nil, nil
  end

  function ClientInventory:EquipActiveItem(nextFn)
    state.is_equipping = true
    self:WhenNotBusy(function()
      self.inventory:EquipActiveItem()
      state.is_equipping = false
      fn.IfFn(nextFn)
    end)
  end

  function ClientInventory:GetFreeSlot(skip_saved_slots)
    local numslots = self.inventory:GetNumSlots()
    if numslots then
      for slot = 1, numslots do
        if not skip_saved_slots or not state.items[slot] then
          local item = self:GetItem(slot)
          if not item then
            return slot
          end
        end
      end
    end
  end

  return ClientInventory
end

function fn.InitClasses()
  local MasterInventory = fn.CreateMasterInventory()
  local ClientContainer = fn.CreateClientContainer()
  local ClientInventory = fn.CreateClientInventory(ClientContainer)

  new.MasterInventory = MasterInventory.new
  new.ClientContainer = ClientContainer.new
  new.ClientInventory = ClientInventory.new
end

function fn.InitOverflow(overflow)
  if  not overflow or not overflow.inst or
      type(overflow.inst.ListenForEvent) ~= "function" then
    return
  end

  local player = fn.GetPlayer()
  if not player then
    return
  end

  local items = overflow:GetItems()
  fn.ListenForAllDurabilityChanges(items)

  state.overflow = new.ClientContainer(overflow)

  local eslot = fn.GetEquipSlot(overflow.inst)

  local function OnItemGet(_, data)
    local item = data.item
    local slot = data.slot

    if not item then
      return
    end

    -- [修复] 物品进入背包(overflow 容器)也补充图标缓存：
    -- client 模式无法 spawn 探测，主物品栏的 EachItem 也不遍历背包。
    -- 不做事件去重，缓存计算是幂等的
    if not state.is_mastersim and fn.ApplyToItem(item) then
      fn.MaybeSetAtlasAndImageCache(item.prefab, function()
        return fn.GetAtlasAndImageFromItem(item)
      end)
    end

    if not fn.ApplyToItem(item) or fn.IsLocked() or
        not state.overflow or not state.inventory then
      return
    end

    if not state.is_mastersim and fn.IsDuplicateItemGetEvent(data) then
      return
    end

    fn.MaybeMove(item, slot, state.overflow)
  end

  local function OnUnequip(_, data)
    if data and data.eslot == eslot then
      if type(overflow.inst.RemoveEventCallback) == "function" then
        overflow.inst:RemoveEventCallback("itemget", OnItemGet)
        state.overflow = nil
      end

      player:RemoveEventCallback("unequip", OnUnequip)
    end
  end

  overflow.inst:ListenForEvent("itemget", OnItemGet)
  player:ListenForEvent("unequip", OnUnequip)
end

function fn.Player_OnNewActiveItem(_, data)
  if fn.IsLocked() then
    return
  end

  local item = data.item

  if item == nil then
    state.manually_moved.dirty = false
    fn.OnNextCycle(function()
      if not state.manually_moved.dirty then
        fn.ClearTable(state.manually_moved)
      end
    end)
  else
    state.manually_moved[item.GUID] = true
    state.manually_moved.dirty = true
  end
end

function fn.Inventorybar_Rebuild(original_fn)
  return function(self)
    original_fn(self)
    fn.OnNextCycle(fn.RefreshImageButtons)
    -- [修复] 重建时重同步图标，覆盖皮肤数据下发的时点差异
    fn.ScheduleIconResync()
  end
end

function fn.InitInventorybar(inventorybar)
  state.inventorybar = inventorybar

  fn.InitDisableSaveSlotsStatusText()

  if type(inventorybar.Rebuild) == "function" then
    inventorybar.Rebuild = fn.Inventorybar_Rebuild(inventorybar.Rebuild)
  end
end

function fn.InitInventory(inventory)
  if state.is_mastersim then
    state.inventory = new.MasterInventory(inventory)

    inventory.GetNextAvailableSlot = fn.Inventory_GetNextAvailableSlot(inventory.GetNextAvailableSlot)
    inventory.Equip = fn.Inventory_Equip(inventory.Equip)
    inventory.OnSave = fn.Inventory_OnSave(inventory.OnSave)
  else
    state.inventory = new.ClientInventory(inventory)

    -- Client Mode needs custom logic for overflow containers (backpack and the like)
    local overflow = inventory:GetOverflowContainer()
    fn.InitOverflow(overflow)

    -- Client Mode cannot directly access item durability but has to use events
    local items = inventory:GetItems()
    fn.ListenForAllDurabilityChanges(items)

    local equips = inventory:GetEquips()
    fn.ListenForAllDurabilityChanges(equips)
  end

  -- [本地修改] 用身上物品(含装备栏, 带皮肤的真实数据)补充图标缓存。
  -- 世界存档恢复路径(Inventory_OnLoad)没有 populate 时机，缺了这一步
  -- spawn 探测的基础图标会常驻，皮肤物品无法显示皮肤图标。
  fn.PopulateIconCacheFromInventory()

  -- [修复] 皮肤图标数据可能晚于图标渲染下发，进入世界后分时点重同步
  fn.ScheduleIconResync()

  -- [本地修改] DST: 从本地持久化文件恢复配置(跨 shard 互通)。
  -- 最终配置由 LoadPersistedSlots 的回调决定(世界存档优先)。
  if state.is_dst then
    fn.LoadPersistedSlots()
  end
end

function fn.PlayerHud_OnControl(base_fn)
  return function(self, control, down)
    local base_val = base_fn(self, control, down)

    if not base_val then
      local handlers = {
        -- Controller Clear Slot
        fn.HandleControllerKey,
      }

      for _, handler in ipairs(handlers) do
        if handler(self, control, down) then
          return true
        end
      end
    end

    return base_val
  end
end

function fn.PlayerHud_OnRawKey(base_fn)
  return function(self, key, down)
    local base_val = base_fn(self, key, down)

    if not base_val then
      local handlers = {
        -- Disable Save Slots
        fn.HandleDisableSaveSlots,
      }

      for _, handler in ipairs(handlers) do
        if handler(self, key, down) then
          return true
        end
      end
    end

    return base_val
  end
end

function fn.HandleControllerKey(hud, control, down)
  if not hud:IsControllerInventoryOpen() then
    return false
  end

  local is_lb = control == CONTROLS.LB
  local is_rb = control == CONTROLS.RB

  if down and state.inventorybar and (is_lb or is_rb) then
    local is_both =
      (is_lb and TheInput:IsControlPressed(CONTROLS.RB)) or
      (is_rb and TheInput:IsControlPressed(CONTROLS.LB))

    if is_both then
      local active_slot = state.inventorybar.active_slot

      if active_slot and active_slot.num and state.inventory then
        local is_inventory

        if state.is_dst and state.is_mastersim then
          -- In DST, active_slot.container points to the inventory replica
          -- but when we also run the Master Simulation our state.inventory.inventory
          -- is the actual inventory, not the replica.
          local player = fn.GetPlayer()
          is_inventory = player and player.replica and player.replica.inventory == active_slot.container
        else
          is_inventory = active_slot.container == state.inventory.inventory
        end

        if is_inventory then
          fn.ClearEntireSlot(active_slot.num)
          return true
        end
      end
    end
  end

  return false
end

function fn.HandleDisableSaveSlots(_, key, down)
  if not down or not state.config.disable_save_slots_toggle then
    return false
  end

  if key == state.config.disable_save_slots_toggle and TheInput:IsKeyDown(GLOBAL.KEY_CTRL) then
    fn.ToggleDisableSaveSlots()
    return true
  end
end

function fn.ToggleDisableSaveSlots()
  state.disable_save_slots = not state.disable_save_slots
  fn.ShowDisableStatusText(3)
end

function fn.InitPlayerHud()
  if not PlayerHud then return end
  PlayerHud.OnControl = fn.PlayerHud_OnControl(PlayerHud.OnControl)
  PlayerHud.OnRawKey = fn.PlayerHud_OnRawKey(PlayerHud.OnRawKey)
end

function fn.InitConfig()
  local function ParseBitFlags(flags, values)
    if #flags ~= #values or not string.find(flags, "^[01]+$") then
      return flags
    end

    local map = {}
    for i = 1, #flags do
      map[values[i]] = string.sub(flags, i, i) == "1"
    end
    return map
  end

  state.config.apply_to_items = ParseBitFlags(GetModConfigData("apply_to_items"), { "equipment", "food", "healer" })
  state.config.show_slot_icons = GetModConfigData("show_slot_icons")
  state.config.slot_icon_opacity = GetModConfigData("slot_icon_opacity")
  state.config.slot_icon_scale = GetModConfigData("slot_icon_scale")
  state.config.slot_icon_offset = GetModConfigData("slot_icon_offset")
  state.config.allow_equip_for_space = GetModConfigData("allow_equip_for_space")
  state.config.reserve_saved_slots = GetModConfigData("reserve_saved_slots")
  state.config.disable_save_slots_toggle = GetModConfigData("disable_save_slots_toggle")
  state.config.save_slots_initial_state = GetModConfigData("save_slots_initial_state")
  state.config.disable_slot_icon_click_when_save_slots_off = GetModConfigData("disable_slot_icon_click_when_save_slots_off")

  -- 将初始开关状态应用到状态表（仅在配置了暂停快捷键时使用）
  if state.config.disable_save_slots_toggle then
    state.disable_save_slots = not state.config.save_slots_initial_state
  end
end

function fn.InitPlayerEvents(player)
  player:ListenForEvent("equip", function(player_inst, data)
    fn.Player_OnEquip(player_inst, data)
    -- [修复] 装备/换肤后重同步图标(皮肤数据可能刚下发)
    tasker:DoTaskInTime(0.5, fn.ResyncIconsFromLiveItems)
  end)
  player:ListenForEvent("itemget", fn.Player_OnItemGet)
  player:ListenForEvent("newactiveitem", fn.Player_OnNewActiveItem)

  -- [本地修改] 玩家实体移除(退出/跨 shard 迁移)时把待写的图标缓存立即落盘：
  -- 防抖用的 DoTaskInTime 可能随实体销毁而不触发(踩坑文档 §3)
  player:ListenForEvent("onremove", function()
    if state.icon_store_flush_task ~= nil then
      state.icon_store_flush_task:Cancel()
      state.icon_store_flush_task = nil
      fn.FlushIconStore()
    end
  end)
end

function fn.InitSaveEquipmentSlots()
  AddSimPostInit(function()
    state.is_mastersim = fn.IsMasterSim()
  end)

  AddPlayerPostInit(function(player)
    fn.OnNextCycle(function()
      -- Make sure it is the current player
      if player == fn.GetPlayer() then
        fn.InitPlayerEvents(player)
        fn.IfHasComponent(player, "inventory", fn.InitInventory)
      end
    end)
  end)

  AddComponentPostInit("inventory", function(inventory)
    -- AddPlayerPostInit triggers after Inventory.OnLoad
    -- so we use AddComponentPostInit for this specific one
    if type(inventory.OnLoad) == "function" then
      inventory.OnLoad = fn.Inventory_OnLoad(inventory.OnLoad)
    end
  end)

  AddClassPostConstruct("widgets/inventorybar", fn.InitInventorybar)

  AddClassPostConstruct("widgets/invslot", function(invslot)
    fn.OnNextCycle(function()
      fn.RenderSlotIcons(invslot.num)
    end)
  end)

  fn.InitPlayerHud()
  fn.InitClasses()
  fn.InitConfig()

  -- [本地修改] 启动时尽早异步加载磁盘图标缓存，
  -- 回调无论早于或晚于首次槽位图标渲染都能闭环
  fn.LoadIconStore()
end

fn.InitSaveEquipmentSlots()
