#!/usr/bin/env bash
#
# 22.2：放 device tree、抽出兩個 vendor 模組（在 lineage22 distro 內）
#
#   bash device/asus/Z01G/tools/127_extract_22.sh
#
# 前置：tools/125（清單）、tools/126（ASUS 的 dump）
#   vendor/asus/Z01G          <- ~/asus/dump                                         （ASUS 1911.117）
#   vendor/asus/Z01G-oneplus  <- ~/ref/proprietary_vendor_oneplus_msm8998-common/proprietary（OnePlus 5）
set -e -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄
ASUS_DUMP=$HOME/asus/dump
OP_SRC=$HOME/ref/proprietary_vendor_oneplus_msm8998-common/proprietary

bash "$PROJ/tools/123_place_tree_22.sh"
cd "$SRC/device/asus/Z01G"

echo "=== ASUS -> vendor/asus/Z01G ==="
./extract-files.py "$ASUS_DUMP" 2>&1 | tail -25
echo "=== OnePlus -> vendor/asus/Z01G-oneplus ==="
./extract-files.py --oneplus "$OP_SRC" 2>&1 | tail -25

for v in Z01G Z01G-oneplus; do
    d="$SRC/vendor/asus/$v"
    printf '  %-14s %5d 個檔  %s\n' "$v" "$(find "$d/proprietary" -type f 2>/dev/null | wc -l)" "$(du -sh "$d" | cut -f1)"
done
