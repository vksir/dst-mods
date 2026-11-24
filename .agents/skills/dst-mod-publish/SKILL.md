---
name: dst-mod-publish
description: 把 dst-mods 仓库里的 mod 发布/更新到 Steam 创意工坊（中英双语标题+描述、工坊标签、版本号）。当用户说“发布/更新/上传这个 mod”“改工坊描述/标题”“版本号要递增”“工坊上说 mod 过期”时使用。
---

# 发布 DST mod 到创意工坊（本项目流程）

发布 = 一个脚本 + 一次校验。**禁止**再用网页手改描述、也不要用 steamcmd（改不了工坊标签）。

## 0. 先确认三件事

```bash
cd /d/Code/MyMods/dst-mods
tasklist //FI "IMAGENAME eq dontstarve*"        # 必须为空：游戏要先关
tasklist //FI "IMAGENAME eq steam.exe"          # 必须在跑，且登录的是发布账号（不要在这里写账号）
python -c "import ctypes;print(ctypes.sizeof(ctypes.c_void_p))"   # 必须是 8（64 位 Python）
```

工坊条目 id 固定在 `docs/mods/<mod>/publishing.md` §1「条目信息」：

| mod | 工坊条目 |
|---|---|
| `wanda_planar_plan` | `3842009601` |
| `save_equipment_slots_fix` | `3836742363` |

## 1. 改文案 → 只改这两个文件

```
docs/mods/<mod>/workshop/zh.txt     中文标题/正文
docs/mods/<mod>/workshop/en.txt     英文标题/正文
```

格式固定三行规则：**第 1 行标题；第 2 行留空；第 3 行起是正文**（BBCode 子集，真换行，不要 Markdown）。

**两个槽位各写各的语言**：`zh.txt` 只写中文（不要「中文 + [hr][/hr] + 英文」的混排），
`en.txt` 只写英文。中文标题里带英文 mod 名可以（`旺达位面计划（Wanda Planar Plan）`），正文不行。

`docs/mods/<mod>/publishing.md` 只留条目信息、截图清单、Patch Notes、检查清单——**不再放正文**。

线上文案才是准的（用户可能直接在网页改过）。要把线上同步回本地：

```bash
python tools/common/workshop.py dump --mod mods/<mod> --item <ID>
# en 取 Web API 原文；zh 走社区页并把 HTML 逆推回 BBCode（UGC 查询描述只回前 256 字符，别用）
# 社区页 429 时等几十秒重试；实在拿不到再用 --from-ugc 兜底（会被截断，会告警）
```

## 2. 升版本（每次发布必做）

- `mods/<mod>/modinfo.lua` 的 `version` +1（如 `0.4.1` → `0.4.2`），工坊标签 `version:x.y.z` 由它生成；
  不升版本 = 玩家端继续提示「mod 过期」。
- 同轮改 `docs/mods/<mod>/publishing.md` §6 Patch Notes（一行标题 + 2~4 条要点）。
- 介绍页每写一条功能，都要有验收报告支撑（`docs/mods/<mod>/testing.md`）。

## 3. 先看计划，再发

```bash
python tools/common/workshop.py plan --mod mods/<mod> --item <ID>
```

`plan` 会给出：新标签（保留 `character`/`tweak` 等分类标签，只换类型标记与 `version:`）、
要提交的双语文案、以及 preflight 警告。**有警告先修**，不要 `--force`（除非你清楚后果）。

## 4. 发布

```bash
python tools/common/workshop.py publish --mod mods/<mod> --item <ID> \
        --changenote "v<x.y.z> — 一句话总结"
```

脚本行为：内容 + 标签 + 预览图挂在第一次提交（english 文案一起），随后为中文槽位再提交一次。
`--dry-run` 只看不发；`--no-copy` 只更内容不动文案；`--pages` 额外抽中英社区页核对。

**只改文案（不升版本）**：

```bash
python tools/common/workshop.py publish --mod mods/<mod> --item <ID>         --changenote "文案：…" --copy-only --langs zh
```

`--copy-only` 不提交内容/标签/预览图、也不再拦「版本没递增」；`--langs zh` 只写中文槽位。

## 5. 校验（必须做）

```bash
python tools/common/workshop.py verify --item <ID>          # english 槽位 + 标签 + time_updated
python tools/common/workshop.py verify --item <ID> --pages  # 再看中英社区页（偶发抽查，别连刷）
```

确认四点：`tags` 含 `version:<新版本>` 与类型标记、`description` 没被意外覆盖、
`time_updated` 是刚才、中文槽位标题/正文正确。

## 硬限制（Steam 侧，绕不过）

1. **一次提交只认一种语言**：`SetItemUpdateLanguage` 只对随后的标题/描述生效 → 双语必须两次提交。
2. **changenote 不分语言**：所以「改动说明」里会有两条；第二条默认「（同步其他语言页面文案）」，
   可用 `--lang-changenote` 改；**不要传空串**（会留一条无正文记录，删不掉）。
3. **UGC 查询的描述只回前 256 字符**，中文全文只能从社区页取。
4. 首发（新建条目）仍用官方 ModUploader；本脚本只更新已有条目。

## 出问题先看这里

| 症状 | 原因 / 处理 |
|---|---|
| `SteamAPI_Init 失败` | Steam 没开／没登录发布账号，或游戏还在跑 |
| `StartItemUpdate 失败` | 条目 id 错，或当前 Steam 账号不是该条目作者 |
| `版本标签没变化` 警告 | `modinfo.version` 没升，先升再发 |
| 标签没变 | 只传了内容？必须走 `publish`（`SetItemTags`）而不是 steamcmd |
| 中文页没变 | 中文那次提交被跳过了；检查 `workshop/zh.txt` 是否存在 |
| 社区页 429 | 请求太快，隔 1 分钟再试；日常校验用 `verify` 不带 `--pages` |

细节与背景见 `docs/mods/common/publishing.md`，工具说明见 `tools/common/README.md`。
