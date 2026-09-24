#!/usr/bin/env bash
# 刷完之後檢查 Wi-Fi 是否運作。
#
#   bash tools/87_wifi_check.sh          # 只看現況
#   bash tools/87_wifi_check.sh -on      # 順便試著開啟 Wi-Fi
#
# 預期的啟動鏈（qcacld 編成 built-in，不是模組）：
#   1. 開機 -> __initcall_hdd_module_init6 自動執行
#      -> 建立 /sys/kernel/boot_wlan/boot_wlan（__ATTR(boot_wlan, 0220, NULL, wlan_boot_cb)）
#   2. 使用者開 Wi-Fi -> libwifi-hal 寫 1 到那個節點
#      （BoardConfig 的 WIFI_DRIVER_STATE_CTRL_PARAM）
#   3. wlan_boot_cb -> qcacld 向 icnss 註冊 -> 與已就緒的韌體交握 -> wlan0 出現
ADB="${ADB:-adb}"
sh() { MSYS_NO_PATHCONV=1 "$ADB" shell "$@" 2>&1; }
hdr() { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }

hdr "1. 驅動有沒有被編進 kernel 並初始化"
sh 'echo "  boot_wlan sysfs: $(ls -la /sys/kernel/boot_wlan/boot_wlan 2>&1)"
    echo "  wlan 相關 kobject: $(ls /sys/kernel/ 2>/dev/null | grep -i wlan | tr "\n" " ")"'

hdr "2. icnss 狀態"
sh 'for d in /sys/bus/msm_subsys/devices/*; do
        n=$(cat $d/name 2>/dev/null)
        [ "$n" = "wlan" ] || [ "$n" = "adsp" ] && printf "  %-8s %s\n" "$n" "$(cat $d/state 2>/dev/null)"
    done
    dmesg 2>/dev/null | grep -aiE "icnss" | tail -6'

hdr "3. qcacld / hdd 的開機訊息"
sh 'dmesg 2>/dev/null | grep -aiE "wlan|qcacld|hdd|cld" | grep -viE "wlan_pd|ipa_smmu" | tail -15'

hdr "4. 網路介面"
sh 'ls /sys/class/net/ | tr "\n" " "; echo
    ip link show wlan0 2>&1 | head -3'

if [ "${1:-}" = "-on" ]; then
    hdr "5. 試著開啟 Wi-Fi"
    sh 'svc wifi enable; sleep 8; echo "  wifi state: $(settings get global wifi_on)"'
    sh 'ls /sys/class/net/ | grep -i wlan || echo "  還是沒有 wlan 介面"'
    hdr "6. 開啟後的 dmesg"
    sh 'dmesg 2>/dev/null | tail -25'
    hdr "7. logcat 的 wifi 錯誤"
    sh 'logcat -d 2>/dev/null | grep -aiE "wifi|wlan" | grep -aiE "error|fail|cannot|unable|denied" | tail -12'
fi
