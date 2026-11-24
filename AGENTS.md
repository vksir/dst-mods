# dst-mods

饥荒联机版（DST）MOD 集合仓库。

## 准则

- 开发完成后必须用真实游戏做 E2E 验证并出验收报告；验证完关闭游戏。
- 提交前检查代码不含敏感/个性化信息，并确认临时调试代码已清空。
- **把用户提的每一项要求、每一条指导都沉淀成文档**，不要只改代码：细则见
  [`docs/mods/README.md`](docs/mods/README.md) 的「写文档的约定」。

### 安全规范

Git 仓库中禁止泄露：
- 个人网址、域名、IP 地址。
- 账号、密钥，特别是 LLM 密钥。
- 个人路径，如代码库绝对路径等。

## 指南（先读，别凭记忆写 DST 代码）

文档按 **通用 / 单 mod** 两级组织：

| 文档 | 内容 |
|---|---|
| [`docs/mods/README.md`](docs/mods/README.md) | 文档索引 + 开发流程 |
| [`docs/mods/common/development.md`](docs/mods/common/development.md) | 通用开发指南：沙箱白名单、Asset、图标/动画管线、动作、容器 UI、存档、调试、工具 |
| [`docs/mods/common/testing.md`](docs/mods/common/testing.md) | 通用测试指南：验收硬性要求、报告模板、测试分层、环境手册、回归清单 |
| [`docs/mods/common/publishing.md`](docs/mods/common/publishing.md) | 通用发布指南：首发用 ModUploader、**后续发布用 `tools/common/workshop.py`**、介绍页文案规范、标签、校验 |
| [`docs/mods/<mod>/`](docs/mods/) | 每个 mod 四份：`features.md`（功能说明，面向玩家）、`development.md`、`testing.md`、`publishing.md` |
| [`GLOSSARY.md`](GLOSSARY.md) | 术语表（shard、bank/build、rpc…） |

动手前按顺序读：`docs/mods/<mod>/features.md` → `common/development.md` → `<mod>/development.md`；
改数值/UI 后再读对应 `testing.md` 与 `publishing.md`（文案要与代码同轮更新）。

## Agent skills

### Issue tracker

Issue 以本地 markdown 文件形式存放在 `.scratch/<feature-slug>/`。See `docs/agents/issue-tracker.md`.

### Triage labels

五个规范角色直接作为标签字符串（本地 tracker 中记录为 issue 文件的 `Status:` 行）。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context：根目录 `GLOSSARY.md` + `docs/adr/`。See `docs/agents/domain.md`.

### 发布

发/更新工坊条目（内容 + 工坊标签 + 中英双语标题与描述）用项目 skill
`.agents/skills/dst-mod-publish/`（本地一份，`.agents/` 不入库）：
文案只改 `docs/mods/<mod>/workshop/{en,zh}.txt`（中文文件只写中文），
发布跑 `python tools/common/workshop.py publish`。不要用 steamcmd（改不了标签），
也不要在网页上手改描述（会被下次发布覆盖）。
