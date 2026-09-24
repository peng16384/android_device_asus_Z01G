#!/usr/bin/env bash
# 用 adb 驅動 TWRP 完成刷機（手機需停在 TWRP 且 adb 可用）
#
#   ADB=/path/to/adb bash tools/35_flash_via_twrp.sh
#
# 前提：
#   - /data 已經 Format 過（不能是原廠的 FDE 加密狀態，LineageOS 解不開）
#   - 外接 SD 卡有掛在 /external_sd
#
# zip 要先用 tools/28_widen_device_assert.sh 放寬裝置檢查：這台的 TWRP
# 沒有設 ro.product.device / ro.build.product，原本的檢查必定 E3004。
#
# 這支以前會在安裝前 setprop ro.product.device Z01G 來繞過。已經拿掉 ——
# 放寬之後不需要，而且留著會讓「放寬的檢查本身壞了」永遠測不出來。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

ADB="${ADB:-adb}"
SRC="${SRC:-$DEVICE_PATH/docs/out}"
ZIP="${ZIP:-lineage-16.0-20260922-UNOFFICIAL-Z01G.zip}"
SD=/external_sd

adb_() { MSYS_NO_PATHCONV=1 "$ADB" "$@"; }

echo "=== 手機狀態 ==="
adb_ devices -l | sed 's/^/  /'
STATE=$(adb_ get-state 2>/dev/null | tr -d '\r')
[ "$STATE" = "recovery" ] || { echo "!!! 不在 recovery（目前 $STATE）" >&2; exit 1; }

echo
echo "=== /data 必須已 Format（應直接掛 sda20 而非 dm-0）==="
adb_ shell 'df -h /data 2>&1 | tail -1' | sed 's/^/  /'
if adb_ shell 'df /data 2>&1' | grep -q 'dm-0'; then
    echo "  !!! /data 仍掛在 dm-0（還是加密狀態）—— 先做 Format Data" >&2
    exit 1
fi

echo
echo "=== 推送 zip ==="
LOCAL_SHA=$(sha256sum "$SRC/$ZIP" | cut -d' ' -f1)
echo "  PC sha256 $LOCAL_SHA"
adb_ push "$SRC/$ZIP" "$SD/" 2>&1 | tail -1 | sed 's/^/  /'
PHONE_SHA=$(adb_ shell "sha256sum $SD/$ZIP" 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
echo "  手機 sha256 $PHONE_SHA"
[ "$LOCAL_SHA" = "$PHONE_SHA" ] || { echo "  !!! 不一致，中止" >&2; exit 1; }
echo "  >>> 一致"

echo
echo "=== 清空 system / cache / dalvik（不碰 data 與 SD 卡）==="
for p in system cache dalvik; do
    echo "  --- wipe $p"
    adb_ shell "twrp wipe $p" 2>&1 | tail -2 | sed 's/^/      /'
done

echo
echo "=== 安裝 ==="
adb_ shell "twrp install $SD/$ZIP" 2>&1 | tail -20 | sed 's/^/  /'

echo
echo "=== 從 recovery.log 確認結果 ==="
adb_ shell 'grep -aE "Installing zip|script succeeded|Updating partition|ERROR|E3004|E1001|Patching system" /tmp/recovery.log | tail -15' 2>&1 | sed 's/^/  /'

echo
echo "完成。確認上面沒有 ERROR 之後再重開機："
echo "  $ADB reboot"
