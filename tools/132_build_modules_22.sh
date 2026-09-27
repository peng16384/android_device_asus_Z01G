#!/usr/bin/env bash
#
# 22.2：只編指定的模組（驗證 device tree 自己的 C++ / 設定檔，不用等完整編譯）
#
#   bash device/asus/Z01G/tools/132_build_modules_22.sh <模組> [模組...]
#
# 例：android.hardware.vibrator-service.z01g
# log：~/lineage-22.2/out/modules.log
# build graph（tools/124）只檢查模組定義，不會編 C++ —— 自己寫的程式要用這支實際編一次。
set -o pipefail

[ $# -ge 1 ] || { echo "用法：$0 <模組> [模組...]"; exit 2; }
SRC=${SRC:-$HOME/lineage-22.2}
cd "$SRC"
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=$HOME/.ccache
source build/envsetup.sh >/dev/null
breakfast Z01G >/dev/null || { echo "!!! breakfast 失敗"; exit 1; }
mkdir -p out
date '+  開始 %T'
m "$@" > out/modules.log 2>&1
rc=$?
date '+  結束 %T'
echo "  rc=$rc（log：$SRC/out/modules.log）"
if [ $rc -ne 0 ]; then
    echo "=== 錯誤 ==="
    grep -nE "error:|FAILED|ninja: error" out/modules.log | head -40
else
    for m in "$@"; do
        find out/target/product/Z01G -path '*/obj*' -prune -o -name "$m*" -newer out/modules.log -print 2>/dev/null | head -3
    done
fi
exit $rc
