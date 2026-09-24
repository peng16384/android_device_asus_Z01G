#!/bin/bash
O=$HOME/lineage-16.0/out/target/product/Z01G/system
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
check() {
    local f="$1"
    [ -e "$f" ] || { echo "  $(basename $f) 不存在"; return; }
    local bits=64; [ "$(od -An -tu1 -j4 -N1 "$f" | tr -d ' ')" = "1" ] && bits=32
    nm -D --undefined-only "$f" 2>/dev/null | awk '{print $NF}' | sort -u > "$T/need"
    : > "$T/have"
    for l in $(readelf -d "$f" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
        if [ "$bits" = 64 ]; then dirs="$O/lib64 $O/vendor/lib64 $O/vendor/lib64/hw";
        else dirs="$O/lib $O/vendor/lib $O/vendor/lib/hw"; fi
        for d in $dirs; do
            if [ -f "$d/$l" ]; then nm -D --defined-only "$d/$l" 2>/dev/null | awk '{print $NF}' >> "$T/have"; break; fi
        done
    done
    sort -u "$T/have" -o "$T/have"
    local miss; miss=$(comm -23 "$T/need" "$T/have" | grep -v '^$')
    local n; n=$(echo "$miss" | grep -c .)
    printf "  %-24s %sbit  需要 %3s 個，缺 %s\n" "$(basename $f)" "$bits" "$(wc -l < $T/need)" "$n"
    [ "$n" -gt 0 ] && echo "$miss" | head -4 | while read -r s; do
        printf "      %s\n          %s\n" "$s" "$(c++filt "$s" 2>/dev/null)"; done
}
echo "=== 指紋 daemon 這條鏈 ==="
check "$O/vendor/bin/gxFpDaemon"
check "$O/vendor/bin/fpseek"
check "$O/vendor/lib64/libfpservice.so"
check "$O/vendor/lib/libfpservice.so"
