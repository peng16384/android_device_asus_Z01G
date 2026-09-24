#!/usr/bin/env bash
# 改完 tools/31_build_blob_list.py 的排除清單之後，重新產生 vendor/ 並驗證。
#
#   wsl -u root -- bash $DEVICE_PATH/tools/42_refresh_blobs.sh
#
# （20_rebuild_vendor.sh 是舊的，呼叫的是已被取代的 tools/12。）
#
# extract_utils.sh 的 setup_vendor() 會先 rm -rf vendor/asus/Z01G/proprietary，
# 所以被移出清單的 blob 會真的消失，不會殘留上一輪的檔案。
# 建置身分與 WSL distro：需要時用環境變數覆蓋
#   BUILD_USER=alice WSL_DISTRO=ubuntu2004 bash tools/xxx.sh
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

BUILD_USER="${BUILD_USER:-${SUDO_USER:-$(id -un)}}"

set -o pipefail

PROJ=$DEVICE_PATH
USER_HOME=$HOME
SRC="$USER_HOME/lineage-16.0"

run_as_user() { sudo -u "$BUILD_USER" -H bash -c "$1"; }

echo "############ 0. 確認 system.img 有掛載 ############"
# ⚠ tools/31 在 /mnt/zs_system 沒掛載時只會印一行訊息就結束（exit 0），
#   而這支腳本以前沒有檢查，會**用舊清單繼續往下抽 blob**，
#   結果是「改了排除清單卻完全沒生效」而且沒有任何錯誤訊息。
#   2026-09-24 實測踩到：移除三支當機的 QTI App 之後，產生的清單
#   與 git HEAD 一模一樣，查了半天才發現是這裡。
if ! mountpoint -q /mnt/zs_system; then
  echo "  /mnt/zs_system 沒掛載，先掛上..."
  mkdir -p /mnt/zs_system
  mount -o ro,loop "$PROJ/work/images/system.img" /mnt/zs_system || {
    echo "!!! 掛載失敗，中止"; exit 1; }
fi
echo "  OK（$(ls /mnt/zs_system | wc -l) 個頂層項目）"

echo
echo "############ 1. 產生 proprietary-files.txt ############"
python3 "$PROJ/tools/31_build_blob_list.py" 2>&1 | tail -20 | sed 's/^/  /'
# ⚠ 一定要檢查：清單沒重新產生的話，後面抽出來的是舊的。
if ! grep -q "^# 共 " "$DEVICE_PATH/proprietary-files.txt"; then
  echo "!!! 清單看起來沒有重新產生，中止"; exit 1
fi

echo
echo "############ 2. rsync device tree 進 AOSP ############"
run_as_user "bash $PROJ/tools/16_place_trees.sh" 2>&1 | grep -E "個檔案|已存在|\[有\]|\[缺\]" | sed 's/^/  /'

echo
echo "############ 3. 抽 blobs（會先清空 proprietary/）############"
"$SRC/device/asus/Z01G/extract-from-image.sh" 2>&1 | tail -6 | sed 's/^/  /'
chown -R "$BUILD_USER:$BUILD_USER" "$SRC/vendor/asus/Z01G" 2>/dev/null

echo
echo "############ 4. 檢查有沒有抽漏 ############"
bash "$PROJ/tools/33_check_extract.sh" 2>&1 | head -12 | sed 's/^/  /'

echo
echo "############ 5. 確認關鍵檔案的去留 ############"
P="$SRC/vendor/asus/Z01G/proprietary"
for f in vendor/lib64/hw/audio.primary.msm8998.so \
         vendor/lib/hw/audio.primary.msm8998.so \
         vendor/bin/hw/android.hardware.audio@2.0-service \
         vendor/lib64/hw/android.hardware.audio@2.0-impl.so \
         vendor/bin/hw/android.hardware.wifi@1.0-service \
         vendor/bin/hw/android.hardware.media.omx@1.0-service \
         vendor/bin/hw/android.hardware.keymaster@3.0-service \
         vendor/bin/hw/vendor.qti.gnss@1.0-service \
         vendor/bin/hw/vendor.nxp.hardware.nfc@1.0-service \
         bin/wfdservice; do
    if [ -e "$P/$f" ]; then echo "  [收] $f"; else echo "  [排] $f"; fi
done
