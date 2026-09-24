#!/usr/bin/env bash
# 對掛載好的 system 做清點，產出可版控的文字清單
#
# 產物（都放 work/inventory/，純文字，會進 git）：
#   broken_symlinks.txt   斷掉的 symlink 與其目標（確認都是跨分割連結而非毀損）
#   vendor_files.txt      /system/vendor 底下所有檔案 + 大小（blob 清單的原料）
#   system_files.txt      整個 /system 的檔案清單 + 大小
#   build.prop            原廠 build.prop 全文
#   manifest.xml / compatibility_matrix.xml
#   hal_services.txt      vendor/bin/hw 底下的 HAL service（決定要抽哪些 blob 的關鍵）
#   init_rc.txt           vendor 的 init rc 檔清單
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -euo pipefail

MNT=/mnt/zs_system
OUT=$DEVICE_PATH/inventory

mountpoint -q "$MNT" || { echo "!!! $MNT 沒掛載，先跑 07_mount_system.sh" >&2; exit 1; }
mkdir -p "$OUT"

echo "=== 斷掉的 symlink ==="
find "$MNT" -xtype l -printf '%P -> %l\n' 2>/dev/null | sort > "$OUT/broken_symlinks.txt"
wc -l < "$OUT/broken_symlinks.txt" | sed 's/^/  共 /;s/$/ 條/'
echo "  目標的頂層目錄分佈："
sed 's/.*-> //' "$OUT/broken_symlinks.txt" | sed 's#^\(/[^/]*\).*#\1#' | sort | uniq -c | sort -rn | sed 's/^/    /'
echo "  範例："
head -8 "$OUT/broken_symlinks.txt" | sed 's/^/    /'

echo
echo "=== 檔案清單 ==="
( cd "$MNT" && find . -type f -printf '%10s  %P\n' | sort -k2 ) > "$OUT/system_files.txt"
( cd "$MNT/vendor" && find . -type f -printf '%10s  %P\n' | sort -k2 ) > "$OUT/vendor_files.txt"
echo "  system 全部 : $(wc -l < "$OUT/system_files.txt") 個檔案"
echo "  vendor      : $(wc -l < "$OUT/vendor_files.txt") 個檔案"

echo
echo "=== HAL service（vendor/bin/hw）==="
ls -1 "$MNT/vendor/bin/hw" 2>/dev/null > "$OUT/hal_services.txt" || true
wc -l < "$OUT/hal_services.txt" | sed 's/^/  共 /;s/$/ 個/'
sed 's/^/    /' "$OUT/hal_services.txt"

echo
echo "=== vendor init rc ==="
find "$MNT/vendor/etc" -name 'init*.rc' -printf '%P\n' 2>/dev/null | sort > "$OUT/init_rc.txt" || true
sed 's/^/    /' "$OUT/init_rc.txt"

echo
echo "=== 複製設定檔 ==="
for f in build.prop manifest.xml compatibility_matrix.xml; do
    [ -f "$MNT/$f" ] && cp "$MNT/$f" "$OUT/$f" && echo "  $f"
done
[ -f "$MNT/vendor/manifest.xml" ] && cp "$MNT/vendor/manifest.xml" "$OUT/vendor_manifest.xml" && echo "  vendor/manifest.xml"
[ -f "$MNT/vendor/ueventd.rc" ] && cp "$MNT/vendor/ueventd.rc" "$OUT/vendor_ueventd.rc" && echo "  vendor/ueventd.rc"
[ -f "$MNT/vendor/etc/fstab.qcom" ] && cp "$MNT/vendor/etc/fstab.qcom" "$OUT/fstab.qcom" && echo "  vendor/etc/fstab.qcom"

echo
echo "=== recovery-from-boot 狀態（TWRP 能不能存活的關鍵）==="
ls -l "$MNT"/recovery-from-boot* 2>&1 | sed 's/^/  /' || true
ls -l "$MNT"/bin/install-recovery.sh "$MNT"/etc/install-recovery.sh 2>&1 | sed 's/^/  /' || true

chown -R 1000:1000 "$OUT" 2>/dev/null || true
echo
echo "清單輸出到：$OUT"
ls -l "$OUT" | sed 's/^/  /' || true
exit 0
