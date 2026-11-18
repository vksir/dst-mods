name = "Wanda Planar Plan"   -- 代码里的 mod 名只能 ASCII（文件夹名/prefab/netvar 同理）；中文名放工坊标题与 description
description =
    "A Wanda overhaul pack: planar damage rework, nameable watches, a watchkeeper bag, and new support watches.\n" ..
    "\n" ..
    "功能一览（每项均可在配置中独立开关）：\n" ..
    "1. 告警表造成的伤害全额转化为位面伤害；旺达受到的位面伤害全额转化为普通伤害。\n" ..
    "2. 溯源表、裂缝表可以用羽毛笔命名：手持羽毛笔右键物品栏中的表（右键文案为“命名”），名字显示为「溯源表-XXX」，所有玩家可见。\n" ..
    "3. 新增钟表袋：右键开启 / 关闭（2×8 格，与“添加燃料”同款的短动作），只收纳旺达的钟表；人物移动不会关闭，也不会连带关掉背包。\n" ..
    "4. 第二次机会表：旺达灵魂状态下用它复活自己后不再损毁。\n" ..
    "5. 新增加速表：0% / 30% / 50% 两档，右键循环切换（文案依次为 激活 / 提升档位 / 停用），同时按比例加速移动与老化。\n" ..
    "6. 新增减速表：右键循环开关（关闭 → 30% → 50%，文案 激活 / 提升档位 / 停用）；开启后周边 12 格内敌对生物移速降至 70% / 50%（身上有粒子特效），代价是自身老化加快 30% / 50%。\n" ..
    "7. 倒走表：施法起手即获得格挡护盾（覆盖整段前摇），施法成功后追加骨头盔甲同款 10 帧免伤。\n" ..
    "三件新物品在地面/手持时都有专属着色（青绿 / 紫红 / 皮革棕），不会与溯源表、克劳斯背包混淆。\n" ..
    "\n" ..
    "This mod must be installed on both the server and the client."
author = "Villkiss"

-- Mods 列表图标（必须指向 mod 目录内的 tex+xml 对，不能用游戏内路径）
icon_atlas = "modicon.xml"
icon = "modicon.tex"
version = "0.4.1"

forumthread = ""

api_version = 6
api_version_dst = 10

dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
hamlet_compatible = false
dst_compatible = true

-- 新物品 prefab、右键动作与命名 UI 都需要客户端加载本 mod
all_clients_require_mod = true
client_only_mod = false

server_filter_tags = {
    "wanda",
    "character",
}

local boolean_options = {
    { description = "开启 On", data = true },
    { description = "关闭 Off", data = false },
}

configuration_options = {
    {
        name = "clock_to_planar",
        label = "告警表伤害转位面",
        hover = "告警表（Alarming Clock）造成的全部伤害按位面伤害结算，无视目标护甲吸收；空表状态同样转化。",
        options = boolean_options,
        default = true,
    },
    {
        name = "planar_to_normal",
        label = "旺达受位面转普通",
        hover = "旺达受到的位面伤害全额转化为普通伤害，可被护甲正常吸收与损耗耐久。",
        options = boolean_options,
        default = true,
    },
    {
        name = "nameable_watches",
        label = "钟表可命名",
        hover = "溯源表、裂缝表可以用羽毛笔命名：手持羽毛笔右键物品栏中（或丢在地上）的表，右键文案为“命名”；命名后名字显示为「溯源表-XXX」，并同步显示给其他玩家。",
        options = boolean_options,
        default = true,
    },
    {
        name = "keep_revive_watch",
        label = "自复活不损毁",
        hover = "第二次机会表：旺达灵魂状态下用它复活自己后不再损毁。",
        options = boolean_options,
        default = true,
    },
    {
        name = "warp_shield",
        label = "倒走表护盾",
        hover = "倒走表施法起手即获得格挡护盾，覆盖整段施法前摇；施法成功后追加与骨头盔甲同款（10 帧）的免伤窗口（护盾特效不带额外的受击音效）。",
        options = boolean_options,
        default = true,
    },
    {
        name = "haste_watch",
        label = "加速表",
        hover = "新增加速表：0% / 30% / 50% 两档，右键循环切换（右键文案依次为 激活 / 提升档位 / 停用），同时按比例加速移动速度与老化（骑乘时只有老化加速生效）。档位存在人物身上，所有同类表共享；丢在地上或放进钟表袋也继续生效。地面/手持为独立绘制的青绿怀表外观（非原版贴图）。",
        options = boolean_options,
        default = true,
    },
    {
        name = "slow_watch",
        label = "减速表",
        hover = "新增减速表：右键循环开关（关闭 → 减速 30% → 50% → 关闭，右键文案 激活 / 提升档位 / 停用）。开启后周边 12 格内敌对生物移速降至 70% / 50%，身上带粒子特效；代价是自身老化速度 +30% / +50%（与加速表的老化加速加算叠加）。档位存在人物身上，所有同类表共享。地面/手持为独立绘制的洋红怀表外观（非原版贴图）。",
        options = boolean_options,
        default = true,
    },
    {
        name = "watch_bag",
        label = "钟表袋",
        hover = "新增钟表袋：右键开启 / 关闭（与“添加燃料”同款的短动作，右键文案 开启 / 关闭），2×8 格，只收纳旺达的钟表；人物移动不会关闭，也不会连带关掉背包。地面/手持外观为皮革棕着色。",
        options = boolean_options,
        default = true,
    },
}
