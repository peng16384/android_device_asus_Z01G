#!/usr/bin/env bash
# LineageOS 第一次開機的狀態擷取
#
#   ADB=/path/to/adb bash tools/29_firstboot_capture.sh
#
# 開機後盡快抓，因為 logcat 的環形緩衝區會被後續訊息蓋掉。
# 全部存到 work/firstboot/，之後比對用。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

ADB="${ADB:-adb}"
OUT="${OUT:-$DEVICE_PATH/docs/firstboot}"
TS=$(date +%Y%m%d-%H%M%S)
D="$OUT/$TS"

adb_() { MSYS_NO_PATHCONV=1 "$ADB" "$@"; }

mkdir -p "$D"
echo "=== 輸出目錄 $D ==="

echo
echo "=== 基本狀態 ==="
adb_ shell 'getprop ro.build.fingerprint; getprop ro.lineage.version; getprop ro.build.version.release; getprop sys.boot_completed; getprop init.svc.bootanim; cat /proc/version' 2>&1 | tee "$D/basic.txt"

echo
echo "=== 抓 log ==="
for x in "logcat -d:logcat.txt" "logcat -b all -d:logcat_all.txt" "logcat -b kernel -d:logcat_kernel.txt"; do
    cmd="${x%%:*}"; f="${x##*:}"
    adb_ shell "$cmd" > "$D/$f" 2>&1 && printf '  %-20s %s 行\n' "$f" "$(wc -l < "$D/$f")"
done
adb_ shell 'dmesg' > "$D/dmesg.txt" 2>&1 && echo "  dmesg.txt            $(wc -l < "$D/dmesg.txt") 行"
adb_ shell 'getprop' > "$D/getprop.txt" 2>&1 && echo "  getprop.txt          $(wc -l < "$D/getprop.txt") 行"
adb_ shell 'df -h; echo ---; mount' > "$D/mounts.txt" 2>&1 && echo "  mounts.txt"
adb_ shell 'ls -1 /sys/class/net' > "$D/netifaces.txt" 2>&1 && echo "  netifaces.txt"
adb_ shell 'cat /proc/bus/input/devices' > "$D/input_devices.txt" 2>&1 && echo "  input_devices.txt"

echo
echo "=== 服務狀態 ==="
adb_ shell 'for s in zygote zygote_secondary surfaceflinger media vold netd ril-daemon wpa_supplicant rmt_storage per_mgr adsprpcd thermal-engine vendor.sensors audioserver cameraserver; do echo "$s = $(getprop init.svc.$s)"; done' 2>&1 | tee "$D/services.txt" | sed 's/^/  /'

echo
echo "=== SELinux denial 統計 ==="
grep -c "avc: *denied" "$D/logcat_all.txt" 2>/dev/null | sed 's/^/  總數 /'
grep -oP 'avc: *denied.*?scontext=u:r:\K[^:]+' "$D/logcat_all.txt" 2>/dev/null | sort | uniq -c | sort -rn | head -15 | sed 's/^/    /'

echo
echo "=== 崩潰 / fatal ==="
grep -iE "FATAL|beginning of crash|Process crashed|died|E AndroidRuntime" "$D/logcat_all.txt" 2>/dev/null | head -20 | sed 's/^/  /'

echo
echo "完成：$D"
