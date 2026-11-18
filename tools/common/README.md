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
