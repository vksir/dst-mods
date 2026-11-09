-- 护卫犬 K-9 正式版
-- 注意：modinfo 沙箱零标准库，只允许字符串/数字常量与字符串元表调用（见 docs/dst-modding-pitfalls.md §2）

name = "护卫犬 K-9（Guard Dog K-9）"
description = [[一只月亮构造体护卫犬：眼球核心、贴身飞行、电弧连锁攻击群怪。

合成：巨鹿眼球×1 + 远古犀牛角×1 + 格罗姆翅膀×1 + 铥矿×5（完整远古祭坛）。
项圈放入背包即召唤，随身携带、跨世界跟随。

升级（月亮锻造台）：
· 启迪之冠 → 伤害 142
· 火花柜（满）→ +68 位面伤害
· 两线可叠满至终阶形态

电弧对潮湿目标伤害更高；连锁最多传导 3 跳。

A lunar construct guard dog with an eyeball core: hovers at your side, hunts
hostiles and chains arc-lightning through crowds.

Craft at a fully restored Ancient Pseudoscience Station: Deerclops Eyeball +
Guardian's Horn + Glommer's Wings + 5 Thulecite. Keep the collar in your
inventory and the K-9 follows you anywhere, even across shards.

Upgrades at the Lunar Forge:
- Enlightened Crown -> 142 damage
- full Spark Ark -> +68 planar damage
- stack both for the apex form.

Electric attacks deal bonus damage to wet targets; arcs chain up to 3 hops.]]

author = "vkzha"
version = "1.0.0"

-- 图标：游戏内 atlas 路径不被 mod 列表 UI 接受（日志 WARNING），正式 icon 需 mod 本地 tex+xml（07 票 ktech 制作）

api_version = 10

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

all_clients_require_mod = true
client_only_mod = false

server_filter_tags = { "guard dog", "companion", "pet", "lunar" }

configuration_options = {}
