#!/usr/bin/env bash
# `m nothing` —— 解析整個 build graph 但不真的編譯
#
#   wsl -- bash $DEVICE_PATH/tools/18_check_buildgraph.sh
#
# breakfast 只驗證 product 設定合法；這一步才會讀遍所有 Android.mk / Android.bp、
# 展開 PRODUCT_PACKAGES 與 PRODUCT_COPY_FILES，找出：
#   - 引用了不存在的檔案（例如 BoardConfig.mk 指到的 config.fs）
#   - PRODUCT_PACKAGES 裡沒有對應模組的名字
#   - sepolicy / manifest 的問題
#
# 比直接 brunch 快非常多（分鐘 vs 小時），適合用來迭代。
# 注意：不能開 set -u —— envsetup.sh 與它定義的 m/lunch/breakfast 函式
# 都會踩到未設定的變數（TOP 等），開了會直接 "unbound variable" 中止。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

SRC="$HOME/lineage-16.0"
LOG=$DEVICE_PATH/docs/buildgraph.log
mkdir -p "$(dirname "$LOG")"

cd "$SRC"

source build/envsetup.sh > /dev/null 2>&1
lunch lineage_Z01G-userdebug > /dev/null 2>&1

echo "=== m nothing（完整輸出在 $LOG）==="
date '+  開始 %F %T'
m nothing -j"$(nproc)" > "$LOG" 2>&1
RC=$?
date '+  結束 %F %T'
echo "  rc=$RC"

echo
echo "=== 錯誤 ==="
grep -nE "error:|Error [0-9]|FAILED|does not exist|No such file|not found|cannot find" "$LOG" \
    | grep -viE "warning" | head -40

echo
echo "=== 最後 30 行 ==="
tail -30 "$LOG"

exit "$RC"
