"""向 Windows 窗口发送键鼠输入，带"焦点确认"，避免按键打到别的窗口。

为什么需要它：agent-desktop 只能发组合键、且不保证目标窗口在前台；
游戏（自绘 UI、无无障碍节点）里打字必须走 Win32 SendInput，并且**发之前必须确认焦点**，
否则文字会被游戏当成快捷键吃掉（实测会弹出各种面板，污染测试状态）。

特性：
  - 按窗口标题关键词找窗口，置前并**验证** GetForegroundWindow() 真的是它
  - Unicode 文本输入（KEYEVENTF_UNICODE，中文也能打）
  - 按住某键 N 毫秒（走路/蓄力）
  - 焦点不对就报错退出，绝不盲发

命令行：
  python tools/gameinput.py list
  python tools/gameinput.py focus "Don't Starve"
  python tools/gameinput.py text "c_give(\"wanda_watch_bag\")" [--app 关键词] [--enter]
  python tools/gameinput.py key grave [--app ...]
  python tools/gameinput.py hold w 800 [--app ...]

库调用：
  from gameinput import find_window, focus, send_text
  hwnd, title = find_window("Don't Starve")
  focus(hwnd)
  send_text("c_give(\\"goldnugget\\")")
"""

import argparse
import ctypes
import sys
import time
from ctypes import wintypes

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

INPUT_KEYBOARD = 1
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
SW_RESTORE = 9
VK_RETURN = 0x0D

DEFAULT_APP = "Don't Starve Together"

KEY_ALIASES = {
    "grave": 0xC0, "`": 0xC0, "~": 0xC0,
    "enter": 0x0D, "return": 0x0D,
    "escape": 0x1B, "esc": 0x1B,
    "tab": 0x09, "space": 0x20, "backspace": 0x08,
    "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28,
    "home": 0x24, "end": 0x23, "delete": 0x2E,
    "ctrl": 0x11, "shift": 0x10, "alt": 0x12,
}


# ------------------------------------------------------------------ 结构体

class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wintypes.WORD),
                ("wScan", wintypes.WORD),
                ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD),
                ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong))]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG),
                ("mouseData", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong))]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [("uMsg", wintypes.DWORD), ("wParamL", wintypes.WORD),
                ("wParamH", wintypes.WORD)]


class _INPUTunion(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT), ("hi", HARDWAREINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("_u", _INPUTunion)]


user32.SendInput.argtypes = (wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int)
user32.SendInput.restype = wintypes.UINT


# ------------------------------------------------------------------ 窗口

def list_windows(keyword=None):
    """返回 [(hwnd, title)]，只包含可见窗口。"""
    found = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    def _cb(hwnd, _):
        if not user32.IsWindowVisible(hwnd):
            return True
        n = user32.GetWindowTextLengthW(hwnd)
        title = ""
        if n:
            buf = ctypes.create_unicode_buffer(n + 1)
            user32.GetWindowTextW(hwnd, buf, n + 1)
            title = buf.value
        # 同时匹配窗口类名：中文系统下标题全是中文，命令行传参容易被编码搞坏，
        # 而类名（如 "Notepad"）是 ASCII，稳定可传
        cbuf = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(hwnd, cbuf, 256)
        cls = cbuf.value
        hay = title + " " + cls
        if keyword is None or keyword.lower() in hay.lower():
            found.append((hwnd, title or cls))
        return True

    user32.EnumWindows(_cb, 0)
    return found


def find_window(keyword):
    wins = list_windows(keyword)
    if not wins:
        raise RuntimeError("找不到标题含 %r 的窗口" % keyword)
    # 优先精确包含度高的
    wins.sort(key=lambda w: len(w[1]))
    return wins[0]


def foreground():
    return user32.GetForegroundWindow()


def focus(hwnd, retries=10):
    """把窗口置前，并**验证**成功。失败抛异常（绝不盲发按键）。"""
    if user32.IsIconic(hwnd):
        user32.ShowWindow(hwnd, SW_RESTORE)
    user32.BringWindowToTop(hwnd)

    for _ in range(retries):
        if foreground() == hwnd:
            time.sleep(0.15)
            return True
        # 常见失败原因：调用线程不是前台线程，用 AttachThreadInput 借用输入队列
        fg = foreground()
        fg_tid = user32.GetWindowThreadProcessId(fg, None)
        my_tid = kernel32.GetCurrentThreadId()
        attached = False
        if fg_tid and fg_tid != my_tid:
            attached = bool(user32.AttachThreadInput(my_tid, fg_tid, True))
        try:
            user32.SetForegroundWindow(hwnd)
            user32.SetFocus(hwnd)
        finally:
            if attached:
                user32.AttachThreadInput(my_tid, fg_tid, False)
        time.sleep(0.12)

    raise RuntimeError("无法把窗口置前（前台仍是 hwnd=%s）" % foreground())


# ------------------------------------------------------------------ 发送

def _send(*inputs):
    n = len(inputs)
    arr = (INPUT * n)(*inputs)
    sent = user32.SendInput(n, arr, ctypes.sizeof(INPUT))
    if sent != n:
        raise RuntimeError("SendInput 只送出 %d/%d（err=%s）"
                           % (sent, n, ctypes.get_last_error()))


def _key_input(vk=0, scan=0, flags=0):
    ki = KEYBDINPUT(vk, scan, flags, 0, None)
    return INPUT(INPUT_KEYBOARD, _INPUTunion(ki=ki))


def key_down(vk):
    _send(_key_input(vk=vk))


def key_up(vk):
    _send(_key_input(vk=vk, flags=KEYEVENTF_KEYUP))


def tap_key(name):
    vk = resolve_vk(name)
    _send(_key_input(vk=vk), _key_input(vk=vk, flags=KEYEVENTF_KEYUP))


def resolve_vk(name):
    if name.lower() in KEY_ALIASES:
        return KEY_ALIASES[name.lower()]
    if len(name) == 1:
        r = user32.VkKeyScanW(ord(name)) & 0xFFFF
        if r == 0xFFFF:
            raise RuntimeError("无法解析按键 %r（非 ASCII 字符请用 text 命令）" % name)
        return r & 0xFF
    raise RuntimeError("未知按键 %r" % name)


def hold_key(name, ms):
    vk = resolve_vk(name)
    key_down(vk)
    time.sleep(ms / 1000.0)
    key_up(vk)


def send_text(text, enter=False, delay=0.02):
    """Unicode 文本输入：每个 UTF-16 code unit 一次 down/up。"""
    units = text.encode("utf-16-le")
    for i in range(0, len(units), 2):
        u = int.from_bytes(units[i:i + 2], "little")
        _send(_key_input(scan=u, flags=KEYEVENTF_UNICODE),
              _key_input(scan=u, flags=KEYEVENTF_UNICODE | KEYEVENTF_KEYUP))
        time.sleep(delay)
    if enter:
        tap_key("enter")


def send_command(text, app=None, enter=True):
    """置前 → 确认焦点 → 输入 → 可选回车。返回目标窗口标题。"""
    hwnd, title = find_window(app or DEFAULT_APP)
    focus(hwnd)
    if foreground() != hwnd:
        raise RuntimeError("焦点校验失败，拒绝发送（避免污染其它窗口）")
    send_text(text, enter=enter)
    return title


# ------------------------------------------------------------------ CLI

def main(argv=None):
    # 控制台是 GBK 时，输出中文/特殊字符会抛 UnicodeEncodeError，统一转 UTF-8
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="向窗口发送输入（带焦点确认）")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="列出可见窗口")

    p_focus = sub.add_parser("focus", help="置前某窗口")
    p_focus.add_argument("keyword", nargs="?", default=DEFAULT_APP)

    p_text = sub.add_parser("text", help="输入文本（Unicode）")
    p_text.add_argument("value")
    p_text.add_argument("--app", default=DEFAULT_APP)
    p_text.add_argument("--enter", action="store_true")

    p_key = sub.add_parser("key", help="敲一下某键")
    p_key.add_argument("name")
    p_key.add_argument("--app", default=DEFAULT_APP)

    p_hold = sub.add_parser("hold", help="按住某键 N 毫秒")
    p_hold.add_argument("name")
    p_hold.add_argument("ms", type=int)
    p_hold.add_argument("--app", default=DEFAULT_APP)

    args = ap.parse_args(argv)

    if args.cmd == "list":
        for hwnd, title in list_windows():
            print("%-12s %s" % (hwnd, title))
        return 0

    if args.cmd == "focus":
        hwnd, title = find_window(args.keyword)
        focus(hwnd)
        print("focused: %s" % title)
        return 0

    if args.cmd == "text":
        print("sent to: %s" % send_command(args.value, args.app, args.enter))
        return 0

    if args.cmd == "key":
        hwnd, title = find_window(args.app)
        focus(hwnd)
        tap_key(args.name)
        print("key %s -> %s" % (args.name, title))
        return 0

    if args.cmd == "hold":
        hwnd, title = find_window(args.app)
        focus(hwnd)
        hold_key(args.name, args.ms)
        print("hold %s %dms -> %s" % (args.name, args.ms, title))
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
