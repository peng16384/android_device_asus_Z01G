#!/bin/bash
# 找出「已安裝的 permissions xml 宣告了共用函式庫，但那個 jar 不在 image 裡」的情形。
#
# 這種懸空宣告的後果：任何 <uses-library> 那個名字的 app 一啟動就
#   java.lang.NoClassDefFoundError / ClassNotFoundException
# 實例：SmartcardService.apk 收了（在 vendor/app），
# 但 org.simalliance.openmobileapi.jar 與它的 xml 都在 /system 側，
# 而 31_build_blob_list.py 對 system 側只沿用早期人工清單 -> 兩個都漏 ->
# 開機後跳「SmartcardService keeps stopping」。
O=$HOME/lineage-16.0/out/target/product/Z01G/system
K=/mnt/zs_system

echo "=== 已安裝的 xml 宣告、但檔案不存在的函式庫 ==="
for d in $O/etc/permissions $O/vendor/etc/permissions; do
    [ -d "$d" ] || continue
    for f in $d/*.xml; do
        [ -e "$f" ] || continue
        # <library name="X" file="Y" />，可能跨行
        tr '\n' ' ' < "$f" | grep -oE '<library[^>]*>' | while read -r tag; do
            name=$(echo "$tag" | sed -n 's/.*name="\([^"]*\)".*/\1/p')
            file=$(echo "$tag" | sed -n 's/.*file="\([^"]*\)".*/\1/p')
            [ -n "$file" ] || continue
            # file 是 /system/... 之類的絕對路徑
            real="$O${file#/system}"
            case "$file" in /vendor/*) real="$O/vendor${file#/vendor}";; esac
            if [ ! -e "$real" ]; then
                orig="$K${file#/system}"
                case "$file" in /vendor/*) orig="$K/vendor${file#/vendor}";; esac
                [ -e "$orig" ] && src="原廠有，可補" || src="原廠也沒有"
                printf "  %-42s %-46s %s\n" "$(basename $f)" "$file" "$src"
            fi
        done
    done
done
