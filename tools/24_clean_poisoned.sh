#!/usr/bin/env bash
# 清掉被「python 指向 python3」那次編譯污染的中間產物
#
#   wsl -- bash $DEVICE_PATH/tools/24_clean_poisoned.sh
#
# 症狀：
#   FAILED: .../apache-xml_intermediates/dex-hiddenapi/classes.dex
#   hiddenapi E ... No DEX files specified
#
# 原因：
#   AOSP 用 build/make/tools/normalize_path.py 產生 java-source-list：
#       ... | normalize_path.py > java-source-list
#   python3 跑這支 Python 2 腳本會 SyntaxError，但 shell 的重導向**已經把檔案建出來**
#   （0 bytes），而整條規則的結束碼被後面的命令蓋掉，ninja 因此認為這個目標完成了。
#   結果：classes.jar 從零個原始檔編出來（18 KB），dex 階段沒有輸入，
#         hiddenapi 才在下一步報「No DEX files specified」。
#
#   換成 python2 之後 ninja 不會重做這些目標，因為它們「看起來是最新的」。
#
# 這就是為什麼錯誤會出現在跟真正原因差很遠的地方，而且改對環境後仍然復發。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

SRC="$HOME/lineage-16.0"
OUT="$SRC/out"

echo "=== 找 0 byte 的 java-source-list ==="
mapfile -t BAD < <(find "$OUT" -name 'java-source-list' -size 0 2>/dev/null)
echo "  找到 ${#BAD[@]} 個"
if [ "${#BAD[@]}" -eq 0 ]; then
    echo "  沒有被污染的產物"
    exit 0
fi

echo
echo "=== 移除對應的 _intermediates 目錄（ninja 會重新產生）==="
for f in "${BAD[@]}"; do
    d=$(dirname "$f")
    # 一併把 classes.jar / dex 的殘留帶走
    printf '  %-70s %s\n' "$(basename "$(dirname "$d")")/$(basename "$d")" \
        "$(du -sh "$d" 2>/dev/null | cut -f1)"
    rm -rf "$d"
done

echo
echo "=== 確認 ==="
echo "  剩餘 0 byte java-source-list: $(find "$OUT" -name 'java-source-list' -size 0 2>/dev/null | wc -l)"
echo "  正常的 java-source-list:      $(find "$OUT" -name 'java-source-list' ! -size 0 2>/dev/null | wc -l)"
echo
echo "完成。重跑 tools/22_build.sh"
