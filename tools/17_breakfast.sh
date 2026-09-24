#!/usr/bin/env bash
# 第一次跑 breakfast，讓 build 系統告訴我們還缺什麼
#
#   wsl -- bash $DEVICE_PATH/tools/17_breakfast.sh
#
# 預期會失敗 —— 這一步的目的就是收集錯誤，而不是期待它一次就過。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -uo pipefail

SRC="$HOME/lineage-16.0"
LOG=$DEVICE_PATH/docs/breakfast.log
mkdir -p "$(dirname "$LOG")"

cd "$SRC"

echo "=== 環境 ==="
echo "  java: $(java -version 2>&1 | head -1)"
echo "  ccache: $(ccache -s 2>/dev/null | head -1)"
echo

echo "=== breakfast Z01G（完整輸出在 $LOG）==="
set +u          # envsetup.sh 對 set -u 不友善
source build/envsetup.sh > /dev/null 2>&1
breakfast Z01G > "$LOG" 2>&1
RC=$?
set -u

echo "  rc=$RC"
echo
echo "=== 錯誤摘要 ==="
grep -iE "error|not found|no such|cannot|failed|missing" "$LOG" | sort -u | head -40

echo
echo "=== 最後 25 行 ==="
tail -25 "$LOG"

exit 0
