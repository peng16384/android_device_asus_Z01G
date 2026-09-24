#!/usr/bin/env bash
# 全面比對：映像裡有、proprietary-files.txt 沒收的檔案
#
#   wsl -u root -- bash $DEVICE_PATH/tools/30_gap_check_full.sh
#
# 13_gap_check.sh 只掃了幾個「猜得到」的類別（相機/音效/WLAN/thermal/GPS），
# 結果漏掉了 vendor/etc/init/hw/init.qcom.rc 這種關鍵檔案 ——
# 沒有它，就算 /system 掛起來也不會有任何 qcom HAL 啟動。
#
# 這支改成反過來做：把整個 vendor/etc、vendor/bin、etc/init 全列出來，
# 逐一對照清單，不做任何「哪些重要」的預判。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

IMG=$DEVICE_PATH/images/system.img
MNT=/mnt/zs_system
LIST=$DEVICE_PATH/proprietary-files.txt
OUT=$DEVICE_PATH/blobs/gap_full.txt

mkdir -p "$MNT"
mountpoint -q "$MNT" || mount -o ro,loop "$IMG" "$MNT" || { echo "!!! 掛載失敗" >&2; exit 1; }

grep -v '^#' "$LIST" | grep -v '^$' | sed 's/|.*//; s/^-//' | sed 's/:.*//' | sort -u > /tmp/have.txt
echo "清單現有 $(wc -l < /tmp/have.txt) 條"
echo

: > "$OUT"
scan() {
    local label="$1" dir="$2"
    [ -d "$MNT/$dir" ] || return 0
    local n=0
    local tmp
    tmp=$(mktemp)
    ( cd "$MNT" && find "$dir" -type f 2>/dev/null | sort ) > "$tmp"
    local total
    total=$(wc -l < "$tmp")
    while IFS= read -r rel; do
        grep -qxF "$rel" /tmp/have.txt || { echo "$rel" >> "$OUT"; n=$((n+1)); }
    done < "$tmp"
    rm -f "$tmp"
    printf '  %-28s %5d / %5d 缺\n' "$label" "$n" "$total"
}

echo "=== 逐區掃描（缺 / 總數）==="
scan "vendor/etc/init"      vendor/etc/init
scan "vendor/etc（全部）"    vendor/etc
scan "vendor/bin"           vendor/bin
scan "etc/init"             etc/init
scan "etc/permissions"      etc/permissions
scan "vendor/firmware"      vendor/firmware

echo
echo "=== vendor/etc/init 缺的（最關鍵）==="
grep '^vendor/etc/init' "$OUT" | sed 's/^/  /'

echo
echo "=== vendor/etc 其他缺的（前 40）==="
grep '^vendor/etc/' "$OUT" | grep -v '^vendor/etc/init' | head -40 | sed 's/^/  /'

echo
echo "=== vendor/bin 缺的（前 30）==="
grep '^vendor/bin' "$OUT" | head -30 | sed 's/^/  /'

echo
echo "缺漏總計 $(wc -l < "$OUT") 條 -> $OUT"
