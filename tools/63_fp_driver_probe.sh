#!/bin/bash
K=/mnt/zs_system
echo "=== 原廠 vendor/ueventd.rc 的 Fingerprint 段落 ==="
sed -n '270,295p' "$K/vendor/ueventd.rc"
echo
echo "=== 整份裡出現 /dev/ 開頭且與指紋/spi 有關的 ==="
grep -nE '^/dev/(goodix|gf|fp|spi|validity|qseecom|qbt)' "$K/vendor/ueventd.rc"
