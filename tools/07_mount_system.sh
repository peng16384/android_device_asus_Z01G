#!/usr/bin/env bash
# 把 dump 下來的 system.img 唯讀掛載起來並做健檢
#
# 在 WSL 內以 root 執行：
#   wsl -u root -- bash $DEVICE_PATH/tools/07_mount_system.sh
#
# 注意：一律 ro 掛載。這份映像是唯一一份完整的原廠 /system 快照，
#       之後所有 blob 抽取都從這裡來，不要讓它被改到。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -euo pipefail

IMG=$DEVICE_PATH/images/system.img
MNT=/mnt/zs_system

[ -f "$IMG" ] || { echo "!!! 找不到 $IMG" >&2; exit 1; }

echo "=== 映像 ==="
ls -l "$IMG"

echo
echo "=== ext4 superblock ==="
dumpe2fs -h "$IMG" 2>/dev/null | grep -E \
    "volume name|Block count|Block size|Free blocks|Inode count|Filesystem state|Filesystem features"

echo
echo "=== 掛載（唯讀）==="
mkdir -p "$MNT"
if mountpoint -q "$MNT"; then
    echo "  已掛載，先卸載"
    umount "$MNT"
fi
mount -o ro,loop "$IMG" "$MNT"
echo "  OK -> $MNT"
df -h "$MNT" | tail -1

echo
echo "=== 頂層內容 ==="
ls -1 "$MNT"

echo
echo "=== 各目錄大小 ==="
du -sh "$MNT"/* 2>/dev/null | sort -h

echo
echo "=== build.prop 重點 ==="
grep -E "^ro\.(build\.(fingerprint|version\.(release|incremental|sdk)|description)|product\.(model|device|board|manufacturer)|board\.platform)" \
    "$MNT/build.prop" 2>/dev/null | sed 's/^/  /'

echo
echo "=== vendor（非 Treble，blobs 都在這裡）==="
ls -1 "$MNT/vendor" 2>/dev/null
echo "  vendor/lib   : $(find "$MNT/vendor/lib"   -maxdepth 1 -name '*.so' 2>/dev/null | wc -l) 個 .so"
echo "  vendor/lib64 : $(find "$MNT/vendor/lib64" -maxdepth 1 -name '*.so' 2>/dev/null | wc -l) 個 .so"
echo "  vendor/bin   : $(find "$MNT/vendor/bin"   -maxdepth 1 -type f 2>/dev/null | wc -l) 個執行檔"
echo "  vendor/firmware: $(find "$MNT/vendor/firmware" -type f 2>/dev/null | wc -l) 個檔案"

echo
echo "=== 完整性抽查 ==="
echo "  symlink 總數 : $(find "$MNT" -type l 2>/dev/null | wc -l)"
echo "  斷掉的 symlink: $(find "$MNT" -xtype l 2>/dev/null | wc -l)"
echo "  檔案總數     : $(find "$MNT" -type f 2>/dev/null | wc -l)"

echo
echo "掛載點：$MNT（唯讀）。卸載：sudo umount $MNT"
