# Save Equipment Slots (Fix) · 测试指南

> 通用要求（报告位置、内嵌图片、只写验证过的结论、测试分层）见
> [`../common/testing.md`](../common/testing.md)。本文列这个 mod 的**验证场景**与坑。

## 1. 这个 mod 难测在哪

- 它是 **client-only mod**：很多行为只在"纯客户端连服务器"时才出现，单人开世界测不出来；
- 关键路径跨 **shard**（地表 ↔ 洞穴两个进程），配置丢失类 bug 必须真的上下洞穴；
- 图标问题依赖 **运行时长/装了多少 mod**（`net_hash` 驻留表溢出、图标未注册 atlas），
  需要接近真实的重 mod 环境；
- 皮肤图标依赖 `inventoryitem.imagename` 的**延迟同步**，快照太早会读到基础图标。

## 2. 验证矩阵

| # | 场景 | 步骤 | 期望 |
|---|---|---|---|
| S1 | 下洞穴 | 配好槽位 → 下洞穴 → 回地表 | 配置仍在 |
| S2 | 重登（自开世界） | 配好 → 退出 → 重进 | 配置仍在（世界存档） |
| S3 | 纯客户端 + 重登 | 连服务器 → 配好 → 退出重连 | 配置仍在（本机文件） |
| S4 | 换电脑 | 拷存档不拷 `client_save` | 配置丢失（**预期行为**） |
| S5 | 槽位图标（无皮肤） | 重登后看装备槽 | 不是方块 |
| S6 | 槽位图标（皮肤） | 带皮肤装备记忆 → 重登 → 物品不在身上 | 显示皮肤图标，不是基础图标 |
| S7 | 图标清除 | 点槽位上方小图标 | 该格记忆清除，图标消失 |
| S8 | 暂停快捷键 | Ctrl + V | 记忆暂停，出现状态提示；再按恢复 |
| S9 | 应用类型 | 切成"装备+食物" | 食物进入记忆范围，其它物品不记忆 |
| S10 | 同装崩溃 | 与"漫漫长路"这类 mod 同装 → 装备回位 | 不崩，槽位占位被清理 |
| S11 | 服务端 mod 物品 | 订阅一个 `all_clients_require_mod` 的物品 mod | 槽位图标正常（不是空白/方块） |
| S12 | 开关跨 shard | Ctrl + V 关闭 → 下洞穴 → 回地表 | 文件仍为 `disable_save_slots:false`；
  进洞穴后按一次 Ctrl + V 显示 ON（说明恢复的是 OFF）；回地表同理 |
| S13 | 开关跨重登 | Ctrl + V 关闭 → 退出到主菜单/重启 → 重进 | 仍为关闭（文件里有 `disable_save_slots:false`；
  重进后按一次 Ctrl + V 显示 ON 即证此前是 OFF） |
| S14 | 开关写盘时机 | 切到关闭后立即看文件（不等拾取物品） | 文件已含 `disable_save_slots:false`（读盘完成后切换即落盘；
  若在刚进世界的一瞬间切换，写盘会挂起到读回后） |
| S15 | 旧版文件兼容 | 删掉文件里的 `disable_save_slots` 字段 → 重进 | 用配置「初始开关状态」，首次 Flush 后补字段 |
| S16 | 快捷键设为「无」 | 快捷键选「无」→ 重进已有文件的服务器 | 不读持久化开关，始终可保存（文件旧值不生效） |

## 3. 断言手法

- **配置持久化**：直接读本机文件
  `文档/Klei/DoNotStarveTogether/<KleiID>/client_save/ses_fix_slots_<服务器名>`
  （JSON），比看 UI 可靠；开关状态看 `disable_save_slots` 字段，槽位看 `items`；
- **图标状态**：日志里搜 `atlas=nil`、`Invalid resource handle for atlas 'FROMNUM'`、
  `[SES-FIX]` 诊断行——出现即说明走到了 fallback/错误路径；
- **皮肤图标**：先在活体上确认 `components.inventoryitem.imagename` 是皮肤名，
  再看槽位图标（顺序不能反，否则可能测的是缓存里的基础图标）；
- **崩溃加固**：制造"槽位里是已失效实体"的局面（同装会移除实体的 mod），
  再触发装备回位，看日志有无 `Assertion Failed`。

## 4. 常见坑

| 坑 | 说明 |
|---|---|
| 用单人世界测 client-only 行为 | 必须真的"客户端连服务器"，host 模式走的是 master 分支 |
| 只重登不进洞穴 | 配置丢失的原始 bug 只在跨 shard 出现 |
| 少装 mod 测图标 | 驻留表溢出/未注册 atlas 都要"接近真实"的 mod 数量才复现 |
| 主菜单阶段验证 atlas | `AtlasContains` 查的是**运行时已加载**的 atlas，主菜单阶段全 false |
| 用 `AtlasContains` 验证真实来源 | 会误杀皮肤图标（皮肤 atlas 可能尚未注册）→ 见 development §3.4 |
| 快照读取早于 classified 同步 | 会读到基础图标/空串，等一会儿或走 `ResyncIconsFromLiveItems` |
| 忘了禁用原版 | 两个 mod 同开会重复处理物品移动，现象混乱 |
| 只测同进程换 shard | 地表→洞穴的客户端一般**不重新加载 modmain**，内存里的开关本来就在；
  "开关不丢失"的难点在**重登**（新进程）与**文件读回前写盘覆盖**，必须真的退出重进 |
| 用旧版写盘文件测开关 | 旧文件没有 `disable_save_slots`，会表现为"开关没恢复到上次"，这是兼容路径不是 bug |
| 用中文名世界测文件名/隔离 | 本机 `client_save` 里的持久化文件是 `ses_fix_slots_unknown`，世界可能
  共用一份；测试时先用控制台打印 `TheNet:GetServerName()`，确认是空串还是被 `%W` 清洗掉了 |

## 5. 报告要求

- 场景逐条列表（S1~S16），每条给"通过/未通过/未验证"；
- 配置持久化类结论附**文件内容片段**（脱敏服务器名）；
- 图标类结论附截图，且必须先是"活体数据正确"的证据再看图标；
- 已知限制（换电脑不跟随、同名世界覆盖、中文名世界共用 `unknown` 文件）明确写出，别让用户误以为是 bug。

## 6. E2E 操作清单（S12–S16，照抄执行）

> 报告与证据目录（本轮）：`D:/Code/MyBlog/笔记/开发/饥荒/Mod/装备槽记忆/`
> ├── `验收报告.md`
> ├── `01-*.png` …（截图，报告里内嵌）
> └── `证据-日志原文.txt`（日志/命令输出原文）
> 硬约束：游戏同一时刻只给一个会话用，**收到协调者的开测通知才动手**。

### 6.0 开测前基线（记录，不然后面分不清谁的进程）

```bash
# 期望 0；若不是 0，先找协调者确认是不是上一轮没关干净
powershell -NoProfile -Command "Get-Process dontstarve_steam_x64,dontstarve_dedicated_server_nullrenderer_x64 -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize"

# 截图（每张证据都用这个；文件名按场景编号）
SHOT="D:/Code/MyBlog/笔记/开发/饥荒/Mod/装备槽记忆"
agent-desktop screenshot --headed --app "dontstarve_steam_x64.exe" "$SHOT/01-s14-toggle-off.png"
```

- 开测后只杀**本轮新出现**的 PID（见 §6.9），别误杀别人的会话；
- 每步的命令输出（文件读取结果）追加到 `证据-日志原文.txt`，截图存同目录。

### 6.1 前置：切到本地目录版 0.1.2（当前玩的是工坊 0.1.1）

```
主菜单 Play → 主界面菜单 Mods
  → 默认 Client 页签（左侧子菜单第一项）
  → 过滤条最左边「Mod Type Filter」按钮（图标在 All/Workshop/Local 间循环）→ 切到 Local
  → 列表只剩本地版 Save Equipment Slots (Fix)
  → 点该行**最右侧**的复选框 → 勾选（启用）
  （行内布局：左图标 / 名字 / 右侧复选框(约 x=140)；星标是收藏，别点错）
  → 过滤条再切到 Workshop → 找到同名条目 → 取消勾选（禁用）
      判定：本地版详情描述含「暂停开关状态」；工坊 0.1.1 不含
  → 右下角 Apply → 前端 SimReset
```

应用后立刻断言（`client_log.txt`）：

```bash
cd "D:/My/Documents/Klei/DoNotStarveTogether"
rg -n "Loading mod: (save_equipment_slots_fix|workshop-3836742363)" client_log.txt | tail -5
```

期望：出现 `Loading mod: save_equipment_slots_fix (Save Equipment Slots (Fix)) Version:0.1.2`，
且**没有**新的 `Loading mod: workshop-3836742363 ... Version:0.1.1` 行。

> 若 Apply 后日志没有重新加载 mod（或版本仍是 0.1.1）：彻底退出游戏再启动一次（有时前端重置不重读 modmain）。

### 6.2 每步都要读的文件（先备份，测完还原）

```bash
CS="D:/My/Documents/Klei/DoNotStarveTogether/202031981/client_save"
mkdir -p "D:/Code/MyBlog/笔记/开发/饥荒/Mod/装备槽记忆/evidence-backup"
cp -v "$CS"/ses_fix_slots_* "D:/Code/MyBlog/笔记/开发/饥荒/Mod/装备槽记忆/evidence-backup/" 2>/dev/null || true

python - <<'PY'
import glob, json
PREFIX = "KLEI     1 "   # 引擎写的持久化文件头(SetPersistentString 固定加)，后面才是 JSON
for f in sorted(glob.glob(r"D:/My/Documents/Klei/DoNotStarveTogether/202031981/client_save/ses_fix_slots_*")):
    raw = open(f, encoding="utf-8").read()
    if raw.startswith(PREFIX):
        raw = raw[len(PREFIX):]
    try:
        d = json.loads(raw)
    except Exception as e:
        print(f, "PARSE FAIL", e); continue
    items = d.get("items") or []
    if isinstance(items, list):   # 数组形式：[null, ["brush"], null, ...]
        slots = [i + 1 for i, v in enumerate(items) if v]
    else:                        # 对象形式：{"1": ["brush"], ...}
        slots = sorted(int(k) for k in items)
    print(f.rsplit("/", 1)[-1],
          "| toggle =", d.get("disable_save_slots", "<missing>"),
          "| slots =", slots)
PY
```

- `toggle = False` 表示「关闭保存」（Ctrl+V 关掉）；
- `toggle = True` 表示「开启保存」；
- `<missing>` 表示旧版文件或快捷键设为「无」（不写该字段）；
- 文件名可能是 `ses_fix_slots_unknown`（中文世界名/空服务器名，见 §4 坑表）——
  记下实际文件名写进报告；这种情况所有中文名世界共用一份，备份/还原更重要。
- 文件格式是 `KLEI     1 `（11 字符头）+ 一行 JSON；`GetPersistentString` 回调拿到的是**去掉头**的 JSON。
  手工改文件时必须保留这个头。

### 6.3 S14：切换即落盘

1. 进世界后等 3 秒（等 `LoadPersistedSlots` 读回文件）；
2. 按 `Ctrl + V`，屏幕上方出现 `Save Slots - OFF`；
3. 立刻执行 §6.2 的读文件命令 → 期望 `toggle = False`；
4. 截图：状态提示 + 文件输出（`01-s14-toggle-off.png`）。

> 若在刚进世界的 1 秒内就按，写盘会挂起到读回后，等 1–2 秒再看文件即可，不算失败。

### 6.4 S12：跨 shard（地表 ↔ 洞穴）

1. 地表保持 OFF（§6.2 读到 `False`）；
2. 下洞穴：控制台 `c_goto(c_find("cave_entrance"))` → 按空格进洞；
   （找不到就 `c_spawn("cave_entrance")` 再 `c_goto`；进洞后等加载完成）
3. 洞穴里执行 §6.2 → 期望仍是 `toggle = False`；
4. 按一次 `Ctrl + V` → 应显示 `Save Slots - ON`（证明进入洞穴时是 OFF）；再按一次回 OFF；
5. 截图 `02-s12-cave-off.png`；
6. 回地表：`c_goto(c_find("cave_exit"))` → 按空格，回到地表后重复第 3–4 步，截图 `03-s12-surface-off.png`。

### 6.5 S13：跨重登（新进程）

1. 地表确认 OFF；
2. 退出到主菜单（Esc → Quit → Yes），或直接关游戏（见 §6.9）；
3. 重新启动游戏 → 进同一世界；
4. 进世界后不要先按快捷键，直接执行 §6.2 → 期望 `toggle = False`；
5. 按一次 `Ctrl + V` → 显示 `Save Slots - ON`（证明恢复的是 OFF），再按一次回 OFF；
6. 截图 + 把两次的文件输出存进 `证据-日志原文.txt`。

### 6.6 S15：旧版文件兼容

1. 先备份文件（§6.2 已备份）；
2. 用 python 删掉文件里的 `disable_save_slots` 字段（保留 `version`/`items`）：

```bash
python - <<'PY'
import glob, json
PREFIX = "KLEI     1 "   # 必须保留：引擎按这个头读文件
for f in glob.glob(r"D:/My/Documents/Klei/DoNotStarveTogether/202031981/client_save/ses_fix_slots_*"):
    raw = open(f, encoding="utf-8").read()
    body = raw[len(PREFIX):] if raw.startswith(PREFIX) else raw
    d = json.loads(body)
    d.pop("disable_save_slots", None)
    open(f, "w", encoding="utf-8").write(PREFIX + json.dumps(d, separators=(",", ":")))
    print("stripped", f)
PY
```

3. Mods 配置里把「初始开关状态」设为 On；重进世界；
4. 期望：进世界后是「开启」状态；按一次 `Ctrl + V` 显示 `Save Slots - OFF`（反证此前是 ON），再按一次回 ON；
5. 再读文件 → 期望 `toggle = False`（首次 Flush 已把字段补回）。

### 6.7 S16：快捷键设为「无」

1. Mods → Configure（选中本地 mod 后右侧扳手按钮）→「暂停保存快捷键」选「无」→ 确认/Apply；
2. 重进世界（文件里有旧 `disable_save_slots` 也不该生效）；
3. 按 `Ctrl + V` 不应有任何反应/状态提示；
4. 放一件装备到槽位，再移动它，确认槽位记忆仍然工作；
5. 读文件 → 期望 `disable_save_slots` 字段**不存在**（不写）；
6. 恢复快捷键为 Ctrl + V，重进，确认开关可用。

### 6.8 回归抽查（上轮通过项，至少 3 条）

| 条 | 操作 | 期望 |
|---|---|---|
| S1 | 配好槽位 → 下洞穴 → 回地表 | 槽位配置仍在 |
| S2/S3 | 退出重进 | 槽位配置仍在 |
| S7 | 点槽位上方小图标 | 该格记忆被清除，图标消失 |
| S5/S6 | 重登后看装备槽图标 | 不是方块；皮肤图标正确 |

### 6.9 还原 Mod 启用状态（游戏还开着时做）

测试用的是本地目录版；测完按开测前记录恢复（默认：工坊版 `3836742363` 勾选、本地版取消勾选）→
右下 `Apply`。若用户已决定发布 0.1.2，则保留本地版并记进报告。

### 6.10 收尾：关游戏 + 确认进程消失 + 还原文件

```bash
cd D:/Code/MyMods/dst-mods

# 1) 游戏内优雅退出（可选，控制台注入；需要已进世界）
python tools/common/dstconsole.py 'TheSim:Quit()'

# 2) 兜底强杀（优雅退出失败时；只杀本轮基线之后新出现的 PID，别误杀别的会话）
powershell -NoProfile -Command "Get-Process dontstarve_steam_x64,dontstarve_dedicated_server_nullrenderer_x64 -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime"
powershell -NoProfile -Command "Get-Process dontstarve_steam_x64,dontstarve_dedicated_server_nullrenderer_x64 -ErrorAction SilentlyContinue | Stop-Process -Force"

# 3) 确认进程为 0（期望输出 0）
sleep 3
powershell -NoProfile -Command "@(Get-Process dontstarve_steam_x64,dontstarve_dedicated_server_nullrenderer_x64 -ErrorAction SilentlyContinue).Count"

# 4) 还原测试前的持久化文件（备份在 evidence-backup/）
CS="D:/My/Documents/Klei/DoNotStarveTogether/202031981/client_save"
cp -v "D:/Code/MyBlog/笔记/开发/饥荒/Mod/装备槽记忆/evidence-backup/"ses_fix_slots_* "$CS"/
```

> 只关游戏，不动 Steam；截图/日志复制到报告目录后再收尾。
