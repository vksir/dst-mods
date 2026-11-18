# tools/ —— 开发与验收工具

按 mod 划分目录：**通用工具放 `common/`，只服务单个 mod 的放 `<mod>/`**。

```
tools/
├── common/                    跨 mod 通用
│   ├── dstconsole.py          向游戏控制台注入 Lua（纯 PostMessage，不依赖焦点）
│   ├── dstlua.sh              执行 Lua 直到日志出现标记（无人值守验收）
│   ├── gameinput.py           带焦点校验的键鼠输入（Unicode）
│   ├── uilook.py              屏幕模板匹配（存在性断言 / 定位）
│   └── ktex2png.py            KTEX 解码（校验图标与图集产物）
└── wanda_planar_plan/        旺达位面计划专用生成器
    ├── gen_wanda_icons.py        物品栏图标 + 预览拼图
    ├── gen_item_build.py         地面精灵 + scml + anim.zip
    ├── gen_workshop_preview.py   工坊预览图 preview.jpg（268×268）
    └── gen_modicon.py            Mods 列表图标 modicon.png（256×256，mod 根目录）
```

新增工具时：

- 只跟某个 mod 的画法/资源有关 → `tools/<mod>/`，文件名带 mod 特征；
- 与 mod 无关（截屏、输入、编解码、日志）→ `tools/common/`；
- 脚本里定位仓库用 `HERE = 脚本目录`、`REPO = HERE/../..`，不要写死绝对路径；
- 跨目录 import：`sys.path.insert(0, os.path.join(REPO, "tools", "common"))`。

用法与限制见各目录的 README，开发/测试语境见
[通用开发指南](../docs/mods/common/development.md#11-工具使用方法) 与 [测试指南](../docs/mods/common/testing.md)。
