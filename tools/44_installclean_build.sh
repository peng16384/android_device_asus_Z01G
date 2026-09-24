#!/usr/bin/env bash
# installclean + 重編。
#
# 為什麼需要：out/target/product/Z01G/system 是增量的 —— 從 proprietary-files.txt
# 移除一條 blob 之後，那個檔案不會從 out 裡消失，還是會被包進 system.img。
# 實測：把 vendor.qti.gnss@1.0-service / vendor.nxp.hardware.nfc@1.0-service
# 排除並重編之後，它們的 .rc 與執行檔都還留在 out 裡，等於什麼都沒改。
#
# make installclean 只清 out/target/product/*（system、data、*.img），
# 保留 out/target/product/*/obj 與 out/soong，所以重編很快（不用重新編譯）。
#
# 規則：只要動過 proprietary-files.txt 的「移除」就要跑這支，不能只跑 22_build.sh。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

SRC="$HOME/lineage-16.0"
LOG=$DEVICE_PATH/docs/build.log
cd "$SRC"

export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_DIR="$HOME/.ccache"
export JACK_SERVER_VM_ARGUMENTS="-Xmx4g"
# bring-up 專用，理由見 22_build.sh
# ⚠ 2026-09-24 移除 `export WITH_ADB_INSECURE=true`。
#   它會讓 ro.adb.secure=0 —— 任何電腦插上 USB 就能直接 adb 進來，
#   不會跳授權對話框。bring-up 期間方便，但沒有理由留著。
#   （實際上現行的建置流程本來就沒帶它，裝置上是 ro.adb.secure=1；
#     這兩支舊腳本是唯一的殘留，留著等於埋一個陷阱。）
#   原本：export WITH_ADB_INSECURE=true

source build/envsetup.sh > /dev/null 2>&1
lunch lineage_Z01G-userdebug > /dev/null 2>&1
echo "  TARGET_PRODUCT=$TARGET_PRODUCT  變體=$TARGET_BUILD_VARIANT"

echo "=== installclean ==="
date '+  %F %T'
make installclean > /tmp/installclean.log 2>&1
echo "  rc=$?  （$(du -sh --si out/target/product/Z01G 2>/dev/null | cut -f1) 剩餘）"

echo "=== 重編 ==="
date '+  %F %T'
mka bacon -j"$(nproc)" > "$LOG" 2>&1
RC=$?
date '+  %F %T'
echo "  rc=$RC"

if [ "$RC" -ne 0 ]; then
    echo "=== 錯誤 ==="
    grep -nE "^(FAILED|ninja: error|error:|make: \*\*\*)" "$LOG" | head -20
    exit "$RC"
fi
echo "=== 成功 ==="
ls -lh out/target/product/Z01G/lineage-16.0-*-UNOFFICIAL-Z01G.zip out/target/product/Z01G/boot.img
