# Issue Tracker：本地 Markdown

本仓库的 issue 与规格说明以 markdown 文件形式存放在 `.scratch/`。

## 约定

- 每个功能一个目录：`.scratch/<feature-slug>/`
- 规格说明：`.scratch/<feature-slug>/spec.md`
- 实现 issue 一个文件一条：`.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 开始编号，不使用合并的大文件
- 状态记录在 issue 文件顶部的 `Status:` 行，取值见 `triage-labels.md` 中的五个角色字符串
- 评论与讨论历史追加在文件底部的 `## Comments` 标题下

## 当技能要求“发布到 issue tracker”

在 `.scratch/<feature-slug>/` 下创建新文件（必要时自动创建目录）。

## 当技能要求“获取相关 ticket”

读取对应路径的文件。用户通常会直接给出路径或编号。

## Wayfinding 操作（供 /wayfinder 使用）

- **Map**：`.scratch/<effort>/map.md`（Notes / Decisions-so-far / Fog 正文）
- **子 ticket**：`.scratch/<effort>/issues/NN-<slug>.md`，从 `01` 编号，正文记录问题；`Type:` 行记录类型（`research` / `prototype` / `grilling` / `task`），`Status:` 行记录 `claimed` / `resolved`
- **阻塞**：文件顶部 `Blocked by: NN, NN` 行；所列文件全部 resolved 后解除阻塞
- **Frontier**：扫描 open、无阻塞、未认领的文件，编号最小者优先
- **认领**：动手前先写 `Status: claimed`
- **解决**：在 `## Answer` 标题下追加答案，置 `Status: resolved`，并把结论摘要回填到 map.md 的 Decisions-so-far
