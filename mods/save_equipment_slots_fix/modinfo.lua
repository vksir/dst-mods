name = "Save Equipment Slots (Fix)"
description =
  "Save Equipment Slots (Fix) - 装备槽记忆\n" ..
  "\n" ..
  "修改自 dani 的 Save Equipment Slots，原 mod：https://steamcommunity.com/sharedfiles/filedetails/?id=1598084686\n" ..
  "\n" ..
  "改动说明：\n" ..
  "1、槽位配置重上游戏、上下洞穴不再丢失。\n" ..
  "2、些许默认配置调整。特别地，默认开关快捷键变更为 Ctrl + V。\n" ..
  "\n" ..
  "Modified from dani's Save Equipment Slots. Original mod: https://steamcommunity.com/sharedfiles/filedetails/?id=1598084686\n" ..
  "Changes:\n" ..
  "1. Slot configurations no longer get lost when reloading the game or entering/exiting caves.\n" ..
  "2. Minor adjustments to the default configuration. In particular, the default toggle shortcut has been changed to Ctrl + V."
author = "Villkiss (Original author: dani)"
version = "0.1.1"
forumthread = ""
api_version = 6
api_version_dst = 10

-- 修复版使用了 DST 专属 API(TheSim:SetPersistentString / net_hash 语义等)，
-- 且未在 DS 单机验证过，不再声明 DS 系列兼容
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
hamlet_compatible = false
dst_compatible = true

all_clients_require_mod = false
client_only_mod = true

icon_atlas = "modicon.xml"
icon = "modicon.tex"

local disable_save_slot_toggle_options = {
  { description = "- 无 - None", data = false },
}

for i = 0, 25 do
  disable_save_slot_toggle_options[i + 2] = {
    description = "Ctrl + " .. ("").char(65 + i),
    data = 97 + i
  }
end

-- 5% to 100% with steps of 5
local percentage_options = {}
for i = 1, 20 do
  local percentage = i * 5
  local data = percentage / 100
  percentage_options[i] = {
    description = percentage .. "%",
    data = data
  }
end

local offset_options = {}
for i = 0, 16 do
  local data = 1 + (i * .25)
  local extra_offset = (data - 1) * 100
  offset_options[i+1] = {
    description = i == 0 and "Default 默认" or "+" .. extra_offset .. "%",
    data = data
  }
end

configuration_options =
{
  {
    name = "apply_to_items",
    label = "Apply To Items 应用类型",
    hover = "配置需要保存槽位的物品类型。\nConfigure which item types should be saved.",

    options = {
      { description = "Equipment 装备", data = "100" },
      { description = "Eq. + Food 装备+食物", data = "110" },
      { description = "Eq. + Healing 装备+治疗", data = "101" },
      { description = "Eq. + Fo. + He. 装备+食物+治疗", data = "111" },
      { description = "All items 全部物品", data = "all" },
    },

    default = "100"
  },

  {
    name = "show_slot_icons",
    label = "Show Slot Icons 显示槽位图标",
    hover = "在已保存的槽位上方显示对应物品的图标，点击图标可清除该槽位的保存。\n" ..
            "Shows an icon of a saved item above its saved slot. Click the icon to clear the saved slot of that item.",

    options = {
      { description = "Show 显示", data = true },
      { description = "Hide 隐藏", data = false },
    },

    default = true
  },

  {
    name = "slot_icon_opacity",
    label = "Slot Icon Opacity 图标不透明度",
    hover = "设置槽位图标的不透明度。\nSet the opacity of the slot icons.",

    options = percentage_options,
    default = .75
  },

  {
    name = "slot_icon_scale",
    label = "Slot Icon Scale 图标缩放",
    hover = "设置槽位图标的缩放比例。\nSet the scale of the slot icons.",

    options = percentage_options,
    default = .75
  },

  {
    name = "slot_icon_offset",
    label = "Slot Icon Offset 图标垂直偏移",
    hover = "设置槽位图标的垂直偏移，以一个物品栏槽位高度的百分比表示。\n" ..
            "Set the vertical offset of the slot icons, expressed as a percentage of 1 inventory slot height.",

    options = offset_options,
    default = 1
  },

  {
    name = "disable_save_slots_toggle",
    label = "Save Slots Toggle 暂停保存快捷键",
    hover = "用于开启/关闭槽位保存功能的组合键。\n" ..
            "Key combination that will toggle saving slots on/off.",
    options = disable_save_slot_toggle_options,
    -- 注意：modinfo 的沙箱环境没有任何标准库（无 string/pairs 等），
    -- 只能用字符串元表调用（同上方 ("").char 惯用法）
    default = ("v"):byte()
  },

  {
    name = "save_slots_initial_state",
    label = "Save Slots Initial State 初始开关状态",
    hover = "槽位保存功能的初始状态，仅在配置了暂停快捷键时生效。\n" ..
            "The initial state of the Save Slots behavior. Only used when a toggle key is configured.",

    options = {
      { description = "On 开", data = true },
      { description = "Off 关", data = false },
    },

    default = true
  },

  {
    name = "disable_slot_icon_click_when_save_slots_off",
    label = "Disable Icon Click 暂停时禁用点击",
    hover = "控制何时禁用槽位图标的点击。\n" ..
            "Controls when clicking slot icons is disabled.",
    options = {
      { description = "Never 从不", data = false },
      { description = "If Save Slots: Off 保存关闭时", data = true },
    },
    default = true
  },

  {
    name = "allow_equip_for_space",
    label = "Allow Equip For Space 允许装备腾位",
    hover = "允许通过装备占位物品来为新物品腾出空间。\n" ..
            "Allows an item to be equipped in order to make space for an incoming item.",
    options = {
      { description = "Enabled 启用", data = true },
      { description = "Disabled 禁用", data = false },
    },

    default = true
  },

  {
    name = "reserve_saved_slots",
    label = "Reserve Saved Slots 保留已存槽位",
    hover = "决定是否为已保存的物品保留其槽位，以及是否仅在其他空槽位可用时才保留。\n" ..
            "Determines if saved slots will be reserved for their items, and if this only happens when there are other slots available.",

    options = {
      { description = "Never 从不", data = false },
      { description = "If Free Slots 有空位时", data = "if_free_slots" },
      { description = "Always 总是", data = "always" },
    },

    default = false
  },

}
