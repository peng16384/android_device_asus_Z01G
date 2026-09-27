#!/usr/bin/env bash
#
# 把 device tree 放進 22.2 原始碼樹（vendor 由 tools/127 抽取產生）
#
#   bash device/asus/Z01G/tools/123_place_tree_22.sh
#
# 可重跑（rsync --delete）。
#
# - device/asus/Z01G      <- device tree 根目錄（git 版控；_dumpling/ 不放）
# - kernel/asus/msm8998   要自己 clone（見 docs/building.md），這裡只檢查
#
# 歷史：第一輪 build graph曾暫時借整棵 OnePlus vendor tree 放在
# vendor/oneplus/msm8998-common、並在 vendor/asus/Z01G 放轉接檔（剔除依賴 hardware/oneplus 的
# 模組用 tools/123_drop_vendor_modules.py）。正式 blob 清單之後不再需要，這裡把它們清掉。
set -e -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄

echo "=== device/asus/Z01G ==="
mkdir -p "$SRC/device/asus"
# 本來就 clone 在 device/asus/Z01G 的話不用放
[ "$(realpath "$PROJ")" = "$(realpath -m "$SRC/device/asus/Z01G")" ] ||
    rsync -a --delete --exclude .git "$PROJ/" "$SRC/device/asus/Z01G/"
chmod +x "$SRC/device/asus/Z01G/extract-files.py" "$SRC/device/asus/Z01G/setup-makefiles.py"
echo "  $(find "$SRC/device/asus/Z01G" -type f | wc -l) 個檔案"

echo "=== kernel/asus/msm8998 ==="
git -C "$SRC/kernel/asus/msm8998" log --oneline -1

echo "=== 清掉第一輪的暫時轉接 ==="
for d in "$SRC/vendor/oneplus/msm8998-common"; do
    [ -d "$d" ] && { rm -rf "$d"; echo "  刪 ${d#$SRC/}"; } || true
done
rmdir "$SRC/vendor/oneplus" 2>/dev/null || true
if [ -f "$SRC/vendor/asus/Z01G/Z01G-vendor.mk" ] && grep -q '暫時：第一輪' "$SRC/vendor/asus/Z01G/Z01G-vendor.mk"; then
    rm -rf "$SRC/vendor/asus/Z01G"; echo "  刪 vendor/asus/Z01G（暫時的轉接）"
fi
