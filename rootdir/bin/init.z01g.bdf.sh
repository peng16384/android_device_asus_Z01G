#!/vendor/bin/sh
# ZS551KL：挑 WLAN 的 BDF（board data file）給 cnss-daemon（init.target.rc 的 post-fs-data 呼叫）
#
# 用的是 OnePlus 的 cnss-daemon：它讀 OnePlus 專屬的 /sys/project_info/hw_id 決定檔名，這台沒有這個節點，
# 就退回要 bdwlanc.bin —— 這台沒有這個檔 -> "Failed to Download the BDF File" -> WLAN FW 永遠等不到 BDF、
# 不會 FW_READY -> Wi-Fi 打不開（2026-09-25：icnss 的 QMI 交握全成功，fw_status 0x5，缺 0x2 FW_READY）。
#
# /vendor/firmware/bdwlanc.bin 是指到這裡的 symlink（rootdir/Android.bp），這支照 ASUS 原廠 cnss-daemon
# 的邏輯（反組譯 ~/asus/dump/vendor/bin/cnss-daemon 0x7354~0x74b4）把它連到正確的那一份：
#   ro.boot.id.rf 1~4                -> bdwlan_open.bin（= bdwlan.bin）
#   ro.boot.id.rf <= 7（含沒設的 -1） -> persist.radio.multisim.config 是 none（或沒設）-> bdwlan_operator.bin
#                                       否則 -> bdwlan_combo.bin
#   其他                              -> bdwlan.bin
rf=$(getprop ro.boot.id.rf)
[ -n "$rf" ] || rf=-1
case "$rf" in
    1|2|3|4)
        f=bdwlan_open.bin ;;
    *)
        if [ "$rf" -le 7 ] 2>/dev/null; then
            ms=$(getprop persist.radio.multisim.config)
            [ -n "$ms" ] || ms=none
            if [ "$ms" = none ]; then f=bdwlan_operator.bin; else f=bdwlan_combo.bin; fi
        else
            f=bdwlan.bin
        fi ;;
esac
mkdir -p /data/vendor/wifi
ln -sf /vendor/firmware/$f /data/vendor/wifi/bdwlan_z01g.bin
log -t z01g-bdf "ro.boot.id.rf=$rf -> $f"
