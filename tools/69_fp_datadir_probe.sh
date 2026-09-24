#!/bin/bash
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

F=$DEVICE_PATH/stock_ramdisk/init.asus.rc
echo "=== init.asus.rc 裡跟指紋有關的 /data 目錄 ==="
grep -nE 'mkdir /data.*(validity|finger|fp|gf)|chown.*(validity|finger|fp|gf)' "$F" -i
echo
echo "=== gxFpDaemon 會用到哪些路徑 ==="
strings /mnt/zs_system/vendor/bin/gxFpDaemon | grep -E '^/(data|persist|vendor)/' | sort -u | head -20
echo
echo "=== fingerprint.gx5206.so 會用到哪些路徑 ==="
strings /mnt/zs_system/vendor/lib64/hw/fingerprint.gx5206.so | grep -E '^/(data|persist|vendor)/' | sort -u | head -20
