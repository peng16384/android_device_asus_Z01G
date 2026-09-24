#!/usr/bin/env bash
#
# 在 TWRP 裡刷 Open GApps，並補上 Open GApps 自己漏掉的 privapp 白名單條目。
#
#   bash tools/92_flash_gapps.sh
#
# ############ 為什麼需要補白名單 ############
# Android 9 的 ro.control_privapp_permissions=enforce 要求每個 priv-app 的
# 特權權限都要在白名單裡，缺一條 system_server 就丟 IllegalStateException：
#
#   java.lang.IllegalStateException: Signature|privileged permissions not in
#   privapp-permissions whitelist: {com.google.android.apps.wellbeing:
#   android.permission.MODIFY_DAY_NIGHT_MODE}
#       at PermissionManagerService.systemReady(PermissionManagerService.java:2123)
#
# 然後無限重啟（實測 14 分鐘內 25 次，卡在 StartPackageManagerService）。
#
# Open GApps 20220503 裝的 privapp-permissions-google.xml 裡，wellbeing 的
# 區塊少了 MODIFY_DAY_NIGHT_MODE（同一個檔案裡另外三個套件都有這條，
# 所以平台認得這個權限名稱，純粹是他們漏寫）。
#
# ⚠ 刻意**不**用「把 ro.control_privapp_permissions 改成 log」的做法 ——
#   那等於關掉整個特權權限控管，影響所有 priv-app。這裡只針對單一套件的
#   單一權限做最小修補。
# ###########################################
#
# ############ 什麼時候要跑 ############
# 每次重刷 ROM zip 之後。ROM 會覆蓋整個 /system，GApps 與這個修補都會消失。
# 正確順序：
#   1. tools/35_flash_via_twrp.sh   刷 ROM
#   2. bash tools/92_flash_gapps.sh 刷 GApps + 補白名單
#   3. adb reboot
#
# 首次安裝 GApps 還需要清 /data（LineageOS 的硬性要求：ROM 開機過之後
# 才補 GApps 會讓 Play 服務不斷崩潰）。但這台的 TWRP 掛不動我們的 /data
# （ext4 的 quota feature，它的 kernel 沒有 CONFIG_QUOTA），
# twrp wipe data 會靜靜失敗，要改用：
#   adb shell make_ext4fs /dev/block/bootdevice/by-name/userdata
# ⚠ 不要加 -l，給錯大小會做出比分割區小的檔案系統。
# #####################################
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

ADB="${ADB:-adb}"
SRC="${SRC:-$DEVICE_PATH/docs/gapps}"
ZIP="${ZIP:-open_gapps-arm64-9.0-nano-20220503.zip}"
SD=/external_sd
WL=/system/etc/permissions/privapp-permissions-google.xml
PKG='com.google.android.apps.wellbeing'
PERM='android.permission.MODIFY_DAY_NIGHT_MODE'

adb_() { MSYS_NO_PATHCONV=1 "$ADB" "$@"; }

echo "=== 手機狀態 ==="
STATE=$(adb_ get-state 2>/dev/null | tr -d '\r')
[ "$STATE" = "recovery" ] || { echo "!!! 不在 recovery（目前 $STATE）" >&2; exit 1; }
echo "  OK"

echo
echo "=== 推送並比對 ==="
[ -f "$SRC/$ZIP" ] || { echo "!!! 找不到 $SRC/$ZIP" >&2; exit 1; }
LOCAL=$(md5sum "$SRC/$ZIP" | cut -d' ' -f1)
echo "  PC   md5 $LOCAL"
if [ "$(adb_ shell "md5sum $SD/$ZIP 2>/dev/null" | tr -d '\r' | cut -d' ' -f1)" != "$LOCAL" ]; then
    adb_ push "$SRC/$ZIP" "$SD/" 2>&1 | tail -1 | sed 's/^/  /'
fi
PHONE=$(adb_ shell "md5sum $SD/$ZIP" 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
echo "  手機 md5 $PHONE"
[ "$LOCAL" = "$PHONE" ] || { echo "  !!! 不一致，中止" >&2; exit 1; }
echo "  >>> 一致"

echo
echo "=== 安裝 GApps ==="
adb_ shell "setprop ro.product.device Z01G; twrp install $SD/$ZIP" 2>&1 | tail -6 | sed 's/^/  /'
adb_ shell 'grep -aE "Installation complete|Updater process ended|ERROR|aborted" /tmp/recovery.log | tail -4' 2>&1 | sed 's/^/  /'

echo
echo "=== 補上 Open GApps 漏掉的白名單條目 ==="
adb_ shell "
mount /system 2>/dev/null
mount -o rw,remount /system 2>/dev/null
[ -f $WL ] || { echo '  !!! 找不到 $WL'; exit 1; }
if grep -aA30 'package=\"$PKG\"' $WL | grep -aq '$PERM'; then
    echo '  已經有了，不需要修補'
else
    cp $WL $WL.orig
    sed -i '/<privapp-permissions package=\"$PKG\">/a\\        <permission name=\"$PERM\" />' $WL
    echo '  已插入（備份在 $WL.orig）'
fi
echo '  --- 確認 ---'
grep -aA2 'package=\"$PKG\"' $WL | head -3
sync
" 2>&1 | sed 's/^/  /'

echo
echo "完成。重開機："
echo "  $ADB reboot"
echo
echo "首次開機會為所有 Google 套件跑 dexopt，在 835 上可能要 20-40 分鐘"
echo "（Velvet.apk 也就是 Google App 最久）。確認沒卡住的方法："
echo "  adb shell 'logcat -d -b crash | grep -c OutOfMemory'        應為 0"
echo "  adb shell 'ps -A | grep -c dex2oat'                          應 >= 1"
echo "  adb shell 'logcat -d -b main | grep -c StartPackageManagerService'"
echo "        若持續增加 = system_server 在重啟迴圈，不是在編譯"
