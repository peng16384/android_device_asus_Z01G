#!/bin/bash
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

F=$DEVICE_PATH/stock_ramdisk/init.asus.rc
echo "=== 指紋相關的 service 定義與觸發條件 ==="
awk '/^service (gx_fpd|fpseek|fpservice|fpver|fplog)/,/^$/' "$F"
echo
echo "=== 提到 gx_fpd / fingerprint 的 on 區塊 ==="
grep -n -B4 -A6 'gx_fpd\|ro.hardware.fingerprint' "$F" | head -60
echo
echo "=== 前 60 行（裝置節點權限在哪個觸發點）==="
sed -n '20,50p' "$F"
