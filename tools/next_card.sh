#!/usr/bin/env bash
# 在职位列表页找「第一张尚未处理过的卡」(与 投递记录.md 比对公司名)
# 输出: "x y 公司名"   —— 可直接 tap;若无未处理卡输出 "NONE"
set -u
export MSYS_NO_PATHCONV=1

ADB="${ADB:-adb}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="$HERE/../投递记录.md"
XML="$(mktemp -d)/list.xml"

# 找不到 adb 就直接报错退出 —— 不能静默,否则会被误读成「列表刷到底了」
if ! command -v "$ADB" >/dev/null 2>&1 && [ ! -x "$ADB" ]; then
  echo "找不到 adb（当前用 '$ADB'）。把 adb 加进 PATH，或 export ADB=/path/to/adb" >&2
  exit 1
fi

"$ADB" shell uiautomator dump /sdcard/list_auto.xml >/dev/null 2>&1
"$ADB" exec-out cat /sdcard/list_auto.xml > "$XML" 2>/dev/null

# dump 为空同理:手机没连、没授权，或当前不在列表页
if [ ! -s "$XML" ]; then
  echo "UI dump 为空：手机没连上/未授权，或界面不在 BOSS直聘。" >&2
  exit 1
fi

while IFS=$'\t' read -r comp b; do
  [ -z "${comp:-}" ] && continue
  [ -z "${b:-}" ] && continue
  x1="$(echo "$b" | sed 's/\[\([0-9]*\),.*/\1/')"
  y1="$(echo "$b" | sed 's/\[[0-9]*,\([0-9]*\)\]\[.*/\1/')"
  x2="$(echo "$b" | sed 's/.*\]\[\([0-9]*\),.*/\1/')"
  y2="$(echo "$b" | sed 's/.*,\([0-9]*\)\]$/\1/')"
  [ $((y2 - y1)) -lt 300 ] && continue                  # 半露的卡跳过
  key="$(echo "$comp" | sed 's/[.．…]*$//')"             # 去掉尾部省略号
  [ -z "$key" ] && continue
  if [ ! -f "$LOG" ] || ! grep -qF "$key" "$LOG"; then
    printf '%s' "$key" > "$HERE/.last_company"
    echo "$(( (x1 + x2) / 2 )) $(( (y1 + y2) / 2 )) $key"
    exit 0
  fi
done < <(powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$HERE/cards.ps1")" -XmlPath "$(cygpath -w "$XML")" 2>/dev/null | tr -d '\r')

echo "NONE"
