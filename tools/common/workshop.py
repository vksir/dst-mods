"""创意工坊发布器（免 GUI）：直接调 Steamworks 的 ISteamUGC，等价于官方 ModUploader。

为什么不用 steamcmd 发工坊：`workshop_build_item` 的 VDF 只认
`workshopitem / publishedfileid / title / description / visibility / previewfile /
contentfolder / kvtags / changenote`（`steamconsole64.dll` 里的键名就是这几个，没有 `tags`）。
DST 判断"mod 过期"靠工坊条目的 `version:x.y.z` 标签，steamcmd 改不了 → 必须走 ISteamUGC
（ModUploader 用的也是这条路，只是它只有 GUI）。

为什么不用 ModUploader：GUI，粘文案/选条目/点 Upload 全靠手，且只能写 english 槽位。

本脚本做的事：
  1. 读 modinfo.lua（name / version / client_only_mod / all_clients_require_mod / server_only_mod）；
  2. 读工坊条目**现有标签**（保留 character/tweak 这类分类标签，只换 mod 类型标记与 version）；
  3. 内容与标签：StartItemUpdate → SetItemTags → SetItemContent( mod 目录 )
     → SetItemPreview( preview.jpg ) → SubmitItemUpdate(changenote)；
  4. 双语文案（可选）：`docs/mods/<mod>/workshop/{en,zh}.txt`，
     每个语言一次提交（Steam 的更新句柄一次只认一个语言，
     `SetItemUpdateLanguage` 只对随后的 SetItemTitle/SetItemDescription 生效）；
  5. `dump`：把线上中英文案拉回本地（中文走社区页并逆推回 BBCode，
     因为 UGC 查询的描述字段只回前 256 字符）。

前置：Steam 客户端已登录发布账号、游戏已关闭、64 位 Python。
依赖 DST 自带的 `bin64/steam_api64.dll`（`--steam-api` 可覆盖）。

命令行：
  python tools/common/workshop.py plan    --mod mods/wanda_planar_plan --item 3842009601
  python tools/common/workshop.py publish --mod mods/wanda_planar_plan --item 3842009601 \\
                                          --changenote "v0.4.2 — 骑牛可开关钟表袋"
  python tools/common/workshop.py publish ... --dry-run          # 只打印计划，不提交
  python tools/common/workshop.py dump    --mod mods/wanda_planar_plan --item 3842009601
                                          # 以线上为准抓成 workshop/{en,zh}.txt
  python tools/common/workshop.py verify  --item 3842009601 [--pages]
  python tools/common/workshop.py delete  --item 3845096080 --yes  # 自测条目清理

标签规则（与 ModUploader 一致）：工坊标签 = mod 类型标记 + 分类标签 + `version:<modinfo.version>`；
`version:` 由 modinfo 决定，所以**每次上传前先把 modinfo.version +1**（见 docs/mods/common/publishing.md）。
"""

import argparse
import difflib
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# 控制台统一 UTF-8，否则 GBK 控制台打印中文会 UnicodeEncodeError / 乱码
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8")

DST_GAME_DIRS = (
    r"D:\SteamLibrary\steamapps\common\Don't Starve Together",
    r"C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together",
)

APPID = 322330
MOD_FLAG_TAGS = ("client_only_mod", "server_only_mod", "all_clients_require_mod")
# 文件名 → Steam 语言名（顺序即提交顺序，第一个随内容一起提交）
COPY_LANGS = (("en", "english"), ("zh", "schinese"))

_BROWSER_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
               "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")

# EItemUpdateStatus
ITEM_UPDATE_NAMES = {
    0: "invalid",
    1: "preparing_config",
    2: "preparing_content",
    3: "uploading_content",
    4: "uploading_preview",
    5: "committing",
}


# ---------------------------------------------------------------- 小工具

def find_steam_api(explicit=None):
    if explicit:
        return explicit
    env = os.environ.get("DST_STEAM_API")
    if env:
        return env
    for base in DST_GAME_DIRS:
        p = os.path.join(base, "bin64", "steam_api64.dll")
        if os.path.isfile(p):
            return p
    raise SystemExit("找不到 steam_api64.dll，用 --steam-api 指定")


def game_running():
    """返回正在运行的 dontstarve 进程名列表（上传前必须为空）。"""
    try:
        out = subprocess.run(["tasklist"], capture_output=True, text=True, timeout=30,
                             errors="ignore").stdout
    except Exception:
        return []
    return sorted({ln.split()[0] for ln in out.splitlines() if "dontstarve" in ln.lower()})


def parse_modinfo(path):
    """从 modinfo.lua 里抠出发布需要的字段（不做完整 Lua 求值）。"""
    text = open(path, encoding="utf-8-sig").read()
    text = re.sub(r"--[^\n]*", "", text)  # 去掉行注释，避免把注释里的示例当成值

    def scal(key, default=None):
        m = re.search(rf'^\s*{key}\s*=\s*(["\']?)([^"\'\n,]+)\1\s*$', text, re.M)
        return m.group(2).strip() if m else default

    def flag(key):
        m = re.search(rf'^\s*{key}\s*=\s*(true|false)\s*$', text, re.M | re.I)
        return bool(m and m.group(1).lower() == "true")

    return {
        "name": scal("name"),
        "version": scal("version"),
        "client_only_mod": flag("client_only_mod"),
        "server_only_mod": flag("server_only_mod"),
        "all_clients_require_mod": flag("all_clients_require_mod"),
    }


def web_item(item_id):
    """Web API 读条目公开信息（title / tags / description / time_updated）。

    这里的 description 是 **english 槽位**原文（含 BBCode）；其他语言槽位见 page_to_bbcode()。
    私密条目返回 result != 1。
    """
    data = urllib.parse.urlencode({"itemcount": 1, "publishedfileids[0]": item_id}).encode()
    req = urllib.request.Request(
        "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/", data=data
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.load(r)["response"]["publishedfiledetails"][0]
    except Exception as exc:
        return {"error": str(exc)}
    if d.get("result") != 1:
        return {"error": f"result={d.get('result')}", "visibility": d.get("visibility")}
    return {
        "title": d.get("title"),
        "tags": [t["tag"] for t in d.get("tags") or []],
        "description": d.get("description") or "",
        "visibility": d.get("visibility"),
        "time_updated": d.get("time_updated"),
        "file_size": d.get("file_size"),
        "result": 1,
    }


def community_page(item_id, lang):
    """抓社区页（`&l=<lang>`）的标题与纯文本描述，用于核对非 english 槽位。

    只在条目公开时可用；纯文本会丢 BBCode 结构，定稿请用 page_to_bbcode()。
    """
    try:
        title, frag = page_parts(item_id, lang)
    except Exception as exc:
        return {"error": str(exc)}
    if frag is None:
        return {"error": "页面里没有 workshopItemDescription（条目可能未公开）"}
    plain = re.sub(r"<br\s*/?>", "\n", frag)
    desc = html.unescape(re.sub(r"<[^>]+>", "", plain))
    return {"title": title, "description": desc.strip()}


def page_parts(item_id, lang):
    """返回 (标题, 描述 HTML 片段)；找不到描述时 frag 为 None。"""
    url = f"https://steamcommunity.com/sharedfiles/filedetails/?id={item_id}&l={lang}"
    req = urllib.request.Request(url, headers={"User-Agent": _BROWSER_UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        page = r.read().decode("utf-8", "ignore")
    tm = re.search(r'<div class="workshopItemTitle">(.*?)</div>', page, re.S)
    title = html.unescape(tm.group(1)).strip() if tm else ""
    start = page.find('<div class="workshopItemDescription"')
    if start < 0:
        return title, None
    # 按 div 嵌套扫到闭合，避免被内容里的 </div> 截断
    depth, i, end = 0, start, None
    tag_re = re.compile(r"<(/?)div\b[^>]*>", re.I)
    while True:
        m = tag_re.search(page, i)
        if not m:
            break
        if m.group(1):
            depth -= 1
            if depth == 0:
                end = m.start()
                break
        else:
            depth += 1
        i = m.end()
    if end is None:
        return title, None
    frag = re.sub(r"^<div[^>]*>", "", page[start:end])
    return title, frag


def html_to_bbcode(fragment):
    """把 Steam 渲染后的工坊描述 HTML 还原成 BBCode（工坊实际用到的子集）。"""
    s = fragment
    s = re.sub(r'<ul[^>]*class="bb_ul"[^>]*>', "[list]", s, flags=re.I)
    s = re.sub(r"</ul>", "[/list]", s, flags=re.I)
    s = re.sub(r"<li[^>]*>", "[*]", s, flags=re.I)
    s = re.sub(r"</li>", "", s, flags=re.I)
    for lvl in (1, 2, 3):
        s = re.sub(rf'<div[^>]*class="bb_h{lvl}"[^>]*>(.*?)</div>',
                   rf"[h{lvl}]\1[/h{lvl}]", s, flags=re.I | re.S)
    s = re.sub(r'<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>', r"[url=\1]\2[/url]", s, flags=re.I | re.S)
    s = re.sub(r'<img[^>]*src="([^"]+)"[^>]*>', r"[img]\1[/img]", s, flags=re.I)
    s = re.sub(r"<blockquote[^>]*>", "[quote]", s, flags=re.I)
    s = re.sub(r"</blockquote>", "[/quote]", s, flags=re.I)
    s = re.sub(r"<code[^>]*>", "[code]", s, flags=re.I)
    s = re.sub(r"</code>", "[/code]", s, flags=re.I)
    s = re.sub(r'<span[^>]*class="bb_spoiler"[^>]*>', "[spoiler]", s, flags=re.I)
    s = re.sub(r"</span>", "[/spoiler]", s, flags=re.I)
    for tag, bb in (("b", "b"), ("strong", "b"), ("i", "i"), ("em", "i"),
                    ("u", "u"), ("strike", "strike"), ("del", "strike")):
        s = re.sub(rf"<{tag}\b[^>]*>", f"[{bb}]", s, flags=re.I)
        s = re.sub(rf"</{tag}>", f"[/{bb}]", s, flags=re.I)
    s = re.sub(r"<hr\s*/?>", "[hr][/hr]", s, flags=re.I)
    s = re.sub(r"<br\s*/?>", "\n", s, flags=re.I)
    s = re.sub(r"</?div[^>]*>", "", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    s = s.replace("\r\n", "\n")
    # 原文本里的换行会被 Steam 吞掉（块级标签之间），这里按 BBCode 习惯补回来，方便下次直提
    for lvl in (1, 2, 3):
        s = re.sub(rf"\[/h{lvl}\](?!\n)", f"[/h{lvl}]\n", s)
        s = re.sub(rf"(?<!\n)\[h{lvl}\]", f"\n[h{lvl}]", s)
    s = re.sub(r"(?<!\n)\[list\]", "\n[list]", s)
    s = re.sub(r"\[/list\](?!\n)", "[/list]\n", s)
    s = re.sub(r"(?<!\n)\[\*\]", "\n[*]", s)
    s = re.sub(r"(?<!\n)\[hr\]\[/hr\]", "\n[hr][/hr]", s)
    s = re.sub(r"\[list\]\n\n", "[list]\n", s)
    s = re.sub(r"[ \t]+\n", "\n", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()


def page_to_bbcode(item_id, lang):
    """社区页 → (标题, BBCode 正文)：把线上文案无损留档的唯一路径。

    UGC 查询的描述字段只回前 256 字符，所以中文槽位只能这样读。
    """
    title, frag = page_parts(item_id, lang)
    if frag is None:
        raise SystemExit("社区页里没有描述区块（条目可能未公开）")
    return title, html_to_bbcode(frag)


# ---------------------------------------------------------------- 双语文案文件

def copy_dir_for(mod_dir):
    """`docs/mods/<mod>/workshop`（不存在就当作没有文案文件）。"""
    return os.path.join(REPO, "docs", "mods", os.path.basename(os.path.normpath(mod_dir)),
                        "workshop")


def read_copy_file(path):
    """格式：第 1 行标题；第 2 行留空；其余是正文（保留原换行）。"""
    raw = open(path, encoding="utf-8").read().replace("\r\n", "\n")
    lines = raw.split("\n")
    title = lines[0].strip()
    body = "\n".join(lines[1:])
    if body.startswith("\n"):
        body = body[1:]
    return {"title": title, "description": body.rstrip("\n")}


def write_copy_file(path, title, description):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(title.strip() + "\n\n" + description.rstrip("\n") + "\n")


def load_copy(dirpath):
    out = {}
    for key, lang in COPY_LANGS:
        p = os.path.join(dirpath, f"{key}.txt")
        if os.path.isfile(p):
            out[key] = dict(read_copy_file(p), lang=lang, path=p)
    return out


# ---------------------------------------------------------------- Steamworks

class SteamUGC:
    """把 steam_api64.dll 的 flat API 包成好用的对象。"""

    def __init__(self, dll_path):
        import ctypes as C

        if C.sizeof(C.c_void_p) != 8:
            raise SystemExit("需要 64 位 Python（steam_api64.dll 是 64 位）")
        self.C = C
        self.dll = C.CDLL(dll_path)
        d = self.dll

        class SteamParamStringArray_t(C.Structure):
            _fields_ = [("m_ppStrings", C.POINTER(C.c_char_p)), ("m_nNumStrings", C.c_int32)]

        self.ParamArray = SteamParamStringArray_t

        d.SteamAPI_Init.restype = C.c_bool
        d.SteamAPI_Shutdown.restype = None
        d.SteamAPI_RunCallbacks.restype = None
        d.SteamAPI_SteamUGC_v015.restype = C.c_void_p

        def sig(name, args, restype):
            f = getattr(d, name)
            f.argtypes = args
            f.restype = restype
            return f

        vp, u32, u64, cp, bool_ = C.c_void_p, C.c_uint32, C.c_uint64, C.c_char_p, C.c_bool
        self.f_create_query = sig(
            "SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest", [vp, C.POINTER(u64), u32], u64)
        self.f_send_query = sig("SteamAPI_ISteamUGC_SendQueryUGCRequest", [vp, u64], u64)
        self.f_release_query = sig("SteamAPI_ISteamUGC_ReleaseQueryUGCRequest", [vp, u64], bool_)
        self.f_query_result = sig(
            "SteamAPI_ISteamUGC_GetQueryUGCResult", [vp, u64, u32, C.c_void_p], bool_)
        self.f_query_num_tags = sig("SteamAPI_ISteamUGC_GetQueryUGCNumTags", [vp, u64, u32], u32)
        self.f_query_tag = sig(
            "SteamAPI_ISteamUGC_GetQueryUGCTag", [vp, u64, u32, u32, cp, u32], bool_)

        self.f_start_update = sig("SteamAPI_ISteamUGC_StartItemUpdate", [vp, u32, u64], u64)
        self.f_set_update_lang = sig("SteamAPI_ISteamUGC_SetItemUpdateLanguage", [vp, u64, cp], bool_)
        self.f_set_title = sig("SteamAPI_ISteamUGC_SetItemTitle", [vp, u64, cp], bool_)
        self.f_set_desc = sig("SteamAPI_ISteamUGC_SetItemDescription", [vp, u64, cp], bool_)
        self.f_set_tags = sig(
            "SteamAPI_ISteamUGC_SetItemTags", [vp, u64, C.POINTER(SteamParamStringArray_t)], bool_)
        self.f_set_content = sig("SteamAPI_ISteamUGC_SetItemContent", [vp, u64, cp], bool_)
        self.f_set_preview = sig("SteamAPI_ISteamUGC_SetItemPreview", [vp, u64, cp], bool_)
        self.f_submit = sig("SteamAPI_ISteamUGC_SubmitItemUpdate", [vp, u64, cp], u64)
        self.f_progress = sig(
            "SteamAPI_ISteamUGC_GetItemUpdateProgress",
            [vp, u64, C.POINTER(u64), C.POINTER(u64)], C.c_int)
        self.f_delete = sig("SteamAPI_ISteamUGC_DeleteItem", [vp, u64], u64)

        self.ugc = None

    def init(self):
        os.environ["SteamAppId"] = str(APPID)
        os.environ["SteamGameId"] = str(APPID)
        if not self.dll.SteamAPI_Init():
            raise SystemExit("SteamAPI_Init 失败：需要 Steam 客户端已登录（发布账号）、且游戏已关闭")
        self.ugc = self.dll.SteamAPI_SteamUGC_v015()
        if not self.ugc:
            raise SystemExit("拿不到 ISteamUGC 接口")
        return self

    def shutdown(self):
        try:
            self.dll.SteamAPI_Shutdown()
        except Exception:
            pass

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            self.dll.SteamAPI_RunCallbacks()
            time.sleep(0.05)

    # ---- 读条目

    def _query(self, item_id):
        C = self.C
        handle = self.f_create_query(self.ugc, C.byref(C.c_uint64(item_id)), 1)
        if not handle:
            raise SystemExit("CreateQueryUGCDetailsRequest 失败")
        if not self.f_send_query(self.ugc, handle):
            raise SystemExit("SendQueryUGCRequest 失败")
        buf = C.create_string_buffer(16384)
        # SteamUGCDetails_t: id@0 eResult@8 eFileType@12 creatorApp@16 consumerApp@20
        #                    title@24(129) description@153(8000，实际只回前 256 字符)
        for _ in range(200):
            self.dll.SteamAPI_RunCallbacks()
            time.sleep(0.05)
            if self.f_query_result(self.ugc, handle, 0, buf) and buf.raw[24:25] not in (b"", b"\0"):
                break
        raw = buf.raw
        title = raw[24:raw.find(b"\0", 24)].decode("utf-8", "replace")
        dstart = 153
        dend = raw.find(b"\0", dstart)
        if dend < 0:
            dend = dstart + 8000
        description = raw[dstart:dend].decode("utf-8", "replace")
        tags = []
        for i in range(self.f_query_num_tags(self.ugc, handle, 0)):
            tbuf = C.create_string_buffer(1024)
            if self.f_query_tag(self.ugc, handle, 0, i, tbuf, 1024):
                tags.append(tbuf.value.decode("utf-8"))
        self.f_release_query(self.ugc, handle)
        return {"title": title, "description": description, "tags": tags}

    def read_tags(self, item_id):
        return self._query(item_id)["tags"]

    # ---- 提交（一次提交只认一种语言）

    def submit_once(self, item_id, *, lang=None, title=None, description=None, tags=None,
                    content=None, preview=None, changenote=None, log=print):
        C = self.C
        handle = self.f_start_update(self.ugc, APPID, item_id)
        if handle == 0xFFFFFFFFFFFFFFFF:
            raise SystemExit("StartItemUpdate 失败：条目 id 不对或不属于当前账号")

        ok = True
        if lang:
            ok &= self.f_set_update_lang(self.ugc, handle, lang.encode())
        if title is not None:
            ok &= self.f_set_title(self.ugc, handle, title.encode("utf-8"))
        if description is not None:
            ok &= self.f_set_desc(self.ugc, handle, description.encode("utf-8"))
        if tags is not None:
            bufs = [t.encode("utf-8") for t in tags]
            arr = (C.c_char_p * len(bufs))(*bufs)
            param = self.ParamArray(arr, len(bufs))
            ok &= self.f_set_tags(self.ugc, handle, C.byref(param))
            self._keep = (arr, param, bufs)  # 活到 Submit 之后
        if content:
            ok &= self.f_set_content(self.ugc, handle, str(content).encode("utf-8"))
        if preview:
            ok &= self.f_set_preview(self.ugc, handle, str(preview).encode("utf-8"))
        if not ok:
            raise SystemExit("设置更新项失败（参数被拒）")

        call = self.f_submit(self.ugc, handle, (changenote or "").encode("utf-8"))
        if not call:
            raise SystemExit("SubmitItemUpdate 失败")

        processed, total = C.c_uint64(0), C.c_uint64(0)
        last = None
        activity = False
        # 纯文案/标签的提交可能瞬间完成、抓不到非 0 进度 → 没看到活动就按“快速完成”处理
        quiet_until = time.time() + 15
        deadline = time.time() + 900
        while time.time() < deadline:
            self.dll.SteamAPI_RunCallbacks()
            status = self.f_progress(self.ugc, handle, C.byref(processed), C.byref(total))
            if status != last:
                log(f"  [{ITEM_UPDATE_NAMES.get(status, status)}] {processed.value}/{total.value}")
                last = status
            if status != 0:
                activity = True
                quiet_until = time.time() + 900
            elif activity:
                break
            elif time.time() > quiet_until:
                log("  [快速提交] 没抓到进度回调")
                break
            time.sleep(0.2)
        else:
            raise SystemExit("上传超时（15 分钟）")

        # 进度回调走完不等于成功（实测可能是 "Timeout uploading manifest"），
        # 真正的结论由 cmd_publish 回读线上标签/文案来判定。
        return True

    def delete(self, item_id):
        if not self.f_delete(self.ugc, item_id):
            raise SystemExit("DeleteItem 失败")
        self.pump(3)
        return True


# ---------------------------------------------------------------- 计划 / 校验

def build_plan(args):
    mod_dir = os.path.abspath(args.mod)
    modinfo_path = os.path.join(mod_dir, "modinfo.lua")
    if not os.path.isfile(modinfo_path):
        raise SystemExit(f"{modinfo_path} 不存在")
    info = parse_modinfo(modinfo_path)
    if not info["version"]:
        raise SystemExit("modinfo.lua 里没有 version")

    # 现有标签：Steamworks 直读（私密条目也行），失败再退回 Web API
    current, source = [], None
    try:
        ugc = SteamUGC(find_steam_api(args.steam_api)).init()
        try:
            current = ugc.read_tags(args.item)
            source = "steamworks"
        finally:
            ugc.shutdown()
    except SystemExit:
        raise
    except Exception as exc:
        print(f"[warn] Steamworks 读标签失败（{exc}），改用 Web API", file=sys.stderr)
    if not current:
        w = web_item(args.item)
        if w.get("tags"):
            current, source = w["tags"], "webapi"

    flags = [t for t in MOD_FLAG_TAGS if info.get(t)]
    extra = [t for t in current if t not in MOD_FLAG_TAGS and not t.startswith("version:")]
    version_tag = f"version:{info['version']}"
    old_version = next((t for t in current if t.startswith("version:")), None)
    tags = list(dict.fromkeys(flags + extra + [version_tag]))

    preview = os.path.join(mod_dir, "preview.jpg")
    copy = load_copy(args.copy_dir or copy_dir_for(mod_dir))

    warnings = []
    procs = game_running()
    if procs:
        warnings.append(f"游戏进程还在跑：{', '.join(procs)} → 先关游戏")
    if not os.path.isfile(preview):
        warnings.append("mod 目录里没有 preview.jpg（工坊预览图会缺）")
    else:
        try:
            from PIL import Image

            with Image.open(preview) as im:
                if im.size != (268, 268):
                    warnings.append(f"preview.jpg 是 {im.size[0]}×{im.size[1]}，约定 268×268")
                if im.format != "JPEG":
                    warnings.append(f"preview.jpg 实际是 {im.format}，要 JPG")
        except ImportError:
            pass
    if old_version == version_tag:
        warnings.append(f"版本标签没变化（{version_tag}）→ 玩家端不会看到新版本，先递增 modinfo.version")
    for name in sorted(os.listdir(mod_dir)):
        if name.startswith(".") or name in ("README.md", "preview.png"):
            warnings.append(f"mod 目录里有不该上传的东西：{name}")
    for key, cfg in copy.items():
        if not cfg["description"].strip():
            warnings.append(f"{cfg['path']} 正文是空的")
        if key == "zh" and not re.search(r"[\u4e00-\u9fff]", cfg["description"]):
            warnings.append(f"{cfg['path']} 里没有中文，确认文件放对了？")

    return {
        "mod": mod_dir,
        "item": args.item,
        "modinfo": info,
        "current_tags": current,
        "current_tags_source": source,
        "new_tags": tags,
        "preview": preview if os.path.isfile(preview) else None,
        "copy": {k: {"path": v["path"], "lang": v["lang"], "title": v["title"],
                     "description_chars": len(v["description"])} for k, v in copy.items()},
        "warnings": warnings,
        "web": web_item(args.item),
    }


def cmd_plan(args):
    plan = build_plan(args)
    if args.brief:
        plan.pop("web", None)
    print(json.dumps(plan, ensure_ascii=False, indent=2))
    return 0


def normalize_bbcode(text):
    """抹平「社区页 ↔ 原文」的无关差异，用于比对线上文案与本地文件。

    Steam 会把裸链接渲染成 <a>，逆推后多一层 `[url=…linkfilter…]…[/url]`；
    行尾空格、多余空行也算噪声。
    """
    s = (text or "").replace("\r\n", "\n")
    s = re.sub(r"\[url=[^\]]*\]((?:https?://)\S+?)\[/url\]", r"\1", s)
    s = re.sub(r"[ \t]+$", "", s, flags=re.M)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()


def cmd_verify(args):
    out = {"web_api_english": web_item(args.item)}
    if args.pages:
        out["community_page"] = {lang: community_page(args.item, lang) for _, lang in COPY_LANGS}

    if args.text:
        # 逐语言比对「线上 vs 本地文件」：en 走 Web API，zh 走社区页（会被渲染，需归一化）
        mod_dir = os.path.abspath(args.text)
        copy = load_copy(args.copy_dir or copy_dir_for(mod_dir))
        checks = {}
        for key, cfg in copy.items():
            try:
                if key == "en":
                    live_title = web_item(args.item).get("title") or ""
                    live_desc = web_item(args.item).get("description") or ""
                else:
                    live_title, live_desc = page_to_bbcode(args.item, cfg["lang"])
            except Exception as exc:
                checks[key] = {"error": str(exc)}
                continue
            a = [l for l in normalize_bbcode(cfg["description"]).split("\n") if l.strip()]
            b = [l for l in normalize_bbcode(live_desc).split("\n") if l.strip()]
            diff = [l for l in difflib.unified_diff(a, b, "本地", "线上", lineterm="", n=0)]
            checks[key] = {
                "title_matches": live_title.strip() == cfg["title"].strip(),
                "live_title": live_title,
                "local_title": cfg["title"],
                "text_matches": a == b,
                "local_chars": len(cfg["description"]),
                "live_chars": len(live_desc),
                "diff": diff[:20],
            }
        out["copy_check"] = checks

    print(json.dumps(out, ensure_ascii=False, indent=2))
    ok = all(c.get("text_matches") and c.get("title_matches")
             for c in out.get("copy_check", {}).values()) if out.get("copy_check") else True
    return 0 if ok else 1


def cmd_dump(args):
    """把线上文案拉回本地（以线上为准留档）。

    en.txt：Web API 的 english 槽位原文（含 BBCode，完整）。
    zh.txt：社区页 `&l=schinese` → 逆推回 BBCode（UGC 查询只回前 256 字符，靠不住）。
            社区页 429 时可以 `--from-ugc` 兜底，但内容会被截断并告警。
    """
    mod_dir = os.path.abspath(args.mod)
    out_dir = args.copy_dir or copy_dir_for(mod_dir)
    wrote = {}

    web = web_item(args.item)
    en_title, en_desc = web.get("title") or "", web.get("description") or ""
    if args.from_page:
        en_title, en_desc = page_to_bbcode(args.item, "english")
    if en_title:
        p = os.path.join(out_dir, "en.txt")
        write_copy_file(p, en_title, en_desc)
        wrote["en"] = {"path": p, "chars": len(en_desc)}

    zh_title, zh_desc, zh_src = "", "", None
    if args.from_ugc:
        ugc = SteamUGC(find_steam_api(args.steam_api)).init()
        try:
            got = ugc._query(args.item)
        finally:
            ugc.shutdown()
        zh_title, zh_desc, zh_src = got["title"], got["description"], "ugc"
        if len(zh_desc) >= 250:
            print("[warn] UGC 描述可能被截断（≤256 字符），建议去掉 --from-ugc 走社区页",
                  file=sys.stderr)
    else:
        zh_title, zh_desc = page_to_bbcode(args.item, "schinese")
        zh_src = "community-page"
    if zh_title:
        p = os.path.join(out_dir, "zh.txt")
        write_copy_file(p, zh_title, zh_desc)
        wrote["zh"] = {"path": p, "chars": len(zh_desc), "source": zh_src}

    print(json.dumps({"out_dir": out_dir, "wrote": wrote}, ensure_ascii=False, indent=2))
    return 0


def cmd_publish(args):
    plan = build_plan(args)
    if args.copy_only:
        # 只改文案：内容与标签不动，所以「版本没递增」不再算问题
        plan["warnings"] = [w for w in plan["warnings"] if not w.startswith("版本标签没变化")]
    print(json.dumps({k: plan[k] for k in ("mod", "item", "new_tags", "copy", "warnings")},
                     ensure_ascii=False, indent=2))
    if plan["warnings"] and not args.force:
        for w in plan["warnings"]:
            print(f"[blocked] {w}", file=sys.stderr)
        raise SystemExit("有前置问题，修好或加 --force")
    if not args.changenote:
        raise SystemExit("必须给 --changenote（工坊「改动说明」不能留空）")

    copy = load_copy(args.copy_dir or copy_dir_for(plan["mod"]))
    if args.no_copy:
        copy = {}
    if args.langs:
        keep = [s.strip() for s in args.langs.split(",") if s.strip()]
        unknown = [k for k in keep if k not in dict(COPY_LANGS)]
        if unknown:
            raise SystemExit(f"--langs 只认 {', '.join(k for k, _ in COPY_LANGS)}，多了：{unknown}")
        copy = {k: v for k, v in copy.items() if k in keep}
    if args.copy_only and not copy:
        raise SystemExit("--copy-only 需要 docs/mods/<mod>/workshop/{en,zh}.txt（或 --copy-dir）")

    if args.dry_run:
        print("[dry-run] 不提交。将要发送：")
        print(json.dumps({
            "content": None if args.copy_only else plan["mod"],
            "preview": None if args.copy_only else plan["preview"],
            "tags": None if args.copy_only else plan["new_tags"],
            "changenote": args.changenote,
            "languages": [
                {"lang": cfg["lang"], "title": cfg["title"],
                 "description_chars": len(cfg["description"]),
                 "changenote": args.changenote if i == 0 else args.lang_changenote}
                for i, (_, cfg) in enumerate(copy.items())
            ] or [{"lang": None, "note": "不动标题与描述"}],
        }, ensure_ascii=False, indent=2))
        return 0

    ugc = SteamUGC(find_steam_api(args.steam_api)).init()
    try:
        items = list(copy.items())
        if not items:
            # 不改文案：一次提交，只更内容 + 标签
            ugc.submit_once(args.item, tags=plan["new_tags"], content=plan["mod"],
                            preview=plan["preview"], changenote=args.changenote)
        else:
            for i, (_, cfg) in enumerate(items):
                note = args.changenote if i == 0 else args.lang_changenote
                first = i == 0
                print(f"[{cfg['lang']}] {cfg['title']}")
                ugc.submit_once(
                    args.item,
                    lang=cfg["lang"],
                    title=cfg["title"],
                    description=cfg["description"],
                    # 只改文案时不动内容/标签/预览图
                    tags=None if args.copy_only else (plan["new_tags"] if first else None),
                    content=None if args.copy_only else (plan["mod"] if first else None),
                    preview=None if args.copy_only else (plan["preview"] if first else None),
                    changenote=note,
                )
    finally:
        ugc.shutdown()

    if args.copy_only:
        # 只改文案：核对 english 槽位与本地文件一致（中文槽位需人工看社区页）
        want = copy.get("en", {}).get("description")
        got_desc, ok = None, not want
        for attempt in range(20):
            time.sleep(6)
            got_desc = (web_item(args.item).get("description") or "")
            if not want or got_desc.replace("\r\n", "\n").strip() == want.strip():
                ok = True
                break
            print(f"  [等待落库 {attempt + 1}/20] english 槽位还差一点…")
        out = {"mode": "copy-only", "english_matches_local": ok,
               "web_api_english": web_item(args.item)}
        if args.pages:
            out["community_page"] = {lang: community_page(args.item, lang) for _, lang in COPY_LANGS}
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0 if ok else 1

    # 回读校验：工坊侧落库有延迟（实测 1~2 分钟），盯 tags 是否变成预期值
    expected = plan["new_tags"]
    got, ok = None, False
    verified = SteamUGC(find_steam_api(args.steam_api)).init()
    try:
        for attempt in range(30):
            time.sleep(6)
            got = verified._query(args.item)["tags"]
            if got == expected:
                ok = True
                break
            print(f"  [等待落库 {attempt + 1}/30] tags={got}")
    finally:
        verified.shutdown()
    if not ok:
        raise SystemExit(
            f"上传后标签没变成预期值：期望 {expected}，实际 {got}" + chr(10) +
            "常见原因：游戏客户端在跑（会抢上传带宽导致 manifest 超时，看 "
            "Steam/logs/workshop_log.txt 里的 'Timeout uploading manifest'）、Steam 限流，重试即可")

    out = {"verified_tags": got, "web_api_english": web_item(args.item)}
    if args.pages:
        out["community_page"] = {lang: community_page(args.item, lang) for _, lang in COPY_LANGS}
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def cmd_delete(args):
    if not args.yes:
        raise SystemExit("删除条目要加 --yes")
    ugc = SteamUGC(find_steam_api(args.steam_api)).init()
    try:
        ugc.delete(args.item)
    finally:
        ugc.shutdown()
    time.sleep(3)
    print(json.dumps(web_item(args.item), ensure_ascii=False, indent=2))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description="DST 创意工坊发布器（ISteamUGC，免 GUI）")
    p.add_argument("--steam-api", help="steam_api64.dll 路径（默认用 DST bin64 里的）")
    sub = p.add_subparsers(dest="cmd", required=True)

    def mod_args(sp):
        sp.add_argument("--mod", required=True, help="mod 目录，例如 mods/wanda_planar_plan")
        sp.add_argument("--item", required=True, type=int, help="工坊条目 id")
        sp.add_argument("--copy-dir", help="双语文案目录（默认 docs/mods/<mod>/workshop）")

    sp = sub.add_parser("plan", help="只打印将要发生什么")
    mod_args(sp)
    sp.add_argument("--brief", action="store_true", help="不打印 Web API 回读")
    sp.set_defaults(func=cmd_plan)

    sp = sub.add_parser("publish", help="上传内容 + 刷新标签 + 同步双语文案")
    mod_args(sp)
    sp.add_argument("--changenote", help="改动说明（工坊里显示，不能留空）")
    sp.add_argument("--lang-changenote", default="（同步其他语言页面文案）",
                    help="第二种语言那次提交用的改动说明（Steam 的 changenote 不分语言，"
                         "两次提交会各留一条）")
    sp.add_argument("--no-copy", action="store_true", help="本次不碰标题与描述")
    sp.add_argument("--copy-only", action="store_true",
                    help="只同步标题与描述（不动内容/标签/预览图，也不要求升版本）")
    sp.add_argument("--langs", help="只提交指定语言，例如 zh 或 en,zh（默认全部）")
    sp.add_argument("--force", action="store_true", help="忽略 preflight 警告")
    sp.add_argument("--dry-run", action="store_true", help="只打印计划")
    sp.add_argument("--pages", action="store_true", help="提交后用社区页核对双语文案")
    sp.set_defaults(func=cmd_publish)

    sp = sub.add_parser("dump", help="把线上中英文案拉成 workshop/{en,zh}.txt")
    mod_args(sp)
    sp.add_argument("--from-page", action="store_true",
                    help="英文也走社区页（默认走 Web API，更完整）")
    sp.add_argument("--from-ugc", action="store_true",
                    help="中文改走 UGC 查询（没有社区页时兜底，但描述会被截断到 256 字符）")
    sp.set_defaults(func=cmd_dump)

    sp = sub.add_parser("verify", help="Web API / 社区页 核对条目")
    sp.add_argument("--item", required=True, type=int)
    sp.add_argument("--pages", action="store_true", help="同时核对中英文社区页")
    sp.add_argument("--text", metavar="MOD_DIR",
                    help="逐语言比对线上文案与本地 workshop/*.txt（en 走 Web API，zh 走社区页）")
    sp.add_argument("--copy-dir", help="双语文案目录（默认 docs/mods/<mod>/workshop）")
    sp.set_defaults(func=cmd_verify)

    sp = sub.add_parser("delete", help="删除条目（自测清理用）")
    sp.add_argument("--item", required=True, type=int)
    sp.add_argument("--yes", action="store_true")
    sp.set_defaults(func=cmd_delete)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
