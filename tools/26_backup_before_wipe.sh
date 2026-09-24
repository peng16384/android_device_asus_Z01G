#!/usr/bin/env bash
# 刷 LineageOS 前的備份（在 Git Bash 或 WSL 執行，adb 走 Windows 版）
#
#   ADB=/path/to/adb bash tools/26_backup_before_wipe.sh
#
# 刷 LineageOS 一定要 wipe /data —— 原廠是 FDE(block) 加密，LineageOS 的
# 加密方式不同，不 wipe 幾乎必定開不了機。所以先把東西弄下來。
#
# /data 現況（33 GB）：
#   /data/media  20 GB   內部儲存空間 —— 其中 16.8 GB 是 TWRP 自己的備份資料夾
#                        （已在 _docs/backup/TWRP），真正的使用者檔案 < 4 GB
#   /data/app     6.1 GB  APK
#   /data/data    4.0 GB  app 資料
#   /data/user_de 953 MB
#   /data/system  249 MB
#
# 本腳本只負責 /data/media（內部儲存空間）。
# app 資料由 TWRP 備份負責 —— 既有的 2026-09-21 那份已涵蓋（13 GB / 96033 檔）。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

ADB="${ADB:-adb}"
DST="${DST:-$DEVICE_PATH/docs/backup_before_wipe}"
SD=/sdcard

adb_() { MSYS_NO_PATHCONV=1 "$ADB" "$@"; }

echo "=== 手機狀態 ==="
adb_ devices -l | sed 's/^/  /'
adb_ shell 'su -c id' | sed 's/^/  root: /'

mkdir -p "$DST/sdcard"

echo
echo "=== 頂層項目 ==="
# 一定要 -A（含 dotfiles，排除 . 與 ..）——
# 用 ls -1 會漏掉 .RecycleBin（203 MB / 157 個檔案）、.trash 之類的隱藏目錄，
# 而且事後只從「檔案數對不上」才會發現。
mapfile -t ITEMS < <(adb_ shell "ls -1A $SD" 2>/dev/null | tr -d '\r')
for i in "${ITEMS[@]}"; do echo "  $i"; done

echo
echo "=== 逐項拉取（跳過 TWRP，它已經在 _docs/backup/TWRP）==="
FAIL=0
for i in "${ITEMS[@]}"; do
    [ -n "$i" ] || continue
    if [ "$i" = "TWRP" ]; then
        echo "  [跳過] TWRP（16.8 GB，已在 _docs/backup/TWRP）"
        continue
    fi
    echo "  [拉取] $i"
    if ! adb_ pull -a "$SD/$i" "$DST/sdcard/" 2>&1 | tail -1 | sed 's/^/         /'; then
        echo "         !!! 失敗"
        FAIL=1
    fi
done

echo
echo "=== 結果 ==="
du -sh "$DST/sdcard" 2>/dev/null | sed 's/^/  總大小 /'
echo "  檔案數 $(find "$DST/sdcard" -type f 2>/dev/null | wc -l)"

echo
echo "=== 與手機對照（檔案數，不含 TWRP）==="
# 排除條件寫在 su -c 的引號裡容易失效，改成事後用 grep 濾掉比較可靠
PHONE=$(adb_ shell "su -c 'find /data/media/0 -type f'" 2>/dev/null \
        | tr -d '\r' | grep -v '^/data/media/0/TWRP/' | wc -l)
LOCAL=$(find "$DST/sdcard" -type f 2>/dev/null | wc -l)
echo "  手機 $PHONE / 本機 $LOCAL"
[ "$PHONE" = "$LOCAL" ] && echo "  一致" || echo "  !!! 不一致，請檢查上面的失敗項目"

echo
echo "=== 產生校驗清單 ==="
( cd "$DST/sdcard" && find . -type f -exec sha256sum {} + 2>/dev/null ) > "$DST/sdcard_sha256.txt"
echo "  $(wc -l < "$DST/sdcard_sha256.txt") 個檔案 -> $DST/sdcard_sha256.txt"

exit "$FAIL"
