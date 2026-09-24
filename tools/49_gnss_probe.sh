#!/bin/bash
O=$HOME/lineage-16.0/out/target/product/Z01G/system
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
IMPL=$O/vendor/lib64/hw/android.hardware.gnss@1.0-impl-qti.so
nm -D --undefined-only "$IMPL" | awk '{print $NF}' | sort -u > $T/need.txt
: > $T/have.txt
for l in $(readelf -d "$IMPL" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
  for d in $O/lib64 $O/vendor/lib64 $O/vendor/lib64/hw; do
    if [ -f "$d/$l" ]; then nm -D --defined-only "$d/$l" 2>/dev/null | awk '{print $NF}' >> $T/have.txt; break; fi
  done
done
sort -u $T/have.txt -o $T/have.txt
miss=$(comm -23 $T/need.txt $T/have.txt | grep -v '^$')
echo "需要 $(wc -l < $T/need.txt) 個符號，其中 $(echo "$miss" | grep -c . ) 個在直接相依的函式庫裡找不到"
echo "$miss" | head -20 | while read -r s; do [ -n "$s" ] && printf "  %s\n      %s\n" "$s" "$(c++filt "$s" 2>/dev/null)"; done
echo
echo "=== 關鍵：有沒有需要那個 Pie 已經不匯出的 toString<GnssNiNotifyFlags> ==="
grep -c 'toStringINS2_15IGnssNiCallback17GnssNiNotifyFlags' $T/need.txt
echo
echo "=== 對照：真正壞掉的 vendor.qti.gnss@1.0_vendor.so 需要它嗎 ==="
nm -D --undefined-only $O/vendor/lib64/vendor.qti.gnss@1.0_vendor.so 2>/dev/null | grep -c 'toStringINS2_15IGnssNiCallback17GnssNiNotifyFlags'
