#!/usr/bin/env bash
#
# 22.2：完整編譯（breakfast Z01G + mka bacon），成品複製回 out/
#
#   bash device/asus/Z01G/tools/133_build_22.sh
#
# 前置：tools/125（清單）-> tools/127（放 device tree + 抽 vendor）。
# log：~/lineage-22.2/out/build.log
# set -o pipefail：管線的結束碼不能被 tail 吃掉（16.0 踩過：以為編好了，zip 根本不存在）
set -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄
DEST=$PROJ/out
cd "$SRC"

bash "$PROJ/tools/123_place_tree_22.sh" | tail -3
bash "$PROJ/tools/136_apply_patches_22.sh" || { echo "!!! patch 套不上"; exit 1; }

export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=$HOME/.ccache
ccache -M 25G >/dev/null
source build/envsetup.sh >/dev/null
breakfast Z01G >/dev/null || { echo "!!! breakfast 失敗"; exit 1; }
echo "  TARGET_PRODUCT=$TARGET_PRODUCT  TARGET_RELEASE=$TARGET_RELEASE  變體=$TARGET_BUILD_VARIANT"

date '+  開始 %F %T'
start=$(date +%s)
# KEEP_GOING=1：遇錯繼續（ninja -k），一輪收齊所有同類錯誤（例如 check_elf 一次只報一個 blob）
mka ${KEEP_GOING:+-k} bacon > out/build.log 2>&1
rc=$?
date '+  結束 %F %T'
echo "  耗時 $(( ($(date +%s) - start) / 60 )) 分鐘，rc=$rc（log：$SRC/out/build.log）"

if [ $rc -ne 0 ]; then
    echo "=== 錯誤 ==="
    grep -nE "error:|FAILED:|ninja: error|Error [0-9]+" out/build.log | head -40
    exit $rc
fi

O=out/target/product/Z01G
zip=$(ls -t $O/lineage-22.2-*-Z01G.zip 2>/dev/null | head -1)
[ -n "$zip" ] || { echo "!!! rc=0 但找不到 zip"; exit 1; }
mkdir -p "$DEST"
cp -v "$zip" $O/boot.img $O/recovery.img "$DEST/"
( cd "$DEST" && sha256sum "$(basename "$zip")" boot.img recovery.img > SHA256SUMS && cat SHA256SUMS )
ls -la "$DEST"
printf '  boot.img %s bytes（分割 33554432）  recovery.img %s bytes\n' \
    "$(stat -c %s $O/boot.img)" "$(stat -c %s $O/recovery.img)"
printf '  system.img %s bytes（分割 5368709120）\n' "$(stat -c %s $O/system.img)"
