#!/usr/bin/env bash
# 把我們自己的樹放進同步好的 LineageOS 原始碼
#
#   device/asus/Z01G      <- $DEVICE_PATH（本 repo 版控中）
#   kernel/asus/msm8998   <- 驗證過的 ASUS GPL kernel（~/zs551kl/kernel/msm-4.4）
#
# 用一般使用者執行：
#   wsl -- bash $DEVICE_PATH/tools/16_place_trees.sh
#
# device tree 用「複製」而不是 symlink：AOSP 的 build 系統對 symlink 到
# /mnt/g（9p）的路徑會很慢，而且 NTFS 不保留權限。
# 改動流程：改 work/ 底下的版控檔 -> 重跑本腳本 -> 重編。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -euo pipefail

SRC="$HOME/lineage-16.0"
PROJ=$DEVICE_PATH
KSRC="$HOME/zs551kl/kernel/msm-4.4"

[ -d "$SRC/.repo" ] || { echo "!!! $SRC 還沒 repo init，先跑 tools/15_repo_sync.sh" >&2; exit 1; }
[ -d "$KSRC" ]      || { echo "!!! 找不到 kernel 原始碼 $KSRC，先跑 tools/01_extract_kernel_src.sh" >&2; exit 1; }

echo "=== device/asus/Z01G ==="
mkdir -p "$SRC/device/asus"
rsync -a --delete \
      --exclude '.git' \
      "$DEVICE_PATH/" "$SRC/device/asus/Z01G/"
chmod +x "$SRC/device/asus/Z01G/"*.sh
echo "  $(find "$SRC/device/asus/Z01G" -type f | wc -l) 個檔案"

echo
echo "=== kernel/asus/msm8998 ==="
if [ -d "$SRC/kernel/asus/msm8998/.git" ]; then
    echo "  已存在，跳過（要更新請自行 rsync 或砍掉重放）"
else
    mkdir -p "$SRC/kernel/asus"
    # kernel 樹 1.2 GB，用 hardlink 複製省空間（同一個 ext4 檔案系統）
    cp -al "$KSRC" "$SRC/kernel/asus/msm8998"
    echo "  已用 hardlink 複製（$(du -sh --si "$SRC/kernel/asus/msm8998" | cut -f1)）"
fi
# 編譯產物不要帶過去
rm -rf "$SRC/kernel/asus/msm8998/out"

echo
echo "=== 檢查相依 ==="
for d in vendor/lineage device/qcom/sepolicy vendor/asus/Z01G; do
    if [ -e "$SRC/$d" ]; then
        echo "  [有]   $d"
    else
        echo "  [缺]   $d"
    fi
done

echo
echo "後續："
echo "  1. 抽 blobs（需 root）："
echo "       sudo IMG=$PROJ/work/images/system.img \\"
echo "            $SRC/device/asus/Z01G/extract-from-image.sh"
echo "  2. 設定編譯環境並試 breakfast："
echo "       cd $SRC && source build/envsetup.sh && breakfast Z01G"
