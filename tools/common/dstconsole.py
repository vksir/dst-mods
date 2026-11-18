#!/usr/bin/env python
"""向饥荒联机版（DST）控制台注入一行 Lua —— 纯 PostMessage，不依赖窗口焦点。

为什么不用 gameinput.py：中文输入法会吞掉 ` 键；窗口被别的程序抢焦点时
SendInput 会打到别的窗口。PostMessage 直接投递到目标 hwnd，稳定得多。

用法：
    python tools/common/dstconsole.py 'print("[T] hi")'
    python tools/common/dstconsole.py 'c_give("goldnugget")' --app "Don't Starve Together"
    python tools/common/dstconsole.py '...' --no-toggle      # 控制台已经开着时

约定：
- ` 键是 **toggle**，所以调用前不知道控制台状态时会翻转。重试逻辑放在 dstlua.sh 里；
- 每条命令以回车提交，游戏把 print 输出写进 client_log.txt。
"""
import argparse
import ctypes
import sys
import time

WM_KEYDOWN, WM_KEYUP, WM_CHAR = 0x0100, 0x0101, 0x0102
VK_RETURN, VK_OEM_3 = 0x0D, 0xC0

_user32 = ctypes.WinDLL("user32", use_last_error=True)


def find_window(title="Don't Starve Together"):
    hwnd = _user32.FindWindowW(None, title)
    if not hwnd:
        raise SystemExit("找不到窗口：%s（游戏没开？）" % title)
    return hwnd


def _key(hwnd, vk, hold=0.06):
    scan = _user32.MapVirtualKeyW(vk, 0)
    _user32.PostMessageW(hwnd, WM_KEYDOWN, vk, 1 | (scan << 16))
    time.sleep(hold)
    _user32.PostMessageW(hwnd, WM_KEYUP, vk, 1 | (scan << 16) | (1 << 30) | (1 << 31))


def inject(lua, app="Don't Starve Together", toggle=True, submit=True, delay=1.0):
    """把一段 Lua 敲进控制台并回车。toggle=True 时先按 ` 开控制台。"""
    hwnd = find_window(app)
    if toggle:
        _key(hwnd, VK_OEM_3)          # ` 开关控制台
        time.sleep(delay)
    for ch in lua:
        _user32.PostMessageW(hwnd, WM_CHAR, ord(ch), 1)
        time.sleep(0.012)             # 太快会丢字符
    time.sleep(0.3)
    if submit:
        _key(hwnd, VK_RETURN)
        time.sleep(delay)
    return hwnd


def main(argv=None):
    ap = argparse.ArgumentParser(description="向 DST 控制台注入 Lua")
    ap.add_argument("lua", help="要执行的 Lua 源码（单行）")
    ap.add_argument("--app", default="Don't Starve Together", help="窗口标题")
    ap.add_argument("--no-toggle", action="store_true", help="控制台已打开：不再按 ` 键")
    ap.add_argument("--no-enter", action="store_true", help="只输入不提交（手动检查）")
    a = ap.parse_args(argv)
    inject(a.lua, app=a.app, toggle=not a.no_toggle, submit=not a.no_enter)
    print("sent(%d): %s" % (len(a.lua), a.lua[:60]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
