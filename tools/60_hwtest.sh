#!/usr/bin/env bash
# Z01G 硬體檢測 —— 用 adb 把能自動判斷的項目全跑一遍。
#
#   bash tools/60_hwtest.sh            # 只跑自動項目
#   bash tools/60_hwtest.sh -i         # 加上需要動手的互動項目
#
# 為什麼要自己寫：
#   ASUS 原廠那套 MMI / FTM 測試模式（*#*#3646633#*#*）在這裡用不了 ——
#   vendor/bin/mmi 與 libmmi.so 需要 libskia.so，而 Pie 不再把 skia 安裝成
#   共享函式庫；整套 MMI 還依賴 ASUS 改過的 framework 與自家 dialer。
#   （刻意不補 libskia.so：塞 Oreo 版會蓋掉 framework 正在用的那一份。）
#   LineageOS 本身也沒有內建硬體測試選單。
#
# 判讀原則：這支只回報「看得到什麼」，不下「壞了」的結論 ——
# 很多項目沒有硬體在場（沒插 SIM、沒有 Wi-Fi AP）就不會有輸出。

ADB="${ADB:-adb}"
sh() { MSYS_NO_PATHCONV=1 "$ADB" shell "$@" 2>&1; }
hdr() { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }

[ "$(MSYS_NO_PATHCONV=1 "$ADB" get-state 2>&1)" = "device" ] || {
    echo "!!! adb 沒有連到開機中的系統（現在是：$(MSYS_NO_PATHCONV=1 "$ADB" get-state 2>&1)）" >&2
    exit 1
}

hdr "系統"
sh 'echo "  版本      $(getprop ro.lineage.version)"
    echo "  Android   $(getprop ro.build.version.release) / SDK $(getprop ro.build.version.sdk)"
    echo "  kernel    $(cut -d" " -f3 /proc/version)"
    echo "  開機完成  $(getprop sys.boot_completed)   uptime $(cut -d" " -f1 /proc/uptime)s"
    echo "  SELinux   $(getenforce)"'

hdr "CPU / 記憶體 / 溫度"
sh 'echo "  核心數    $(grep -c ^processor /proc/cpuinfo)"
    echo "  大核最高  $(cat /sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_max_freq 2>/dev/null) kHz"
    echo "  小核最高  $(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null) kHz"
    echo "  RAM       $(grep MemTotal /proc/meminfo | tr -s " ")  可用 $(grep MemAvailable /proc/meminfo | tr -s " ")"
    for z in /sys/class/thermal/thermal_zone*/; do
        t=$(cat $z/temp 2>/dev/null); n=$(cat $z/type 2>/dev/null)
        [ -n "$t" ] && [ "$t" -gt 30000 ] 2>/dev/null && echo "  $n: $((t/1000))C"
    done | head -6'

hdr "儲存 / 分割區"
sh 'df -h /system /data /cache /persist /firmware /dsp 2>/dev/null | grep -v "^Filesystem"'

hdr "顯示"
sh 'dumpsys display 2>/dev/null | grep -oE "[0-9]+ x [0-9]+, [0-9.]+ fps" | head -1 | sed "s/^/  解析度  /"
    echo "  背光    $(cat /sys/class/leds/lcd-backlight/brightness 2>/dev/null) / $(cat /sys/class/leds/lcd-backlight/max_brightness 2>/dev/null)"
    echo "  面板    $(cat /sys/class/graphics/fb0/msm_fb_panel_info 2>/dev/null | head -2 | tr "\n" " ")"'

hdr "輸入裝置"
# 只取 Input Devices 那一段 —— 整份 dumpsys input 後面還有 windows / channels，
# 用 "^ +[0-9]+: " 會把那些全撈進來。
sh 'dumpsys input 2>/dev/null | sed -n "/^Input Devices:/,/^Input Reader State/p" |
    grep -E "^ +[0-9]+: |KeyLayoutFile" | sed "s/^ */  /"'

hdr "感測器"
sh 'dumpsys sensorservice 2>/dev/null | grep -oE "^0x[0-9a-f]+\) [^|]+\|[^|]+\|" | sed "s/^/  /" | head -20'

hdr "電池 / 充電"
sh 'dumpsys battery 2>/dev/null | grep -E "level|status|health|temperature|voltage|current"  | sed "s/^ */  /"'

hdr "音訊"
sh 'echo "  聲卡      $(cat /proc/asound/cards 2>/dev/null | tr "\n" " ")"
    echo "  PCM 裝置  $(cat /proc/asound/pcm 2>/dev/null | wc -l) 個"
    echo "  audioserver=$(getprop init.svc.audioserver)  audio-hal=$(getprop init.svc.vendor.audio-hal-2-0)"'

hdr "子系統（modem / adsp / ...）"
sh 'for d in /sys/bus/msm_subsys/devices/*; do
        printf "  %-10s %s\n" "$(cat $d/name 2>/dev/null)" "$(cat $d/state 2>/dev/null)"
    done'

hdr "連線"
sh 'w=$(ls /sys/class/net/ | grep -E "^wlan" | tr "\n" " ")
    echo "  Wi-Fi 介面  ${w:-（無 —— kernel 缺 qcacld）}"
    b=$(ls /sys/class/bluetooth/ 2>/dev/null | tr "\n" " ")
    echo "  藍牙 HAL    $(getprop init.svc.vendor.bluetooth-1-0)  hci=${b:-（無，藍牙沒開時本來就沒有）}"
    echo "  rild        $(getprop init.svc.ril-daemon)"
    echo "  SIM 狀態    $(getprop gsm.sim.state)"
    echo "  電信業者    $(getprop gsm.operator.alpha)"
    echo "  網路介面    $(ls /sys/class/net/ | tr "\n" " ")"'

hdr "相機"
sh 'echo "  provider  $(getprop init.svc.vendor.camera-provider-2-4)"
    dumpsys media.camera 2>/dev/null | grep -E "Number of camera devices|Device [0-9]+ maps|facing" | sed "s/^/  /" | head -8'

hdr "GNSS"
sh 'dumpsys location 2>/dev/null | grep -A2 "gps provider" | sed "s/^/  /" | head -6'

hdr "服務異常（init 重啟次數 / crash）"
sh 'echo "  --- init 重啟 ---"
    dmesg 2>/dev/null | grep -oE "Service .[^ ]+. \(pid [0-9]+\) (exited|received)" |
        sed -E "s/pid [0-9]+/pid N/" | sort | uniq -c | sort -rn | head -8 | sed "s/^/  /"
    echo "  --- FATAL EXCEPTION ---"
    n=$(logcat -d -b crash 2>/dev/null | grep -ac "FATAL EXCEPTION")
    echo "  共 $n 次"
    logcat -d -b crash 2>/dev/null | grep -a "Process: " | sed "s/.*Process: /  /" | sort -u'

if [ "${1:-}" = "-i" ]; then
    hdr "互動測試（依畫面提示操作）"
    echo "  10 秒內請按：Home、多工、返回、音量上、音量下、電源"
    echo "  （只列按鍵事件，觸控座標已濾掉）"
    sh 'timeout 10 getevent -lq 2>/dev/null | grep -E "EV_KEY" | grep -v BTN_TOUCH' | sed 's/^/    /'

    hdr "震動（應該會震一下）"
    sh 'echo 300 > /sys/class/timed_output/vibrator/enable 2>/dev/null ||
        echo 300 > /sys/class/leds/vibrator/duration 2>/dev/null && echo 1 > /sys/class/leds/vibrator/activate 2>/dev/null ||
        echo "  沒有可寫的 vibrator 節點（需要 root）"'
fi

echo
echo "完成。"
