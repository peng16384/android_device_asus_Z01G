#!/usr/bin/env bash
# 把 LineageOS zip 推到外接 SD 卡，並在手機端驗證 sha256
#
#   ADB=/path/to/adb bash tools/27_push_zip_to_sd.sh
#
# 為什麼放 SD 卡而不是內部儲存：
#   刷 LineageOS 要 Format Data，那會連內部儲存（/data/media）一起清掉。
#   SD 卡是獨立分割，不受影響。
#
# 為什麼不用 adb sideload：
#   這台的 TWRP USB gadget 起不來（Windows 只看到
#   「未知的 USB 裝置（要求裝置描述元失敗）」VID_0000&PID_0002），
#   TWRP 裡完全沒有 adb。所以改成「在 Android 下先把檔案放進 SD 卡」。
#
# sha256 一定要在手機端算過再比對 —— SD 卡傳輸出錯不算罕見，
# 而刷一個壞掉的 zip 產生的症狀會很難和 device tree 的問題區分。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

ADB="${ADB:-adb}"
SRC="${SRC:-$DEVICE_PATH/docs/out}"
ZIP_NAME="${ZIP_NAME:-lineage-16.0-20260922-UNOFFICIAL-Z01G.zip}"
SD=/storage/DCC7-100D

adb_() { MSYS_NO_PATHCONV=1 "$ADB" "$@"; }

[ -f "$SRC/$ZIP_NAME" ] || { echo "!!! 找不到 $SRC/$ZIP_NAME" >&2; exit 1; }

echo "=== 來源 ==="
ls -lh "$SRC/$ZIP_NAME" | sed 's/^/  /'
LOCAL_SHA=$(sha256sum "$SRC/$ZIP_NAME" | cut -d' ' -f1)
echo "  sha256 $LOCAL_SHA"

echo
echo "=== SD 卡 ==="
adb_ shell "df -h $SD" 2>&1 | tail -1 | sed 's/^/  /'

echo
echo "=== 推送（666 MB，約 1 分鐘）==="
adb_ push "$SRC/$ZIP_NAME" "$SD/" 2>&1 | tail -1 | sed 's/^/  /'

echo
echo "=== 手機端驗證 ==="
PHONE_SHA=$(adb_ shell "sha256sum $SD/$ZIP_NAME" 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
echo "  PC   $LOCAL_SHA"
echo "  手機 $PHONE_SHA"
if [ "$LOCAL_SHA" = "$PHONE_SHA" ]; then
    echo "  >>> 一致，可以刷"
else
    echo "  !!! 不一致 —— 不要刷，重推一次" >&2
    exit 1
fi

echo
echo "=== SD 卡上的檔案 ==="
adb_ shell "ls -l $SD/$ZIP_NAME" 2>&1 | sed 's/^/  /'
