# dst-mods

Don't Starve Together mods —— 所有 mod 位于 `mods/`，每个子目录一个独立 mod。

- `mods/wanda_planar_plan` — 旺达位面计划：加速表 / 减速表 / 钟表袋 / 命名 / 护盾等（开发中的主要 mod）
- `mods/save_equipment_slots_fix` — Save Equipment Slots 修复版：装备槽配置跨地表/洞穴(shard)不再丢失（详见 [docs/mods/save_equipment_slots_fix/](docs/mods/save_equipment_slots_fix/features.md)）
- `mods/arc_k9`、`mods/laser_rover_proto`、`mods/advanced_attack`、`mods/scythe`、`mods/winter_feast_clean`、`mods/snappy_actions` — 其余 mod / 原型

## 文档

| 文档 | 内容 |
|---|---|
| [docs/mods/](docs/mods/README.md) | 文档总索引 |
| [docs/mods/common/](docs/mods/common/development.md) | 通用开发 / 测试 / 发布指南 |
| [docs/mods/wanda_planar_plan/](docs/mods/wanda_planar_plan/features.md) | 旺达位面计划：功能说明、开发、测试、发布 |
| [docs/mods/save_equipment_slots_fix/](docs/mods/save_equipment_slots_fix/features.md) | 装备槽记忆修复：功能说明、开发、测试、发布 |
| [GLOSSARY.md](GLOSSARY.md) | 术语表 |

## 其他目录

- `tools/`：`common/`（通用工具）、`<mod>/`（单 mod 生成器）
- `docs/mods/<mod>/`：每个 mod 的功能说明、开发、测试、发布文档
- `dist/`：构建产物（gitignore）
- `.scratch/`：本地 issue tracker（gitignore）
