#!/usr/bin/env bash
# 檢查 proprietary-files.txt 列的檔案是否都真的被抽出來了
#
#   wsl -u root -- bash $DEVICE_PATH/tools/33_check_extract.sh
#
# 起因：清單 3544 條，但 vendor/asus/Z01G/proprietary 只有 3345 個檔案，
# 編譯時炸在
#   ninja: error: 'vendor/asus/Z01G/proprietary/vendor/etc/firmware/wcd9320/
#          wcd9320_anc.bin', needed by ..., missing and no known rule to make it
#
# extract-files.sh 對抽不到的檔案只會印一行訊息就繼續，不會讓整個流程失敗，
# 所以要另外檢查。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

SRC="$HOME/lineage-16.0"
[ -d "$SRC" ] || SRC=$HOME/lineage-16.0
LIST="$SRC/device/asus/Z01G/proprietary-files.txt"
PROP="$SRC/vendor/asus/Z01G/proprietary"
IMG=$DEVICE_PATH/images/system.img
MNT=/mnt/zs_system

mountpoint -q "$MNT" || mount -o ro,loop "$IMG" "$MNT" 2>/dev/null

grep -v '^#' "$LIST" | grep -v '^$' | sed 's/|.*//; s/^-//' | sed 's/:.*//' | sort -u > /tmp/want.txt
( cd "$PROP" && find . -type f | sed 's#^\./##' | sort ) > /tmp/got.txt

echo "清單 $(wc -l < /tmp/want.txt) 條 / 實際抽出 $(wc -l < /tmp/got.txt) 個"
comm -23 /tmp/want.txt /tmp/got.txt > /tmp/miss.txt
echo "缺 $(wc -l < /tmp/miss.txt) 條"
echo

echo "=== 缺的檔案在映像裡是什麼型態 ==="
sym=0; reg=0; none=0
: > /tmp/miss_symlink.txt
while IFS= read -r rel; do
    t="$MNT/$rel"
    if [ -L "$t" ]; then
        sym=$((sym+1)); echo "$rel -> $(readlink "$t")" >> /tmp/miss_symlink.txt
    elif [ -f "$t" ]; then
        reg=$((reg+1))
    else
        none=$((none+1))
    fi
done < /tmp/miss.txt
echo "  symlink      $sym"
echo "  一般檔案     $reg"
echo "  映像裡不存在 $none"

echo
echo "=== symlink 範例（前 15）==="
head -15 /tmp/miss_symlink.txt | sed 's/^/  /'

echo
echo "=== 缺的按目錄分佈 ==="
sed 's#/[^/]*$##' /tmp/miss.txt | sort | uniq -c | sort -rn | head -15 | sed 's/^/  /'

cp /tmp/miss.txt $DEVICE_PATH/blobs/extract_missing.txt
echo
echo "清單已寫到 work/blobs/extract_missing.txt"
