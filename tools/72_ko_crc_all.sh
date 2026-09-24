#!/bin/bash
# 對所有原廠 .ko 跑 CRC 比對，判斷「CRC 不合」是個別模組還是系統性的。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

P=$HOME/lineage-16.0/vendor/asus/Z01G/proprietary/vendor/lib/modules
K=/mnt/zs_system/lib/modules
for f in "$P"/*.ko "$K"/*.ko; do
    [ -e "$f" ] || continue
    printf '%-24s ' "$(basename $f)"
    python3 $DEVICE_PATH/tools/71_ko_crc_check.py "$f" 2>/dev/null |
        sed -n 's/^  相符 \(.*\)$/\1/p'
done
