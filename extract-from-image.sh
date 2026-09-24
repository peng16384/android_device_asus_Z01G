#!/bin/bash
#
# 本專案專用：從 dd 下來的 system.img 抽 blobs，不走 adb。
#
# 為什麼不用 adb：
#   - adb pull 會丟失權限、symlink 與 SELinux context
#   - 映像是離線的，抽幾次都不必再碰手機，也不怕手機狀態被改掉
#
# extract_utils.sh 期望 SRC 目錄底下有 system/ 子目錄，
# 所以這裡建一個暫存目錄，把掛載點 bind 進去當 system/。
#
# 需要 root（mount / bind mount）。
#
# 用法（在 WSL 內）：
#   sudo device/asus/Z01G/extract-from-image.sh
set -euo pipefail

IMG="${IMG:-$DEVICE_PATH/images/system.img}"
MNT="${MNT:-/mnt/zs_system}"
WORKDIR="${WORKDIR:-/tmp/z01g_dump}"

MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$MY_DIR" ]]; then MY_DIR="$PWD"; fi

[ "$(id -u)" -eq 0 ] || { echo "!!! 需要 root（mount 用）" >&2; exit 1; }
[ -f "$IMG" ] || { echo "!!! 找不到 $IMG" >&2; exit 1; }

echo "=== 掛載 $IMG（唯讀）==="
mkdir -p "$MNT"
if ! mountpoint -q "$MNT"; then
    mount -o ro,loop "$IMG" "$MNT"
fi
echo "  OK"

echo "=== 準備 dump 目錄 $WORKDIR ==="
mkdir -p "$WORKDIR/system"
if ! mountpoint -q "$WORKDIR/system"; then
    mount --bind "$MNT" "$WORKDIR/system"
fi
ls -1 "$WORKDIR/system" | head -5 | sed 's/^/  /'

echo
echo "=== 呼叫 extract-files.sh ==="
"$MY_DIR"/extract-files.sh "$WORKDIR" "$@"

echo
echo "完成。收尾："
echo "  umount $WORKDIR/system && umount $MNT"
