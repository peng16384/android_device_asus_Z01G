#!/bin/bash
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

O=$HOME/lineage-16.0/out/target/product/Z01G/system
echo "=== shim 有沒有編出來 ==="
ls -la "$O/lib/libshim_keymaster.so" "$O/lib64/libshim_keymaster.so" 2>&1
echo "=== 它匯出的符號（應該是 Oreo 版的 mangled name）==="
for b in lib lib64; do
    [ -f "$O/$b/libshim_keymaster.so" ] && \
      nm -D --defined-only "$O/$b/libshim_keymaster.so" | grep copy_size | sed "s/^/  $b  /"
done
echo
echo "=== linker 裡有沒有把我們的設定編進去 ==="
for l in linker linker64; do
    n=$(strings "$O/bin/$l" 2>/dev/null | grep -c 'libshim_keymaster')
    echo "  bin/$l  命中 $n"
    strings "$O/bin/$l" 2>/dev/null | grep 'libkeymaster1.so|' | sed 's/^/    /'
done
echo
echo "=== 遞迴連結檢查（指紋那條鏈）==="
python3 $DEVICE_PATH/tools/66_link_check.py \
    vendor/bin/gxFpDaemon vendor/lib64/hw/fingerprint.gx5206.so 2>&1 | grep -v sanitizer
