# DST Mod 文档

文档按 **通用 / 单个 mod** 两级组织：

```
docs/mods/
├── common/                     通用（所有 mod 都适用）
│   ├── development.md          开发指南：沙箱、Asset、图标/动画管线、动作、容器 UI、存档、调试、工具
│   ├── testing.md              测试指南：验收硬性要求、报告模板、测试分层、环境手册、回归清单
│   └── publishing.md           发布指南：首发走 GUI / 更新走脚本（workshop.py）、介绍页文案规范、标签、校验
└── <mod>/                      每个 mod 五份
    ├── features.md             功能说明（面向玩家：有哪些功能、怎么用；不含部署）
    ├── development.md          该 mod 的设计决策、代码结构、特有常量与踩坑
    ├── testing.md              该 mod 的断言项、验证矩阵、回归清单
    ├── publishing.md           该 mod 的工坊条目：标题、正文（中英双语 BBCode）、截图、更新日志
    └── workshop/               机器读的双语文案：en.txt / zh.txt（第1行标题 / 第2行空 / 其余正文），
                                `tools/common/workshop.py publish` 直接读它发布
```

| mod | 文档 |
|---|---|
| `wanda_planar_plan` 旺达位面计划 | [功能](wanda_planar_plan/features.md) · [开发](wanda_planar_plan/development.md) · [测试](wanda_planar_plan/testing.md) · [发布](wanda_planar_plan/publishing.md) |
| `save_equipment_slots_fix` 装备槽记忆修复 | [功能](save_equipment_slots_fix/features.md) · [开发](save_equipment_slots_fix/development.md) · [测试](save_equipment_slots_fix/testing.md) · [发布](save_equipment_slots_fix/publishing.md) |

其它参考：

| 文档 | 内容 |
|---|---|
| [术语表](../../GLOSSARY.md) | shard、build、bank、rpc、netvar… |
| [`.scratch/<feature>/`](../../.scratch) | 本地 issue tracker（需求拆解、状态、临时脚本，gitignore） |

## 一轮开发的流程

```
需求（用户口头/速记）
  → .scratch/<feature-slug>/spec.md      拆成可验收的条目
  → 写代码（common/development.md + <mod>/development.md）
  → 实测验收（common/testing.md + <mod>/testing.md）→ 验收报告（博客仓库 v<N>/）
  → 更新 <mod>/features.md（面向玩家）与 <mod>/publishing.md（工坊页正文）
  → **沉淀**：把本轮用户的要求与纠正写成 common/ 或 <mod>/ 里的规则（不是只留在对话里）
  → 发布（common/publishing.md）
```

沉淀是硬性要求（见 `AGENTS.md` 的「规范」）：用户指出过的问题必须变成文档里的规则或坑，
否则下一轮还会犯。

## 写文档的约定

- **通用结论进 `common/`，mod 专有内容进 `<mod>/`**：一条经验只要对第二个 mod 也可能成立，就写 common；
- **用户提的每条要求/纠正都要落成文档里的规则，不能只改代码**：
  需求进 `.scratch/<feature>/spec.md`，做法进 `common/` 或 `<mod>/development.md`，
  验收标准进 `<mod>/testing.md`，文案/发布要求进 `common/publishing.md` 或 `<mod>/publishing.md`；
  同一类错误被用户指出第二次，说明上一条规则没写下来；
- 数值、坐标、配方这类会变的东西，**单一来源**是代码 + 该 mod 的 `features.md` / `publishing.md`，
  改代码时同一轮改这三处（`modinfo` 的 description/hover 也算一处）；
- **美术与宣传物料由用户拍板**（图标风格、`preview.jpg` 宣传图、工坊截图）：AGENT 只准备
  技术规格与提醒，不擅自替换正式素材；代做的产物一律标注"占位，待用户确认"；
- **接口/行为结论要带出处**：引擎行号（`playerhud.lua:402`）、实测日志、报告章节，方便下轮核对；
- 报告里"未验证"就写"未验证"，别写"应该没问题"。

## 仓库结构

```
dst-mods/
├── mods/<mod>/            每个子目录一个独立 mod（= 游戏 mods 目录里的 Junction 目标）
├── tools/
│   ├── common/            跨 mod 通用工具（uilook / gameinput / dstconsole / ktex2png）
│   └── <mod>/             只服务单个 mod 的生成器（画图标、生成 anim build）
├── docs/                  本目录 + 术语表 + agent 约定
├── dist/                  构建产物（gitignore）
└── .scratch/              本地 issue tracker / 调试脚本（gitignore）
```

## 最短上手（新 mod）

1. `mods/<mod>/` 建 `modinfo.lua` + `modmain.lua` + `images/`；
2. 做 Junction 让游戏直接读仓库（[common/development.md §1.2](common/development.md#12-junction-部署本仓库默认)）：
   ```bat
   mklink /J "…\Don't Starve Together\mods\<mod>" "D:\Code\MyMods\dst-mods\mods\<mod>"
   ```
3. 游戏内启用 → 改 lua 重进世界（改资源要重启）；
4. 验完出报告（[common/testing.md](common/testing.md)），再按 [common/publishing.md](common/publishing.md) 发布。
