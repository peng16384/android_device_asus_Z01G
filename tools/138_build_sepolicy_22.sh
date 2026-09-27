#!/usr/bin/env bash
#
# 22.2：只編 SELinux 政策（含 neverallow 與 sepolicy tests），幾分鐘內知道能不能過，再跑完整編譯
#
#   bash device/asus/Z01G/tools/138_build_sepolicy_22.sh
#
# ⚠ 16.0 的教訓：只編 policy（m sepolicy）不會跑 sepolicy_tests —— 像「/data 底下的型別要帶
#   core_data_file_type」那種檢查要完整編譯才看得到。這裡把 tests 一起編。
set -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄
cd "$SRC"

bash "$PROJ/tools/123_place_tree_22.sh" | tail -1
source build/envsetup.sh >/dev/null
breakfast Z01G >/dev/null || { echo "!!! breakfast 失敗"; exit 1; }

start=$(date +%s)
m selinux_policy sepolicy_tests > out/sepolicy.log 2>&1
rc=$?
echo "  耗時 $(( $(date +%s) - start )) 秒，rc=$rc（log：$SRC/out/sepolicy.log）"
if [ $rc -ne 0 ]; then
    grep -nE "error|Error|neverallow|FAILED|violat|unknown type|The following" out/sepolicy.log | grep -v "^.*warning" | head -40
fi
exit $rc
