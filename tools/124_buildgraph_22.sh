#!/usr/bin/env bash
#
# 22.2：breakfast + m nothing（只產生 build graph，不編譯）
#
#   bash device/asus/Z01G/tools/124_buildgraph_22.sh
#
# log：~/lineage-22.2/out/buildgraph.log
# 16.0 的經驗（tools/18）：先過 build graph 再編，錯誤會少很多輪。
# set -o pipefail：管線的結束碼不能被 tail 吃掉（16.0 踩過，見 CLAUDE.md）
set -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
cd "$SRC"
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=$HOME/.ccache
source build/envsetup.sh >/dev/null
breakfast Z01G || { echo "!!! breakfast 失敗"; exit 1; }
echo "  TARGET_PRODUCT=$TARGET_PRODUCT  TARGET_RELEASE=$TARGET_RELEASE  變體=$TARGET_BUILD_VARIANT"
mkdir -p out
date '+  開始 %T'
m nothing > out/buildgraph.log 2>&1
rc=$?
date '+  結束 %T'
echo "  rc=$rc（log：$SRC/out/buildgraph.log）"
if [ $rc -ne 0 ]; then
    echo "=== 錯誤 ==="
    grep -nE "error:|Error|FAILED|ninja: error|failed to|dependencies on|is not defined|cannot find|missing" out/buildgraph.log | head -40
fi
exit $rc
