#!/bin/bash
# 交叉比對「init 服務定義」與「實際安裝的執行檔」。
#
# 為什麼要這支：
#   第一次開到開機動畫卻卡住，根因是 /vendor/bin/hw/android.hardware.audio@2.0-service
#   這個 blob 有被收進來，但它的 .rc 被 31_build_blob_list.py 的 EXCLUDE_PATTERNS
#   排掉了（當初以為「AOSP 會自己編這些 HAL、會自帶 rc」，後來 32_prune_device_mk.py
#   又把那些 AOSP 套件從 device.mk 拿掉，兩邊對不起來）。
#   結果：執行檔在、但 init 完全沒有這個服務 -> IDevicesFactory 永遠沒人註冊
#   -> AudioFlinger 的建構子卡死 -> media.audio_flinger 沒註冊 -> system_server 卡住。
#
#   這種「binary 在但 rc 不在」或「rc 在但 binary 不在」的錯位不會有任何編譯錯誤，
#   只會在開機時安靜地卡住，所以每次改 blob 清單後都要跑這支。
OUT=$HOME/lineage-16.0/out/target/product/Z01G
SYS=$OUT/system
ROOT=$OUT/root

tmp=$(mktemp -d)
# 收集所有 rc 檔
find $SYS/etc/init $SYS/vendor/etc/init $ROOT -name '*.rc' 2>/dev/null > $tmp/rcs
echo "掃描 $(wc -l < $tmp/rcs) 個 .rc 檔"
echo

# service <name> <path>
grep -h -E '^service[[:space:]]+' $(cat $tmp/rcs) 2>/dev/null \
  | awk '{print $2"\t"$3}' | sort -u > $tmp/services

echo "=== (1) 有 service 定義、但執行檔不存在 ==="
while IFS=$'\t' read -r name path; do
    # /vendor/... 在非 Treble 實際落在 /system/vendor/...
    real="$SYS${path#/system}"
    case "$path" in
        /vendor/*) real="$SYS/vendor${path#/vendor}" ;;
        /system/*) real="$SYS${path#/system}" ;;
        /sbin/*|/init*) real="$ROOT$path" ;;
    esac
    [ -e "$real" ] || printf "  %-34s %s\n" "$name" "$path"
done < $tmp/services

echo
echo "=== (2) vendor/bin/hw 裡有執行檔、但沒有任何 service 用它 ==="
for f in $SYS/vendor/bin/hw/* $SYS/vendor/bin/* ; do
    [ -f "$f" ] || continue
    p="/vendor${f#$SYS/vendor}"
    grep -qF "	$p" $tmp/services || printf "  %s\n" "$p"
done
rm -rf $tmp
