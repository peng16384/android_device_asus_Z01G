#!/usr/bin/env bash
# 刷機前的一次性檢查，把過去幾輪踩過的坑全部驗一遍。
#
#   wsl -u root -- bash $DEVICE_PATH/tools/45_preflight.sh
#
# 每一項都對應一次實際的開機失敗，不是形式檢查：
#   1  ramdisk 有沒有 fstab.qcom          第 1 輪：沒有 -> first-stage init 掛不了 /system
#   2  vendor fstab 不能有 /system         第 2 輪：有 -> mount_all 失敗 -> zygote 不啟動
#   3  init 服務與執行檔有沒有錯位         第 3 輪：audio HAL 的 .rc 被排掉 -> system_server 卡死
#   4  USB / adb 屬性                      第 3 輪：persist.sys.usb.config=none -> USB 不列舉
#   5  blob 還缺哪些函式庫                 第 2 輪：android.hidl.base@1.0 缺 -> 所有 vendor HAL exit(1)
#   6  產物完整性與分割區大小
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

PROJ=$DEVICE_PATH
SRC=$HOME/lineage-16.0
OUT=$SRC/out/target/product/Z01G

fail=0
ok()   { echo "  [OK]  $*"; }
bad()  { echo "  [!!]  $*"; fail=$((fail+1)); }

echo "=== 1. ramdisk 的 /fstab.qcom ==="
if [ -f "$OUT/root/fstab.qcom" ]; then
    if grep -vE '^\s*#' "$OUT/root/fstab.qcom" | grep -qE '^\S+\s+/system\s'; then
        ok "有 fstab.qcom 且含 /system 條目"
    else
        bad "fstab.qcom 沒有 /system -> first-stage init 會掛不了 /system"
    fi
else
    bad "ramdisk 根目錄沒有 fstab.qcom"
fi

echo "=== 2. /vendor/etc/fstab.qcom ==="
V=$OUT/system/vendor/etc/fstab.qcom
if [ -f "$V" ]; then
    if grep -vE '^\s*#' "$V" | grep -qE '^\S+\s+/system\s'; then
        bad "vendor fstab 含 /system -> e2fsck 會對已掛載分割失敗，mount_all 整體回傳 -1"
    else
        ok "vendor fstab 沒有 /system（正確）"
    fi
    grep -qE '/data\s.*encryptable' "$V" && ok "/data 用 encryptable（非 forceencrypt）" \
        || bad "/data 不是 encryptable，bring-up 期間會進加密流程"
else
    bad "沒有 /vendor/etc/fstab.qcom -> ASUS init.target.rc 的 mount_all 會失敗"
fi

echo "=== 3. init 服務 vs 執行檔錯位 ==="
bash "$PROJ/tools/40_check_services.sh" > /tmp/svc.txt 2>&1
n2=$(sed -n '/^=== (2)/,$p' /tmp/svc.txt | grep -c '/vendor/bin/hw/')
echo "  vendor/bin/hw 裡沒有對應服務的執行檔：$n2 個"
sed -n '/^=== (2)/,$p' /tmp/svc.txt | grep '/vendor/bin/hw/' | sed 's/^/    /'
if sed -n '/^=== (1)/,/^=== (2)/p' /tmp/svc.txt | grep -qE 'audio-hal|wifi_hal_legacy|media\.omx|keymaster-3-0'; then
    bad "關鍵 HAL 有服務定義但執行檔不存在"
else
    ok "關鍵 HAL（audio / wifi / media.omx / keymaster）服務與執行檔都在"
fi

echo "=== 4. USB / adb 屬性 ==="
grep -q 'persist.sys.usb.config=adb' "$OUT/root/default.prop" \
    && ok "persist.sys.usb.config=adb" \
    || bad "persist.sys.usb.config 不是 adb -> USB gadget 不會被綁定"
grep -q 'ro.adb.secure=0' "$OUT/root/default.prop" \
    && ok "ro.adb.secure=0（bring-up 用，之後要拿掉）" \
    || bad "ro.adb.secure=1 -> 需要在畫面上按授權，但現在沒有畫面"

echo "=== 5. blob 還缺哪些函式庫 ==="
python3 "$PROJ/tools/36_check_blob_deps.py" 2>&1 | sed -n '/缺 [0-9]* 個函式庫/p;/原廠有 ->/p' | head -20 | sed 's/^/  /'

echo "=== 6. 產物 ==="
ZIP=$(ls -t "$OUT"/lineage-16.0-*-UNOFFICIAL-Z01G.zip 2>/dev/null | head -1)
if [ -n "$ZIP" ]; then
    ok "$(basename "$ZIP")  $(du -h --si "$ZIP" | cut -f1)"
    b=$(stat -c %s "$OUT/boot.img")
    [ "$b" -le 33554432 ] && ok "boot.img $b / 33554432" || bad "boot.img 超過分割區大小"
else
    bad "找不到 zip"
fi

echo
[ "$fail" -eq 0 ] && echo "全部通過，可以刷。" || echo "有 $fail 項要處理。"
exit "$fail"
