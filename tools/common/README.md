# tools/common —— 通用工具

零/轻依赖（numpy + Pillow 已在环境里），Windows + git-bash 下开发。
所有脚本都能从仓库根目录直接跑，脚本内用 `REPO = HERE/../..` 定位。

| 脚本 | 一句话 |
|---|---|
| [`dstconsole.py`](#dstconsolepy控制台注入) | 向游戏控制台注入一行 Lua（PostMessage，不依赖焦点） |
| [`dstlua.sh`](#dstluash执行到日志出现标记) | 反复注入直到日志出现标记（无人值守验收的骨架） |
| [`uilook.py`](#uilookpy屏幕模板匹配) | 屏幕模板匹配，可当"东西在不在"的断言 |
| [`gameinput.py`](#gameinputpy带焦点校验的输入) | 带焦点校验的键鼠输入，支持 Unicode |
| [`ktex2png.py`](#ktex2pngpy解码-ktex) | KTEX 解码，校验图标/图集产物 |
| [`workshop.py`](#workshoppy免-gui-发布) | 创意工坊发布/校验/删除（ISteamUGC，免 GUI） |

---

## dstconsole.py：控制台注入

```bash
python tools/common/dstconsole.py 'print("[T] hi")'
python tools/common/dstconsole.py 'c_give("goldnugget")' --app "Don't Starve Together"
python tools/common/dstconsole.py '...' --no-toggle      # 控制台已经开着
python tools/common/dstconsole.py '...' --no-enter       # 只输入不提交
```

- ` ` ` 键是 **toggle**，所以调用前不知道状态时会翻转 → 需要重试就用 `dstlua.sh`；
- 字符逐字用 `WM_CHAR` 投递（12ms 间隔），**不受中文输入法影响，也不需要窗口焦点**；
- 命令必须单行，多语句用 `;`，末尾 `print` 一个标记便于断言。

## dstlua.sh：执行到日志出现标记

```bash
tools/common/dstlua.sh '[T] hi' 'print("[T] hi")'
tools/common/dstlua.sh '[W7] ALIGN backpack' 'require("wanda_v7test").Align("backpack")'
```

- 最多试 4 次（每次 sleep 3s），日志出现标记就打印并退出 0；否则 `FAIL: <标记>` 退出 1；
- 日志路径自动探测（`$USERPROFILE/Documents/...`、`D:/My/Documents/...`），可用 `DST_LOG` 覆盖；
- 窗口标题可用 `DST_APP` 覆盖；控制台已开着时传 `--no-toggle`。

## uilook.py：屏幕模板匹配

纯 numpy + Pillow 的归一化互相关（FFT 加速），整屏 2560×1440 约 0.3 秒，
等价 OpenCV `TM_CCOEFF_NORMED`。

```bash
python tools/common/uilook.py shot shot.png                        # 截屏
python tools/common/uilook.py crop shot.png 700,200,80,80 tpl.png  # 裁模板
python tools/common/uilook.py find tpl.png --screen shot.png --threshold 0.9 --max 3
python tools/common/uilook.py find tpl.png --region 0,1300,2560,140 --scales 1.0,0.9,0.8
# -> {"ok":true,"matches":[{"x":700,"y":200,"w":80,"h":80,"cx":740,"cy":240,"score":1.0}]}
```

```python
from uilook import grab, crop, find_template
assert find_template("tpl_icon.png", screen=grab(), threshold=0.9), "图标没出现"
```

自测：从截图裁 80×80 再整屏找回 → score 1.0、0.294s；拿 mod 图标去原版物品栏找 → 0 命中（可当负例断言）。

**边界**：对缩放敏感（换分辨率/UI 缩放要重截模板或给 `--scales`）；
半透明/动态背景（草地）小模板易误命中 → 优先选 UI 面板、图标这类纯色背景元素；没有 OCR。

## gameinput.py：带焦点校验的输入

发输入前必须 `GetForegroundWindow() == 目标 hwnd`，不一致就抛错，**绝不盲发**
（不校验的后果：按键被游戏当快捷键吃掉，弹出各种面板污染测试状态）。

```bash
python tools/common/gameinput.py list                       # 列可见窗口（标题+类名都能匹配）
python tools/common/gameinput.py focus "Don't Starve"
python tools/common/gameinput.py text 'c_give("goldnugget")' --app "Don't Starve"
python tools/common/gameinput.py key grave --app "Don't Starve"
python tools/common/gameinput.py hold w 800 --app "Don't Starve"
```

- Unicode 走 `SendInput + KEYEVENTF_UNICODE`（`VkKeyScanW` 只能 ASCII），中文可打；
- 置前失败会 `AttachThreadInput` 借用前台线程输入队列再试，仍失败报错；
- 窗口匹配同时比对**类名**（中文系统标题是中文，命令行传参易被 GBK 破坏）；
- 控制台输出统一 UTF-8（否则 GBK 控制台打印中文会 `UnicodeEncodeError`）。

## ktex2png.py：解码 KTEX

```bash
python tools/common/ktex2png.py <file.tex> out.png
```

用途：核对编译产物（图标真的进 atlas 了吗、`anim/<x>.zip` 里的 `atlas-0.tex` 长什么样）。
注意 DST 图集是**上下翻转**存储，翻正后再比较。

---

## workshop.py：免 GUI 发布

替代官方 `ModUploader.exe` 的**更新**流程（首发仍用 GUI）。直接调 DST 自带
`bin64/steam_api64.dll` 的 `ISteamUGC`：`StartItemUpdate` → `SetItemTags` /
`SetItemContent` / `SetItemPreview` → `SubmitItemUpdate`。

```bash
python tools/common/workshop.py plan    --mod mods/wanda_planar_plan --item 3842009601
python tools/common/workshop.py publish --mod mods/wanda_planar_plan --item 3842009601 \
                                        --changenote "v0.4.2 — 骑牛可开关钟表袋"
python tools/common/workshop.py verify  --item 3842009601 --pages   # 双语页面核对
python tools/common/workshop.py dump    --mod mods/wanda_planar_plan --item 3842009601
python tools/common/workshop.py delete  --item <ID> --yes           # 自测条目清理
```

- 前置：**Steam 客户端已用发布账号登录**、游戏已关闭、64 位 Python；
- 标签：读条目**现有标签**，只换 mod 类型标记（`client_only_mod` 等）与
  `version:<modinfo.version>`，分类标签（`character` / `tweak` / `item` …）原样保留；
- **双语文案**：读 `docs/mods/<mod>/workshop/{en,zh}.txt`（第 1 行标题 / 第 2 行空 / 其余正文），
  逐语言提交；没有这两个文件就不碰标题与描述（`--no-copy` 也可强制跳过）；
- preflight：游戏进程、`preview.jpg`（268×268 JPG）、版本标签是否已递增、mod 目录杂草、
  中文文件里到底有没有中文；`--force` 可越过（不建议）；
- 结束后自动调 Steam Web API 回读；`--pages` 额外抽一次中英文社区页（公开条目）。

三条实测限制（Steam 侧，绕不过）：

1. 一次更新只认一个语言（`SetItemUpdateLanguage` 对随后的标题/描述生效，后一次覆盖前一次）
   → 双语 = 两次提交，内容/标签/预览图挂在第一次；
2. `changenote` 不分语言 → 第二次提交用 `--lang-changenote`（默认「（同步其他语言页面文案）」），
   传空串会留一条无正文记录；
3. `GetQueryUGCResult` 的描述字段只回前 256 字符 → `dump` 的中文正文取自
   `publishing.md` 的 bbcode 块，英文正文取自 Web API。

为什么不用 steamcmd：`workshop_build_item` 的 VDF 没有 `tags` 键（键名白名单见
`steamconsole64.dll`：`workshopitem / publishedfileid / title / description / visibility /
previewfile / contentfolder / kvtags / changenote`），而 DST 的「mod 过期」提示依赖
`version:x.y.z` 标签 → 只靠 steamcmd 刷不了版本。详见
[发布指南 §1.1](../../docs/mods/common/publishing.md)。

实测（2026-11-24，自测条目 3845096080，已删除）：steamcmd 写 `"tags" "client_only_mod,version:0.0.1"`
上传成功但 `tags: []`；本脚本同一伪造 mod 上传后 `tags: [client_only_mod, version:0.0.1]`，
把 modinfo 改到 0.0.2 再传后标签变 `version:0.0.2`，标题与描述两项全程未被覆盖。

---

## 组合用法

```python
from uilook import grab, find_template
from gameinput import send_command

send_command('c_give("wanda_haste_watch")', enter=True)   # 带焦点校验地发给游戏
assert find_template("tpl_slot.png", screen=grab(), threshold=0.9), "物品没进背包"
```

顺序永远是**先断言存在，再看外观**（见 [测试指南](../../docs/mods/common/testing.md)）。

> `dstconsole.py` / `dstlua.sh` 是从 `.scratch/` 的临时脚本整理而来（逻辑相同，改成 argparse +
> 自动探测日志路径）。语法已校验；整理后未再进游戏复测注入行为。
