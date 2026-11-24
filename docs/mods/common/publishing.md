# 发布指南（创意工坊）· 通用

> 本文规定**流程**与**介绍页写法**；每个 mod 的**文案**（中英标题 + 正文）放在
> `docs/mods/<mod>/workshop/{en,zh}.txt`（脚本直接读，线上为准留档），条目信息、截图清单、
> Patch Notes 放在 `docs/mods/<mod>/publishing.md`。
> 遇到新坑回写本文，别只改单 mod 文档。

## 目录

1. [两条发布通道：GUI 首发 / 脚本更新](#1-两条发布通道gui-首发--脚本更新)
2. [介绍页文案规范（重点）](#2-介绍页文案规范重点)
3. [发布前准备](#3-发布前准备)
4. [上传流程](#4-上传流程)
5. [标签是怎么来的](#5-标签是怎么来的)
6. [校验上传结果](#6-校验上传结果)
7. [常见坑](#7-常见坑)
8. [发布检查清单](#8-发布检查清单)

---

## 1. 两条发布通道：GUI 首发 / 脚本更新

**首发**用官方 `Don't Starve Mod Tools\ModUploader.exe`（要填标题、粘正文、传截图，只有 GUI 顺手）；
**之后的每次内容更新**用仓库脚本 [`tools/common/workshop.py`](../../../tools/common/workshop.py)，
免手动操作、不改网页上润色过的描述。

```bash
cd D:/Code/MyMods/dst-mods
# 1) 先看要发生什么（会读条目现有标签、算新标签、跑 preflight）
python tools/common/workshop.py plan    --mod mods/<mod> --item <工坊ID>
# 2) 上传内容 + 刷新 version 标签（不传 --title / --description-file 就完全不碰标题与描述）
python tools/common/workshop.py publish --mod mods/<mod> --item <工坊ID> \
                                        --changenote "v0.4.2 — 一句话改了什么"
# 3) 校验（工坊侧落库有延迟，脚本已内置重试）
python tools/common/workshop.py verify  --item <工坊ID>
```

前置条件：**Steam 客户端已用发布账号登录**、游戏已关闭、64 位 Python；
`steam_api64.dll` 直接复用 DST 自带的 `bin64/steam_api64.dll`。
脚本做的是和 ModUploader 的 Update 完全一样的事（`ISteamUGC::StartItemUpdate` →
`SetItemTags` / `SetItemContent` / `SetItemPreview` → `SubmitItemUpdate`）。

### 1.1 为什么不用 steamcmd（2026-11-24 实测，结论：只能传内容，改不了标签）

`steamcmd +login <账号> +workshop_build_item <vdf>` 能无人值守跑通（缓存登录），
但 VDF 只认这几个键——`steamconsole64.dll` 里的键名白名单就是它们：

```
workshopitem / publishedfileid / title / description / visibility /
previewfile / contentfolder / kvtags / changenote
```

**没有 `tags`**。实测写 `"tags" "client_only_mod,version:0.0.1"`，上传成功、
`GetPublishedFileDetails` 回来 `tags: []` ——`client_only_mod` / `all_clients_require_mod` /
`version:x.y.z` 一个都写不进去。而 DST 客户端二进制里明确有
`all_clients_require_mod` / `version_compatible` / `version:` 与
`[Mod Warning] %s is out of date and needs to be updated for new users to be able to join the server`，
说明「mod 过期」判定就看这些标签 → **steamcmd 单独用不了**。

顺带确认的两条 steamcmd 事实（以后想用它当备份手段时有用）：

1. `description` / `title` 是整体替换，不写就保持原样（想保网页润色版就一个字都别写）；
2. **描述里写真实换行（引号内直接换行）能落成真换行**，写 `\n` 两字符会原样显示。

### 1.2 脚本与 ModUploader 的差别

| 项 | ModUploader（GUI） | `workshop.py` |
|---|---|---|
| 新建条目 | 支持 | 不支持（首发仍走 GUI；之后用 `--item` 更新） |
| 标签 | 从 modinfo 生成 + 分类勾选 | 读现有标签，只替换 mod 类型标记与 `version:`，**分类标签（character/tweak/item…）原样保留** |
| 标题 / 描述 | 只能写 english 槽位（多语言得回网页手改） | **中英双语一起写**（读 `workshop/{en,zh}.txt`） |
| 预览图 | 用 mod 目录里的 `preview.jpg` | 同上（preview.jpg 缺失会 preflight 拦下） |
| 多人协作 / 无人值守 | 不行 | 行（CI、agent 都能跑） |
| 删条目 | GUI 有删除按钮 | `delete --item <ID> --yes`（自测清理用） |

### 1.3 双语文案：仓库里改，一条命令同步

工坊条目每个语言一个标题 + 一份描述。**别再回网页手改**，改成编辑仓库文件：

```
docs/mods/<mod>/workshop/en.txt     英文标题 / 正文
docs/mods/<mod>/workshop/zh.txt     中文标题 / 正文
```

文件格式就三行规则：**第 1 行标题；第 2 行留空；第 3 行起是正文**（BBCode 子集，真换行）。
`workshop.py publish` 自动读它们并逐语言提交；没有这两个文件就完全不碰标题与描述。

```bash
# 文案有改、内容也有改：一次搞定
python tools/common/workshop.py publish --mod mods/<mod> --item <ID> \
        --changenote "v<x.y.z> — 一句话"
# 提交后核验双语页面（会抽一次社区页，别刷）
python tools/common/workshop.py verify --item <ID> --pages
# 想把线上文案拉回本地（迁移/对齐）
python tools/common/workshop.py dump --mod mods/<mod> --item <ID>
```

三条硬限制（实测，改不了）：

1. **Steam 的一次更新只认一个语言**：`SetItemUpdateLanguage` 只对随后的标题/描述生效，
   后一次会把前一次覆盖掉 → 双语必须**两次提交**。脚本已把内容/标签/预览图挂在第一次上，
   第二次只换中文槽位。
2. **changenote 不分语言**：两次提交就会在「改动说明」留两条记录。脚本给第二条用
   `--lang-changenote`（默认「（同步其他语言页面文案）」），想要别的文案就传参；
   传空串会留一条无正文记录（删不掉，见 §7）。
3. **UGC 查询读描述会被截到 256 字符**：所以 `dump` 的 en 正文取自 Web API，zh 正文走社区页
   并把渲染后的 HTML 逆推回 BBCode（`page_to_bbcode`）；社区页 429 时才用 `--from-ugc` 兜底。

---

## 2. 介绍页文案规范（重点）

工坊介绍页 = **标题 + 正文 + 截图 + 更新日志**。四者都在上传器里填/上传，网页可再编辑。
正文是玩家决定要不要订阅的唯一依据，按下面的格式写。

### 2.1 标题

- **代码里的名字只能 ASCII**：`modinfo.name` 用纯英文（与 mod 文件夹名一致），中文名放**工坊标题**与
  `description`。文件夹名 / prefab 名 / netvar 名 / 资源路径同理一律 ASCII——中文会跟着进存档键、
  文件路径、日志与工坊标签，出问题很难查；
- 工坊标题格式：`<英文名> <中文名>`，例：`Wanda Planar Plan 旺达位面计划`；
- 一句话说清"这是什么"（角色加强包 / 修复版 / 建筑包），不超过 40 字符；
- 与原 `modinfo.name` 保持一致，避免游戏内列表与工坊页对不上。

### 2.2 正文结构（固定骨架）

```bbcode
[h1]中文标题[/h1]

一句话简介（这个 mod 解决什么问题）。

[h2]功能[/h2]
[list]
[*]功能 1：一句话 + 关键数值
[*]功能 2：……
[/list]

[h2]配置[/h2]
所有功能可在「模组配置」中单独开关。

[h2]反馈[/h2]
问题请在评论区反馈，附上游戏版本和你装的其它 mod。

（只有"标签表达不了的兼容性/冲突"才另起一节，例如"请先禁用原版 XXX"。）

[hr][/hr]

[h1]English[/h1]

One-sentence summary.

[h2]Features[/h2]
[list]
[*]Feature 1 …
[*]Feature 2 …
[/list]
```

规则：

1. **中文在前、英文在后**，中间用 `[hr][/hr]` 分隔（浏览者按语言往下翻，不用切页）；
2. 数值写进正文（`30% / 50%`、`12 格`），玩家最关心；改数值时**同一轮**改这里；
3. **每条功能一句话说完，只写核心功能与玩家关心的点**。机制细节一律不写，包括：
   状态存在谁身上、叠加/计算公式、UI 布局如何排、配方材料清单——这些玩家进游戏就能看到，
   写进介绍页只会把页面撑长、没人读（用户明确要求"以简要为主"）；
4. **不要写安装要求**（"服务器和客户端都要装" / "客户端 mod 自己装就行"）：工坊标签
   （`all_clients_require_mod` / `client_only_mod`）已经表达，正文再写一遍是冗余，
   改档时还容易和标签矛盾。只写**标签表达不了**的兼容性/冲突（例："请先禁用原版 XXX"）；
5. 结尾可留问题反馈渠道（工坊评论区即可，`forumthread` 留空）；
6. 每条功能都要有验收结论支撑（见 [测试指南](testing.md)），别把"计划做"写成"已做"。

### 2.3 支持的 BBCode 子集

Steam 工坊描述框支持（够用即可，别用 Markdown，**不渲染**）：

| 标签 | 用途 |
|---|---|
| `[h1]…[/h1]` `[h2]…[/h2]` `[h3]…[/h3]` | 标题层级 |
| `[b]…[/b]` `[i]…[/i]` `[u]…[/u]` `[strike]…[/strike]` | 强调 |
| `[list]` + `[*]` + `[/list]` | 无序列表（**不要**手打 `- `） |
| `[hr][/hr]` | 分隔线（中英分界） |
| `[url=链接]文字[/url]` | 链接（原 mod、相关 mod） |
| `[img]图片URL[/img]` | 外链图（工坊页图片请在页面侧栏上传，别依赖外链） |
| `[quote]…[/quote]` `[code]…[/code]` `[spoiler]…[/spoiler]` | 引用 / 代码 / 折叠 |

**换行就是换行**（别写 `\n`）；空行才会产生段落间距。

### 2.4 中英双语怎么排

- **两个槽位各写各的语言，不要混排**：`workshop/zh.txt` **只写中文**，`workshop/en.txt` 只写英文。
  早期为了省事在中文槽位里放了「中文 + `[hr][/hr]` + 英文」，现在没必要（2026-11-24 已拆开）；
  英文玩家看 english 槽位，中文玩家看 schinese 槽位，混排只会让两边都多出一段看不懂的文本；
- 标题同理：中文标题可以带英文 mod 名（`旺达位面计划（Wanda Planar Plan）`），但描述正文只用中文；
- `dump` 会照抄线上现状，所以拉回来之后要自己确认没有混排（`grep -E '[A-Za-z]{20,}' workshop/zh.txt` 能快速兜一遍）；
- 英文用短句，避免中文式长句；专有名词（mod 名/角色名）保留原名。

### 2.5 截图（工坊页项目）

建议 5 张，页面侧栏上传，文件名即顺序：

| # | 内容 |
|---|---|
| 1 | 封面：游戏内全景 + mod 名叠字（清晰、无 UI 遮挡关键内容） |
| 2 | 核心新内容（新物品/新面板）在物品栏与地面的样子 |
| 3 | 实际使用中的界面（打开容器 / 悬停文案 / 配置界面） |
| 4 | 数值或效果对比（改前 vs 改后） |
| 5 | 配置菜单（让玩家知道可开关） |

截图来源可直接用验收报告里的证据图（分辨率足够、已核对过），但**不要**把带调试日志/水印的图放上去。

### 2.6 更新日志（Patch Notes）

- 每次有实质改动就写，格式：`v0.4.0 — 一句话总结` + 2~4 条要点；
- **别留空**：留空会在「改动说明」里留一条无正文记录，删不掉；
- 与 `modinfo.version` 一致（工坊标签 `version:0.4.0` 自动生成）。

### 2.7 定稿放哪

- **唯一来源**：`docs/mods/<mod>/workshop/{en,zh}.txt`（第 1 行标题 / 第 2 行空 / 其余正文）；
- 想拿线上最新版本就用 `workshop.py dump` 拉回来（以线上为准），改完再 `publish` 推上去；
- `publishing.md` 不再放正文（避免两处副本打架），只留条目信息、截图清单、Patch Notes、检查清单；
- 脚本每次 Update 都会整体覆盖对应语言槽位，**以这两个 txt 为准**。

---

## 3. 发布前准备

### 3.1 `modinfo.lua` 字段

| 字段 | 注意 |
|---|---|
| `name` | **纯 ASCII**；与 mod 文件夹名一致 |
| `description` | 游戏内简介（可中文）；与 hover、介绍页的数值必须一致 |
| `author` / `version` | `version = "0.1.2"` → 工坊标签 `version:0.1.2` |
| `client_only_mod` / `server_only_mod` / `all_clients_require_mod` | 决定工坊标签，也决定玩家怎么装（见 §5） |
| `api_version` / `api_version_dst` / `*_compatible` | 兼容性标签 |
| `server_filter_tags` | 服务器筛选（不影响工坊标签） |
| `configuration_options` | hover 文案随数值一起改 |

### 3.2 mod 目录：只留本体 + 一张 `preview.jpg`

上传器是 **ALL files in directory will be uploaded**：README、调试截图、`.scratch` 链接都会进
订阅者的下载包（体积对不上时先查目录多了什么，曾靠 15KB/13KB 差值抓到 README）。

**唯一的例外是 `preview.jpg`——它必须放在 mod 目录里**：ModUploader 上传时用这张图作为
**工坊条目的预览图**，缺了就只有默认灰底图。

| 要求 | 值 |
|---|---|
| 路径 | `mods/<mod>/preview.jpg` |
| 尺寸 | **268×268**（原版 mod 的既有约定；上传器会自己生成各尺寸缩略图） |
| 格式 | JPG（RGB，别用带透明通道的 PNG 改名） |
| 内容 | 三件代表性内容横排 + mod 名（缩略图会缩到 ~120px 显示，字要大、主体要少） |

> **这是宣传图，由用户拍板，AGENT 不要擅自生成/替换**：
> 发布前只需**提醒用户准备**并给出上述规格；用户明确要求时才可代做，且产物要标注为
> "占位，待用户确认"。改视觉素材时也别顺手覆盖它。

### 3.3 先出验收报告

见 [测试指南](testing.md)。介绍页里写的每条功能，都要有对应的验收结论，别凭"我以为"写文案。

---

## 4. 上传流程

### 4.1 首发（只有一次，GUI）

1. **关游戏**（工具要占用 AppID 322330 的 Steam 接口）；
2. **先递增 `modinfo.version`**（`0.4.0` → `0.4.1`）。工坊标签 `version:x.y.z` 由它生成，
   不递增的话标签不刷新，玩家游戏内会一直提示「mod 过期」——**每次重新上传都要 +1**；
3. 启动 `ModUploader.exe`；
4. **不选已有条目**（= 新建条目，见 §7）；
5. 目录选 `D:\Code\MyMods\dst-mods\mods\<mod>`；
6. 标题 → 粘 `docs/mods/<mod>/workshop/en.txt` 的正文（中文槽位留给 §4.2 的脚本补）→ Patch Notes；
7. Upload；
8. 用 Web API / `workshop.py verify` 校验（§6），把条目 ID 回填到 `docs/mods/<mod>/publishing.md`，
   再回网页补截图与语言槽位。

### 4.2 更新（每次发版，脚本一条命令）

1. **关游戏**（避免抢 Steam 接口；`workshop.py` 的 preflight 会拦）；
2. 递增 `modinfo.version` + 同步 `docs/mods/<mod>/publishing.md` 的 Patch Notes（同一轮改完）；
3. `python tools/common/workshop.py plan --mod mods/<mod> --item <ID>`：
   看新标签里 `version:` 是否已变、分类标签是否保留、有无 preflight 警告；
4. `python tools/common/workshop.py publish --mod mods/<mod> --item <ID> --changenote "v<x.y.z> — 一句话"`；
5. 脚本末尾会自己回读工坊侧 `tags` 到预期值才算成功（落库有 1~2 分钟延迟），并打印 Web API 结果；
6. 如该版有新截图，去网页后台上传（脚本不管截图，`preview.jpg` 除外）。

### 4.3 只想改文案（不升版本）

文案改动不需要动内容，也不需要递增 `modinfo.version`：

```bash
python tools/common/workshop.py publish --mod mods/<mod> --item <ID>         --changenote "文案：中文页面只保留中文" --copy-only --langs zh
```

- `--copy-only`：不提交内容/标签/预览图，只写语言槽位，也不再因为「版本没递增」拦你；
- `--langs zh`：只提交中文槽位（避免给 english 槽位留下一条内容没变的改动记录）；
- 校验：`--copy-only` 模式下会核对 english 槽位与 `workshop/en.txt` 是否一致；
  中文槽位的内容级核对要读社区页（`page_to_bbcode`），频繁请求会被 429，隔几分钟再抓。

---

## 5. 标签是怎么来的

上传器读 `modinfo.lua` 自动生成，**网页上改无效**：

| modinfo | 工坊标签 |
|---|---|
| `client_only_mod = true` | `client_only_mod` |
| `server_only_mod = true` | `server_only_mod` |
| `all_clients_require_mod = true` | `all_clients_require_mod` |
| `*_compatible` | 各 DLC 兼容标签 |
| `version = "x.y.z"` | `version:x.y.z` |

给玩家的安装说明必须与这三个开关一致：
`client_only_mod` → "自己装就行"；`all_clients_require_mod` → "服务器和每个玩家都要装"。

---

## 6. 校验上传结果

两条路，结果一样：脚本的 `verify` 子命令（或 `publish` 末尾自带的回读）与手写 curl。
**别刷社区页**（会 429，返回 12KB 错误壳，HTML 结构还随 A/B 变）：

```bash
python tools/common/workshop.py verify --item <ID>
```

```bash
curl -s -X POST https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/ \
  --data "itemcount=1&publishedfileids[0]=<ID>"
```

返回 `title` / `tags` / `description` / `time_updated`，无需登录。可确认：

- 描述有没有被覆盖、换行是真换行（`0x0A`）还是字面量（`0x5C 0x6E`）；
- 标签有没有变（尤其 `version:`）；
- `time_updated` 是否是刚才。

---

## 7. 常见坑

| 坑 | 症状 / 后果 | 处理 |
|---|---|---|
| **想用 steamcmd 刷标签** | VDF 没有 `tags` 键，上传成功但 `client_only_mod` / `version:` 都不变，游戏内提示 mod 过期 | 用 `tools/common/workshop.py`（ISteamUGC），见 §1.1 |
| **把 `kvtags` 当标签用** | `kvtags` 只是后台元数据，页面不显示、不能筛选、DST 也不读 | 工坊可见标签只能通过 ISteamUGC 写 |
| **Steam 登了别的号** | `StartItemUpdate` 失败或传错账号名下 | 发布账号先登 Steam 客户端（脚本不带密码，不存凭证） |
| **一次提交想写两种语言** | 只有最后一次 `SetItemUpdateLanguage` 的语言生效，另一种静默丢失 | 双语分两次提交，用 `publish`（脚本已内置） |
| **想直读中文文案** | UGC 查询的描述字段只回前 256 字符 | 用 `dump`（走社区页逆推 BBCode）拉全文 |
| **网页上手改了描述** | 下次 `publish` 会整体覆盖回 `workshop/*.txt` | 改描述只改文件；网页改了就 `dump` 拉回本地再发 |
| **`dump` 之后不核对** | 线上旧文案被当成新定稿写进仓库 | `dump` 后过一遍 `git diff`，确认是想要的那版 |
| **`dump` 出来的链接带 `[url=…]`/`linkfilter`** | 社区页会把裸链接渲染成 `<a>`，逆推后多出 `[url=https://steamcommunity.com/linkfilter/?u=…]` | 转换噪声，不影响渲染；把裸链接手写回去更干净 |
| **不选条目** | 生成**新**工坊 ID，旧条目成孤儿 | 下拉里选中旧条目；误建的用工具 Delete 删（删掉的条目网页返回 500） |
| **描述框覆盖** | 网页润色过的排版被打回 | 定稿以 `docs/mods/<mod>/workshop/*.txt` 为准 |
| **描述框没有语言选项** | 内容落 `english` 槽位 | 中英并列放在一个正文里（§2.4），或上传后网页补中文槽位 |
| **用了 Markdown** | 页面显示原始 `**粗体**` | 只用 §2.3 的 BBCode 子集 |
| **介绍页写太细** | 没人看；改一次数值还要同步改文案 | 只留核心功能一句话，细节放 `features.md`（§2.2 规则 3） |
| **正文写安装要求** | 与工坊标签重复；改 `client_only_mod` 后正文忘了改就成了矛盾信息 | 安装要求交给标签，正文只写兼容性/冲突（§2.2 规则 4） |
| **Patch Notes 留空** | 「改动说明」出现无正文记录，删不掉 | 有改动就写一行 |
| **语言槽位没配** | 别的语言用户只看得到 English | 网页逐语言补标题/描述 |
| **游戏没关** | 上传器抢不到 Steam 接口 | 先关游戏 |
| **重新上传忘了递增版本** | 工坊 `version:x.y.z` 标签不刷新，玩家游戏内提示「mod 过期」，Steam 也不会当新版本分发 | 每次上传前 `modinfo.version` +1（§4 步骤 2） |
| **mod 目录有杂物** | 订阅者下载包里混进 README/截图 | 只留 mod 本体 |
| **标签想去网页改** | 改了没用 | 只能通过 modinfo + 重新上传 |

工坊条目数据模型（备忘）：

- 标题/描述**按语言分别存**（`ISteamUGC::SetItemUpdateLanguage`，不设置默认 `english`），
  页面按浏览者语言取，**没有的语种回退 English**；
- `changenote` 不分语言；
- 没有"版本号"字段，只能靠 `version:x.y.z` 标签。

---

## 8. 发布检查清单

```
[ ] 验收报告已出（common/testing.md），介绍页每条功能都有结论支撑
[ ] grep -rn "TEMP\|\[T\]\|\[DBG\]\|print(" mods/<mod> --include=*.lua   → 0
[ ] 临时自检模块 scripts/<mod>_selftest.lua 已删
[ ] 资源都有 Asset 声明；日志无 "Invalid resource handle" / "variable … is not declared"
[ ] modinfo 的 description / hover / 配置项文案与实际数值一致
[ ] modinfo.version 已递增；介绍页 Patch Notes 与之对齐
[ ] 介绍页标题/正文与 docs/mods/<mod>/workshop/{en,zh}.txt 一致（线上改过就先 dump 拉回）
[ ] mod 目录里没有 README、调试 png、.scratch 残留
[ ] 已提醒用户准备 mods/<mod>/preview.jpg（268×268 宣传图，上传器拿它当工坊预览图）
[ ] 游戏已关闭 → `workshop.py plan` 无警告 → `publish --changenote` → `verify --pages` 回读双语标签与文案
[ ] 中英两个语言槽位都核对过（标题 + 正文）；改动说明没有第二条空记录
[ ] 网页补截图、语言槽位（语言槽位现在由脚本写，只差截图）
```
