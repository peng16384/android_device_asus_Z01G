#!/usr/bin/env bash
# 完整編譯 LineageOS 16.0 for Z01G
#
#   wsl -- bash $DEVICE_PATH/tools/22_build.sh
#
# 預期第一次會失敗數次 —— 目的是收集編譯錯誤逐一修，不是期待一次就過。
# 24 執行緒 + ccache，順利的話約 40–90 分鐘；中途失敗會更快。
#
# 注意：不能開 set -u（envsetup.sh 的函式會踩到未設定變數）。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

SRC="$HOME/lineage-16.0"
LOG=$DEVICE_PATH/docs/build.log
mkdir -p "$(dirname "$LOG")"

cd "$SRC"

export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_DIR="$HOME/.ccache"
# LineageOS 16.0 的 jack 已經不用了，但 javac 記憶體仍需拉高
export JACK_SERVER_VM_ARGUMENTS="-Xmx4g"

# bring-up 專用：關掉 adb 金鑰驗證。
#
# 為什麼一定要：device tree 裡已經把 persist.sys.usb.config 設成 adb，
# 但 ro.adb.secure=1 時 adbd 會要求在手機畫面上按「允許 USB 偵錯」。
# 現在 system_server 還起不來、根本沒有畫面可以按，等於 adb 永遠連不上。
# vendor/lineage/config/common.mk 看這個環境變數：
#     ifdef WITH_ADB_INSECURE -> PRODUCT_SYSTEM_DEFAULT_PROPERTIES += ro.adb.secure=0
# 而 build/make/tools/post_process_props.py 看到 ro.adb.secure != 1 時，
# 還會自動幫 persist.sys.usb.config 補上 adb —— 兩邊一致。
#
# 副作用：任何接上的電腦都能直接 adb 進來，不會跳授權。
# 能正常開機、能在畫面上授權之後要拿掉這一行重編。
# ⚠ 2026-09-24 移除 `export WITH_ADB_INSECURE=true`。
#   它會讓 ro.adb.secure=0 —— 任何電腦插上 USB 就能直接 adb 進來，
#   不會跳授權對話框。bring-up 期間方便，但沒有理由留著。
#   （實際上現行的建置流程本來就沒帶它，裝置上是 ro.adb.secure=1；
#     這兩支舊腳本是唯一的殘留，留著等於埋一個陷阱。）
#   原本：export WITH_ADB_INSECURE=true

echo "=== 環境 ==="
echo "  jobs    : $(nproc)"
echo "  記憶體  : $(free -h | awk 'NR==2{print $2}')"
echo "  可用空間: $(df -h . | tail -1 | awk '{print $4}')"
echo "  ccache  : $(ccache -s | awk '/max cache size/{print $4,$5}')"
echo "  log     : $LOG"
echo

source build/envsetup.sh > /dev/null 2>&1
lunch lineage_Z01G-userdebug > /dev/null 2>&1
echo "  TARGET_PRODUCT=$TARGET_PRODUCT  變體=$TARGET_BUILD_VARIANT"
echo

echo "=== 開始編譯 ==="
date '+  %F %T'
mka bacon -j"$(nproc)" > "$LOG" 2>&1
RC=$?
date '+  %F %T'
echo "  rc=$RC"

echo
if [ "$RC" -ne 0 ]; then
    echo "=== 編譯失敗，錯誤摘要 ==="
    grep -nE "error:|Error [0-9]+|FAILED:|ninja: build stopped" "$LOG" \
        | grep -viE "warning" | head -30
    echo
    echo "=== 最後 25 行 ==="
    tail -25 "$LOG"
    exit "$RC"
fi

echo "=== 成功 ==="
# 注意：這個流程不會產生獨立的 system.img —— system 以 system.new.dat.br 的形式
# 包在 zip 裡（block-based OTA）。早期版本這裡 ls system.img 會失敗，
# 因為是最後一個命令，整支腳本的結束碼就變成非 0，看起來像編譯失敗。
ls -lh "$SRC"/out/target/product/Z01G/lineage-*.zip 2>/dev/null | sed 's/^/  /'
ls -lh "$SRC"/out/target/product/Z01G/boot.img "$SRC"/out/target/product/Z01G/recovery.img 2>/dev/null | sed 's/^/  /'
exit 0
