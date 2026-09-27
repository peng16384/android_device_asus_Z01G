#!/usr/bin/env bash
#
# 22.2：vendor 模組的 PRODUCT_COPY_FILES 與 soong 安裝的檔案，路徑相撞的（在 lineage22 distro 內）
#
#   bash device/asus/Z01G/tools/130_copy_vs_soong_22.sh
#
# 前置：tools/124 至少跑過一次（要有 out/soong/installs-lineage_Z01G.mk）。
# Kati 遇到這種相撞一次只報一個（overriding commands for target ...），每輪 2 分鐘；這支一次列齊。
set -e -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
cd "$SRC"
INST=out/soong/installs-lineage_Z01G.mk
[ -s "$INST" ] || { echo "沒有 $INST —— 先跑 tools/124"; exit 1; }

tmp=$(mktemp -d)
# soong 會安裝的：installs-*.mk 的 target 行
grep -oE '^out/target/product/Z01G/[^ :]+' "$INST" | sed 's|^out/target/product/Z01G/||' | sort -u > "$tmp/soong"
# vendor 模組的 PRODUCT_COPY_FILES 目的地（$(TARGET_COPY_OUT_VENDOR) = system/vendor）
for mk in vendor/asus/Z01G/Z01G-vendor.mk vendor/asus/Z01G-oneplus/Z01G-oneplus-vendor.mk; do
    grep -oE ':\$\(TARGET_COPY_OUT_[A-Z_]+\)/[^ \\]+' "$mk" |
        sed -E 's|^:\$\(TARGET_COPY_OUT_VENDOR\)/|system/vendor/|; s|^:\$\(TARGET_COPY_OUT_SYSTEM\)/|system/|;
                s|^:\$\(TARGET_COPY_OUT_SYSTEM_EXT\)/|system/system_ext/|; s|^:\$\(TARGET_COPY_OUT_PRODUCT\)/|system/product/|' |
        sed "s|\$| $(dirname "$mk")|"
done | sort -u > "$tmp/copy"

awk 'NR==FNR {s[$1]=1; next} ($1 in s)' "$tmp/soong" "$tmp/copy" > "$tmp/hit"
if [ -s "$tmp/hit" ]; then
    echo "PRODUCT_COPY_FILES 與 soong 安裝相撞：$(wc -l < "$tmp/hit") 個"
    sed 's/^/  /' "$tmp/hit"
else
    echo "沒有相撞"
fi
rm -rf "$tmp"
