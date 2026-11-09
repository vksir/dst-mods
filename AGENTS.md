# dst-mods

饥荒联机版（DST）mod 集合仓库，每个子目录一个独立 mod。

> **开发 DST mod 前必读 [`docs/dst-modding-pitfalls.md`](docs/dst-modding-pitfalls.md)**：
> modmain/modinfo 沙箱标准库残缺（直接引用 next/pcall/string 会闪退）、
> shard 架构、客户端图标缓存、调试日志位置、创意工坊发布（VDF 覆盖文案 / tags 无效 / 语言槽位）
> 等已踩过的坑。
>
> **部署方式**：游戏 mods 目录中的 mod 文件夹是指向本仓库的 **Junction**
> （`mklink /J`，无需管理员），仓库即游戏目录，**改完即生效，无需复制**；
> 详见踩坑文档 §6。
>
> **发布**：统一用官方 `Don't Starve Mod Tools\ModUploader.exe`
> （`client_only_mod` / `version:x.y.z` 这类工坊 tags 只有它能写，steamcmd 写不了）；
> 坑与校验方法见踩坑文档 §10。

## Agent skills

### Issue tracker

Issue 以本地 markdown 文件形式存放在 `.scratch/<feature-slug>/`。See `docs/agents/issue-tracker.md`.

### Triage labels

五个规范角色直接作为标签字符串（本地 tracker 中记录为 issue 文件的 `Status:` 行）。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context：根目录 `GLOSSARY.md` + `docs/adr/`。See `docs/agents/domain.md`.
