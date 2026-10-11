#!/usr/bin/env bash
# 读取当前职位详情页的完整 JD;带 -v/-r 时,读完顺带把判定写入 投递记录.md。
#
# 用法:
#   bash tools/read_jd.sh                       # 只读 JD,打印全部字段
#   bash tools/read_jd.sh -v 投 -r "理由..."     # 读 JD + 追加一行到 投递记录.md
#   bash tools/read_jd.sh -v 否 -r "理由..." -o out.txt   # 同时把 JD 存文件
set -u
export MSYS_NO_PATHCONV=1

ADB="${ADB:-adb}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="$HERE/../投递记录.md"
PHONE_DUMP=/sdcard/jd_auto.xml

# 找不到 adb 就直接报错退出
if ! command -v "$ADB" >/dev/null 2>&1 && [ ! -x "$ADB" ]; then
  echo "找不到 adb（当前用 '$ADB'）。把 adb 加进 PATH，或 export ADB=/path/to/adb" >&2
  exit 1
fi
WORK="$(mktemp -d)"
XML="$WORK/jd_auto.xml"
OUT_HEAD="$WORK/head.txt"   # 页面顶部字段(岗位/薪资/公司…)
OUT="$WORK/jd.txt"          # JD 正文所在
VERDICT=""; REASON=""

while [ $# -gt 0 ]; do
  case "$1" in
    -v) VERDICT="${2:-}"; shift 2;;
    -r) REASON="${2:-}";  shift 2;;
    -o) OUT="${2:-}";     shift 2;;
    *)  shift;;
  esac
done

swipe() { "$ADB" shell input swipe "$1" "$2" "$3" "$4" "${5:-400}" >/dev/null 2>&1; }
dump() {
  "$ADB" shell uiautomator dump "$PHONE_DUMP" >/dev/null 2>&1
  "$ADB" exec-out cat "$PHONE_DUMP" > "$XML" 2>/dev/null
}
extract() {  # $1 = 输出文件
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$HERE/extract_jd.ps1")" \
    -XmlPath "$(cygpath -w "$XML")" -OutPath "$(cygpath -w "$1")" >/dev/null
}
field() { awk -F'\r' -v k="### $1" '$0 ~ k {getline; print $1; exit}' "$2"; }

# ---- 1) 滚到页面顶部,先抓头部字段(岗位/薪资/公司) ----
for _ in 1 2 3; do swipe 540 900 540 2000 300; sleep 0.8; done
dump
extract "$OUT_HEAD"

# ---- 2) 逐屏下滑,直到 JD 块出现 ----
for _ in 1 2 3 4 5 6; do
  grep -q 'id/tv_description' "$XML" && break
  swipe 540 1800 540 900 400; sleep 1.2; dump
done
if ! grep -q 'id/tv_description' "$XML"; then
  echo "未找到 JD 节点(可能不在职位详情页)" >&2; exit 1
fi

y2="$(grep -o 'tv_description"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$XML" | head -1 \
      | sed -n 's/.*\]\[[0-9]*,\([0-9]*\)\]"/\1/p')"
if [ -n "${y2:-}" ] && [ "$y2" -gt 2100 ]; then swipe 540 1700 540 1100 300; sleep 1.2; dump; fi

# ---- 3) 展开「查看更多」----
for i in 0 1 2 3 4; do
  grep -q '查看更多' "$XML" || break
  bounds="$(grep -o 'tv_description"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$XML" | head -1 \
            | grep -o '[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*' | tr '][' '  ' | tr ',' ' ')"
  if [ -z "$bounds" ]; then sleep 1; dump; continue; fi
  read -r x1 y1 x2 y2 <<< "$bounds"
  "$ADB" shell input tap $((x2 - 60)) $((y2 - 30 - i * 45)) >/dev/null 2>&1
  sleep 1.3; dump
done

# ---- 4) 输出 ----
extract "$OUT"
cat "$OUT_HEAD"
cat "$OUT"

# ---- 5) 有判定就写投递记录 ----
if [ -n "$VERDICT" ]; then
  job="$(field tv_job_name "$OUT_HEAD")"
  salary="$(field tv_job_salary "$OUT_HEAD")"
  company="$(cat "$HERE/.last_company" 2>/dev/null)"
  [ -z "$company" ] && company="$(field tv_boss_title "$OUT_HEAD" | sed 's/ • .*//')"
  ts="$(date '+%Y-%m-%d %H:%M')"
  n=$(( $(grep -c '^| 自动#' "$LOG" 2>/dev/null || echo 0) + 1 ))
  case "$VERDICT" in
    投*) emoji='✅ 已沟通';;
    *)   emoji='⏭ 跳过';;
  esac
  row="| 自动#$n | $ts | $job | $company | $salary | — | **自动判定 $VERDICT**:$REASON | $emoji |"
  awk -v r="$row" '/^---$/{print r; print ""; print; next} {print}' "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  echo ""
  echo "--- 已写入投递记录 ---"
  echo "$row"
fi
