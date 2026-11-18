#!/usr/bin/env bash
# 在 DST 控制台执行一段 Lua，直到日志里出现指定标记（用于无人值守验收）。
#
# 用法：
#   tools/common/dstlua.sh '[T] hi' 'print("[T] hi")'
#   tools/common/dstlua.sh '[T] hi' 'print("[T] hi")' --no-toggle
#
# 为什么要有重试：控制台是 ` 键 **toggle**，脚本不知道它当前开没开。
# 反复调用会在"开/关"之间翻转，直到某次真的执行成功（日志出现标记）。
#
# 环境变量：
#   DST_LOG   客户端日志路径（默认自动找 文档/Klei/DoNotStarveTogether/client_log.txt）
#   DST_APP   窗口标题（默认 "Don't Starve Together"）
set -u

MARK="${1:?用法: dstlua.sh 日志标记 lua源码 [--no-toggle]}"
LUA="${2:?缺少 lua 参数}"
shift 2 || true
EXTRA=("$@")

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_log() {
  if [ -n "${DST_LOG:-}" ]; then echo "$DST_LOG"; return; fi
  for p in \
    "$USERPROFILE/Documents/Klei/DoNotStarveTogether/client_log.txt" \
    "D:/My/Documents/Klei/DoNotStarveTogether/client_log.txt" \
    "$HOME/Documents/Klei/DoNotStarveTogether/client_log.txt"
  do
    [ -f "$p" ] && { echo "$p"; return; }
  done
  echo "找不到 client_log.txt，请设置 DST_LOG" >&2; exit 2
}

LOG="$(find_log)"
APP_ARG=()
if [ -n "${DST_APP:-}" ]; then APP_ARG=(--app "$DST_APP"); fi

for _ in 1 2 3 4; do
  if ! python "$HERE/dstconsole.py" "$LUA" "${APP_ARG[@]+"${APP_ARG[@]}"}" "${EXTRA[@]+"${EXTRA[@]}"}" >/dev/null 2>&1; then
    echo "注入失败（游戏窗口在不在？）" >&2
    exit 2
  fi
  sleep 3
  if grep -aq -- "$MARK" "$LOG"; then
    grep -a -- "$MARK" "$LOG" | tail -3
    exit 0
  fi
done

echo "FAIL: $MARK"
exit 1
