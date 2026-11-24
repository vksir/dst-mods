# 测试指南（验收）

> 这份文档规定"改完怎么证明它成立"。仓库里每轮需求都要按它出验收报告。
> 报告实例：`D:\Code\MyBlog\笔记\开发\饥荒\Mod\旺达加强\v6\验收报告.md`（内嵌 8 张图 + 日志原文）、
> `…\v7\验收报告.md`（数值矩阵 + 中轴线实测表）。

## 目录

1. [硬性要求（用户明确提过的）](#1-硬性要求用户明确提过的)
2. [报告模板](#2-报告模板)
3. [测试分层：证据的可信度](#3-测试分层证据的可信度)
4. [测试环境手册](#4-测试环境手册)
5. [常见测试坑](#5-常见测试坑)
6. [每轮回归清单](#6-每轮回归清单)

---

## 1. 硬性要求（用户明确提过的）

来自历史需求（v3 第 5 条、v4 第 11 条、v5 第 6 条、v6 第 2 条），都是**返工过的**：

1. **每条需求都必须有验收依据**，不能只说"改好了"。
2. **报告与图片放固定位置**（按 mod、按版本分目录）：
   ```
   D:\Code\MyBlog\笔记\开发\饥荒\Mod\<mod>\v<N>\
   ├── 验收报告.md
   ├── 01-xxx.png / 02-xxx.png …     ← 证据图片
   └── 证据-日志原文.txt              ← 日志/断言原文（可选但强烈建议）
   ```
3. **报告要逐条列举用户需求原文**，每条后面紧跟验收凭据（表格或小节），
   顺序与用户提的顺序一致，不能打乱、不能合并。
4. **图片必须在报告里内嵌**（`![说明](01-xxx.png)`，同目录相对路径），
   不要只写"见 xxx.png"——用户要在一个页面里看完。
5. **只写真实跑过的结论**。没验证的一律写"未验证"并说明原因，绝不"推测通过"。
6. **提交前清临时码**：`grep -rn "TEMP\|\[T\]\|\[DBG\]" mods/<mod> --include=*.lua` 必须是 0，
   临时自检模块 `scripts/<mod>_selftest.lua` 要删。
7. 报告写清**测试环境**（分辨率 / UI 缩放 / 是否 host），否则坐标类结论别人无法复现。

## 2. 报告模板

```md
# <mod> v<N> 验收报告

> 需求来源：用户 <日期> 提出（<条数> 条）
> 环境：本机 2560×1440 全屏（逻辑 1280×720），HUDSize = 7，<mod> 最新代码
> 证据：本目录（图片全部内嵌，可直接查看）

## 需求清单

| # | 需求原文 | 结论 |
|---|---------|------|
| 1 | …… | ✅ 通过 |
| 2 | …… | ⚠️ 部分通过（见下） |

---

## 需求 1：<标题>

### 问题定位
<根因，带原版代码行号 / 日志>

### 实现
<关键代码片段，几行就够>

### 凭据
<日志原文 + 表格 + 图片>

![说明](01-xxx.png)

### 结论
✅ 通过 / ❌ 未通过（原因）

---

## 交付物
<改了哪些文件、证据文件清单>

## 未验证 / 已知限制
<逐条列出，不要省略>
```

写作要点：

- **结论符号统一**：`✅ 通过` / `⚠️ 部分通过` / `❌ 未通过` / `未验证`；
- 数值类需求给**矩阵表**（v7 老化倍率 3×3 那张），比一句"叠加正常"有说服力；
- 坐标/对齐类需求给**实测数字表**（期望 vs 实测 vs 误差），并注明分辨率；
- 有对比（改前/改后）就放对比图；
- 日志原文粘进报告，同时另存 `证据-日志原文.txt`（日志会被下次进世界清空）。

## 3. 测试分层：证据的可信度

从高到低，能上层解决就不要只靠下层。

### L1 代码断言（最可靠）

把状态打印出来对比，比看图猜强。用临时自检模块：

```lua
-- scripts/<mod>_selftest.lua（交付前删）
local M = {}
local function P(...) print("[T] " .. table.concat({...}, " ")) end
function M.Run()
    P("tier=" .. tostring(ThePlayer.components.oldager.rate))
end
return M
```

控制台：`require("my_mod_selftest").Run()`（`require` 缓存 → 改完文件先
`package.loaded["my_mod_selftest"]=nil`）。

### L2 截图 + 自己看图

```bash
agent-desktop screenshot --headed --app "dontstarve_steam_x64.exe" shot.png
```

**先断言"东西真的在"，再看"长什么样"**。典型翻车：把原版物品截图当成自己 icons 的证据
（v3 干过）。先 `print(inventory:GetItemInSlot(1).prefab)` 确认是 mod 物品，再截图。

### L3 屏幕模板匹配（存在性断言）

`tools/common/uilook.py`：从截图裁模板，再整屏找，score 可当阈值。

```bash
python tools/common/uilook.py crop shot.png 700,200,80,80 tpl.png
python tools/common/uilook.py find tpl.png --screen shot.png --threshold 0.9
```

适合断言"图标在物品栏第 1 格""面板出现在右侧坑位"。换分辨率要重截模板。

### L4 可靠的键盘输入

`tools/common/gameinput.py`（焦点校验 + Unicode）或 `tools/common/dstconsole.py`
（纯 PostMessage 注控制台，中文输入法下更稳）。

## 4. 测试环境手册

### 4.1 起服 / 进世界

```bash
cmd //c start "" "steam://rungameid/322330"        # 启动
powershell -NoProfile -Command "@(Get-Process dontstarve_steam_x64).Count"   # 是否在跑
```

自动化进世界（菜单点击）看完再点，别盲点：菜单会变（有更新、有公告）。

**判断"进世界了"**：日志出现 mod 的启动标记（如 `[V8] ready wanda`）。

### 4.2 控制台注入（无人值守的核心）

```bash
tools/common/dstlua.sh '[T] hi' 'print("[T] hi")'          # 执行直到日志出现标记
python tools/common/dstconsole.py 'c_give("goldnugget")'    # 单次注入
```

- ` ` ` 键是 **toggle**，脚本不知道当前状态 → `dstlua.sh` 内置 4 次重试；
- 字符用 `WM_CHAR` 逐字投递（12ms 间隔），直接 `PostMessage` **不需要窗口焦点**；
- 中文输入法会吞按键 → 这条路径专治；
- 控制台**已开着**时用 `--no-toggle`；
- 命令要单行；需要多语句用 `;` 串起来，末尾 `print` 一个标记便于断言。

### 4.3 临时自检模块（见 L1）

文件名带 mod 前缀，`[T]` 前缀便于 grep 清理。

### 4.4 日志与截图位置

| 东西 | 路径 |
|---|---|
| 客户端日志 | `文档/Klei/DoNotStarveTogether/client_log.txt`（本机 `D:/My/Documents/...`） |
| 服务端日志 | `.../Cluster_N/server_log.txt` |
| 游戏截图（F12） | `Steam/userdata/<id>/760/remote/322330/screenshots/` |
| 自动化截图 | 自己给绝对路径（`C:/Users/<u>/AppData/Local/Temp/...`） |

日志前缀按版本走（`[V6] [V8] [W7] …`），**交付前 grep 清零**。

### 4.5 状态复原

测完把玩家/世界恢复原样，否则下一轮测试从脏状态开始：

```lua
-- 测试常用"防死"三件套（角色常是幽灵）
if ThePlayer:HasTag("playerghost") then
    ThePlayer:RemoveTag("playerghost")
    ThePlayer.player_classified:SetGhostMode(false)
    ThePlayer:SetStateGraph("SGwilson"); ThePlayer.sg:GoToState("idle")
end
ThePlayer.components.health:SetPercent(1)
ThePlayer:SetInvincible(true)
-- 结束游戏（省电）
```

## 5. 常见测试坑

| 坑 | 症状 | 处理 |
|---|---|---|
| **改了 `prefab`/`modmain` 没重启** | 新旧代码混用，结论全是错的 | 改这些必须重启客户端；只有 `scripts/` 模块可 `package.loaded[x]=nil` 重载 |
| **改 `ThePlayer.prefab`** | HUD 直接毁掉，界面错乱 | 绝不要改；要换角色用 `c_spawn` 新角色 |
| **批量 `:Remove()` 实体** | 一次删几十个实体把游戏崩掉（踩过） | 分批、加数量上限（`if #rm < 40 then`），或干脆不删 |
| **幽灵状态** | 人物倒地、UI 消失、动作不触发 | 见 4.5 三件套 |
| **开容器动画没停就测量** | 面板坐标/包围盒是弹出动画中间值 | 等动画结束；判断 `GetVisualBB` 高度 < 200 视为未停 |
| **`widget:IsShown()` 不存在** | 报 nil | 读 `w.shown` / `w.parent.shown` |
| **`HUD:DoTaskInTime` 不存在** | 报 nil | 用 `ThePlayer:DoTaskInTime` |
| **`replica.container:IsOpen()` 不存在** | 报 nil | 用 `IsOpenedBy(player)` |
| **`taskkill //PID` 无效** | 进程杀不掉 | `powershell Stop-Process -Id <pid> -Force` |
| **不校验焦点就发键** | 按键进游戏当快捷键，弹出各种面板污染状态 | 用 `gameinput.py`（内置校验）或 `dstconsole.py` |
| **看截图认物品** | 把原版物品当自己的 | 先 L1 断言 prefab，再截图 |
| **测试窗口是独享资源** | 多个 agent 同时操作 → 互相踩 | 同一时刻只允许一个测试者（其它 worker 只写代码） |
| **存档 modoverrides 指向工坊 id** | 仓库里改了代码，进游戏却“没生效”（跑的是工坊旧版） | 宿主进世界时客户端会**重写** `modoverrides.lua`（把你手改的本地 mod 名改回 workshop id）→ 要么在“模组”界面切成本地 mod，要么临时把 `steamapps/workshop/content/322330/<id>` 换成本仓库代码（原名备份 + `.e2ebak`，测完还原） |
| **不知道控制台开没开** | ESC 想关控制台却弹出暂停菜单 | 实测：回车执行**成功**时控制台会自己关，**报错时**才留着；别盲按 ESC，截图看一眼 |
| **控制台里改的 ACTIONS 只改了一半** | 红/绿对照时客户端 tooltip 仍显示旧文案 | 宿主 VM 与真客户端是两份动作表；改字段做对照只能用服务端行为断言，并注明差异 |
| **角色是幽灵（寿命/饥饿）** | 动作列表里只剩 `LOOKAT`，啥都点不了 | `player_common_extensions.lua` 的 ghost 过滤器（优先级 99）只放行 `ghost_exclusive`；先 `PushEvent("respawnfromghost")` 再测 |

## 6. 每轮回归清单

需求改完，除了新功能，**上一轮修过的东西必须再验一遍**（很多 bug 是回归）：

```
[ ] 本轮每条需求：一条凭据（日志/截图/数值表）
[ ] 上一轮报告的"通过"项抽查 3 条，确认没被打回
[ ] 新存档 + 旧存档（改过存档字段时）各进一次世界
[ ] 客户端日志无 "variable … is not declared" / "Invalid resource handle"
[ ] 临时码 grep = 0；临时自检模块已删
[ ] 报告：需求逐条对应、图片内嵌、环境写清、未验证项列全
[ ] 测完关游戏（省电），HUD/分辨率设置恢复用户原值
```

### 报告自查（交出去之前）

- 用户能只读这一个文件就判断"过没过"吗？
- 每条结论后面有没有**紧跟**凭据？还是散落在别处？
- 有没有把"我改了代码"当成"它生效了"？（改完必须实测）
- 未验证项写清楚了吗？
