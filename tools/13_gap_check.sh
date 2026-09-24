#!/usr/bin/env bash
# 檢查 proprietary-files.txt 有沒有漏掉重要的 blob
#
# 起因：12_clean_proprietary_list.py 回報「剔除用不到的 sensor 0 條」，
# 但 ASUS 的 vendor 映像明明塞了十幾顆 sensor 的 chromatix ——
# 代表這些檔案「根本沒進到草稿裡」。
#
# 原因：草稿 = 參考機清單 ∩ 本機映像，加上檔名含 ASUS 關鍵字的。
# 參考機（OnePlus/Xiaomi）用的是別顆 sensor，所以他們的清單裡沒有 imx362/351/319，
# 而這些檔名也不含 "asus" 之類的關鍵字 -> 兩邊都漏掉。
#
# 這支腳本把「映像裡有、清單裡沒有」的重要檔案列出來。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -euo pipefail

IMG=$DEVICE_PATH/images/system.img
MNT=/mnt/zs_system
LIST=$DEVICE_PATH/proprietary-files.txt
OUT=$DEVICE_PATH/blobs/gap_report.txt

mkdir -p "$MNT"
if ! mountpoint -q "$MNT"; then
    mount -o ro,loop "$IMG" "$MNT" || { echo "!!! 掛載失敗" >&2; exit 1; }
fi
echo "掛載點 $MNT 就緒（$(ls "$MNT" | wc -l) 個頂層項目）"
echo

# 清單裡已有的路徑
grep -v '^#' "$LIST" | grep -v '^$' | sed 's/|.*//' | sed 's/^-//' | sort -u > /tmp/have.txt
echo "清單現有 $(wc -l < /tmp/have.txt) 條"
echo

report() {
    local title="$1"; shift
    echo "=== $title ==="
    local n=0
    for pat in "$@"; do
        while IFS= read -r f; do
            rel="${f#$MNT/}"
            if ! grep -qxF "$rel" /tmp/have.txt; then
                printf '  %s\n' "$rel"
                echo "$rel" >> "$OUT.tmp"
                n=$((n+1))
            fi
        done < <(find "$MNT" -path "$pat" -type f 2>/dev/null | sort)
    done
    echo "  -> 缺 $n 條"
    echo
}

: > "$OUT.tmp"

report "本機相機 sensor 的 chromatix / 校正（IMX362 主 / IMX351 望遠 / IMX319 前）" \
    "$MNT/vendor/etc/camera/imx362*" \
    "$MNT/vendor/etc/camera/imx351*" \
    "$MNT/vendor/etc/camera/imx319*" \
    "$MNT/vendor/lib/libchromatix_imx362*" \
    "$MNT/vendor/lib/libchromatix_imx351*" \
    "$MNT/vendor/lib/libchromatix_imx319*" \
    "$MNT/vendor/lib/libmmcamera_imx362*" \
    "$MNT/vendor/lib/libmmcamera_imx351*" \
    "$MNT/vendor/lib/libmmcamera_imx319*"

report "相機通用設定" \
    "$MNT/vendor/etc/camera/camera_config.xml" \
    "$MNT/vendor/etc/camera/*.conf"

report "WLAN（qcacld / firmware / 設定）" \
    "$MNT/vendor/firmware/wlan/*" \
    "$MNT/vendor/etc/wifi/*" \
    "$MNT/vendor/lib*/libwifi-hal*" \
    "$MNT/vendor/lib*/lib_driver_cmd*"

report "音效設定（mixer_paths / audio_policy / acdb）" \
    "$MNT/vendor/etc/audio*" \
    "$MNT/vendor/etc/mixer_paths*" \
    "$MNT/vendor/etc/acdbdata/*"

report "顯示：本機面板的色彩校正" \
    "$MNT/vendor/etc/qdcm_calib_data*"

report "Thermal / 電源設定" \
    "$MNT/vendor/etc/thermal*" \
    "$MNT/vendor/etc/*thermal*"

report "GPS 設定" \
    "$MNT/vendor/etc/gps*" \
    "$MNT/vendor/etc/izat*" \
    "$MNT/vendor/etc/flp.conf" \
    "$MNT/vendor/etc/sap.conf"

sort -u "$OUT.tmp" > "$OUT"
rm -f "$OUT.tmp"
echo "==============================================="
echo "缺漏總計 $(wc -l < "$OUT") 條，已寫到 $OUT"
