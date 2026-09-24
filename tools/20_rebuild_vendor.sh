#!/usr/bin/env bash
# 改完 proprietary-files.txt 之後，重新產生 vendor 並驗證 build graph
#
#   wsl -- bash $DEVICE_PATH/tools/20_rebuild_vendor.sh
#
# 迭代流程就是這支：
#   1. 重新產生 proprietary-files.txt（tools/12）
#   2. rsync device tree 進 AOSP（tools/16）
#   3. 重跑 setup-makefiles.sh 產生 vendor mk
#   4. m nothing 驗證
#
# 注意：不能開 set -u —— envsetup.sh 的函式會踩到未設定變數。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

# ############################################################################
# 2026-09-23：這支已被 tools/42_refresh_blobs.sh 取代，不要再用。
#
# 下面第 1 步呼叫的 tools/12_clean_proprietary_list.py 來源是早期那份
# 878 條的 proprietary-files-draft.txt，會把現行 tools/31_build_blob_list.py
# 產生的 3600+ 條 proprietary-files.txt **直接蓋掉**，而且蓋掉之後編譯照樣
# 會過，只是開機起來沒聲音 / 沒相機 —— 正是 2026-09-23 花一整天查的那類問題。
# ############################################################################
echo "!!! 這支已停用，請改用 tools/42_refresh_blobs.sh" >&2
echo "    （它呼叫的 tools/12 會用舊草稿蓋掉 tools/31 產生的清單）" >&2
exit 1


PROJ=$DEVICE_PATH
SRC="$HOME/lineage-16.0"

echo "############ 1. 重新產生 proprietary-files.txt ############"
python3 "$PROJ/tools/12_clean_proprietary_list.py" 2>&1 | grep -E "保留|剔除|草稿" | sed 's/^/  /'

echo
echo "############ 2. rsync device tree ############"
bash "$PROJ/tools/16_place_trees.sh" 2>&1 | grep -E "個檔案|已存在|\[有\]|\[缺\]" | sed 's/^/  /'

echo
echo "############ 3. setup-makefiles.sh ############"
( cd "$SRC/device/asus/Z01G" && ./setup-makefiles.sh 2>&1 | tail -3 | sed 's/^/  /' )
echo "  PRODUCT_PACKAGES 模組數：$(grep -cP '^LOCAL_MODULE := ' "$SRC/vendor/asus/Z01G/Android.mk")"

echo
echo "############ 4. m nothing ############"
bash "$PROJ/tools/18_check_buildgraph.sh" 2>&1 | grep -vE "^\[[0-9]+/[0-9]+\] including"
