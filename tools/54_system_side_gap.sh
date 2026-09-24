#!/bin/bash
# 檢查 system 側（非 vendor/）有哪些「宣告共用函式庫的 permissions xml」
# 與「framework jar」沒被收進 blob 清單。
#
# 起因：SmartcardService.apk 在 vendor/app 所以被收了，但它 uses-library 的
# org.simalliance.openmobileapi.jar 與對應的 permissions xml 都在 /system，
# 而 31_build_blob_list.py 對 system 側只沿用早期人工挑過的清單 ->
#   java.lang.NoClassDefFoundError: Lorg/simalliance/openmobileapi/service/ISmartcardService$Stub;
#   -> SmartcardService keeps stopping（開機後跳對話框）
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

K=/mnt/zs_system
L=$DEVICE_PATH/proprietary-files.txt
O=$HOME/lineage-16.0/out/target/product/Z01G/system

inlist() { grep -qx -- "-\?$1" "$L"; }

echo "=== 原廠 /system/etc/permissions 裡「宣告共用函式庫」的 xml ==="
for f in $K/etc/permissions/*.xml; do
    grep -q '<library ' "$f" || continue
    rel="etc/permissions/$(basename $f)"
    lib=$(sed -n 's/.*<library name="\([^"]*\)".*file="\([^"]*\)".*/\1 -> \2/p' "$f" | head -1)
    if inlist "$rel"; then st="[收]"; else st="[漏]"; fi
    # 我們建出來的有沒有（AOSP 自己可能也會裝同名檔）
    [ -e "$O/$rel" ] && built="已安裝" || built="不在 image"
    printf "  %s %-52s %-10s %s\n" "$st" "$(basename $f)" "$built" "$lib"
done

echo
echo "=== 原廠 /system/framework 的 jar（排除 AOSP 自己會編的）==="
for f in $K/framework/*.jar; do
    rel="framework/$(basename $f)"
    inlist "$rel" && continue
    [ -e "$O/$rel" ] && continue          # AOSP 自己有同名的就不算漏
    printf "  [漏] %s\n" "$rel"
done
