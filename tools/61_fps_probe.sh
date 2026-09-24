#!/bin/bash
O=$HOME/lineage-16.0/out/target/product/Z01G/system
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

check() {
    local f="$1"
    [ -e "$f" ] || { echo "  $f 不存在"; return; }
    nm -D --undefined-only "$f" 2>/dev/null | awk '{print $NF}' | sort -u > "$T/need"
    : > "$T/have"
    for l in $(readelf -d "$f" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
        for d in $O/lib64 $O/vendor/lib64 $O/vendor/lib64/hw $O/lib $O/vendor/lib $O/vendor/lib/hw; do
            if [ -f "$d/$l" ]; then nm -D --defined-only "$d/$l" 2>/dev/null | awk '{print $NF}' >> "$T/have"; break; fi
        done
    done
    sort -u "$T/have" -o "$T/have"
    local miss; miss=$(comm -23 "$T/need" "$T/have" | grep -v '^$')
    local n; n=$(echo "$miss" | grep -c .)
    printf "  %-52s 需要 %4s 個，缺 %s 個\n" "$(basename $f)" "$(wc -l < $T/need)" "$n"
    [ "$n" -gt 0 ] && echo "$miss" | head -5 | while read -r s; do
        printf "      %s\n          %s\n" "$s" "$(c++filt "$s" 2>/dev/null)"
    done
}

echo "=== 指紋 HAL 這條鏈能不能連起來 ==="
check "$O/vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-service"
check "$O/vendor/lib64/hw/fingerprint.gx5206.so"
check "$O/vendor/lib64/hw/fingerprint.gx5216.so"
check "$O/vendor/lib64/hw/gxfingerprint.default.so"
