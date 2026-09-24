#!/bin/bash
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

O=$HOME/lineage-16.0/out/target/product/Z01G/system
echo "=== 這輪要修的東西有沒有裝進去 ==="
for f in usr/keylayout/focal-touchscreen.kl usr/keylayout/goodixfp.kl usr/keylayout/gpio-keys.kl \
         usr/idc/focal-touchscreen.idc usr/keychars/focal-touchscreen.kcm \
         framework/org.simalliance.openmobileapi.jar \
         etc/permissions/org.simalliance.openmobileapi.xml; do
    if [ -e "$O/$f" ]; then echo "  [有] $f"; else echo "  [缺] $f"; fi
done
printf "  %s AsusCamera\n" "$([ -e "$O/vendor/app/AsusCamera" ] && echo '[還在!]' || echo '[已移除]')"
printf "  %s framework/com.android.nfc_extras.jar\n" "$([ -e "$O/framework/com.android.nfc_extras.jar" ] && echo '[還在!]' || echo '[已移除]')"

echo
echo "=== keylayout 內容（不能有 GESTURE_，否則整個檔案會被丟掉）==="
echo "  focal-touchscreen.kl 裡的 GESTURE 行數: $(grep -c '^key.*GESTURE' "$O/usr/keylayout/focal-touchscreen.kl" 2>/dev/null)"
grep '^key' "$O/usr/keylayout/focal-touchscreen.kl" 2>/dev/null | sed 's/^/    /'
echo "  goodixfp.kl:"
grep '^key' "$O/usr/keylayout/goodixfp.kl" 2>/dev/null | sed 's/^/    /'

echo
echo "=== 還有沒有 apk/jar 缺 classes.dex ==="
bash $DEVICE_PATH/tools/56_check_dex.sh "$O"

echo
echo "=== 還有沒有懸空的函式庫宣告 ==="
bash $DEVICE_PATH/tools/55_dangling_libs.sh | tail -5
