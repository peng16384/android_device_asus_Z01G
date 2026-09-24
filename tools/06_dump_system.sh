#!/usr/bin/env bash
# 把 system 分割區整個 dd 出來
#
# 為什麼用 dd 而不是 adb pull /system：
#   - adb pull 會丟失權限、symlink、SELinux context，而 LineageOS 的 device tree
#     需要正確的權限與 symlink 結構
#   - 有了完整映像，之後要抽第幾次 blob 都不用再碰手機
#
# 這是唯讀操作，不寫入手機任何分割區。
#
# 用法（在 Git Bash 或 WSL 執行，adb 走 Windows 版）：
#   ADB=/path/to/adb bash tools/06_dump_system.sh
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -euo pipefail

ADB="${ADB:-adb}"
PROJ="${PROJ:-$DEVICE_PATH}"
OUT="$PROJ/work/images"
PART="system"
BLK="/dev/block/bootdevice/by-name/$PART"
SIZE=5368709120          # sda19 = 5,242,880 KB = 5 GiB（來自 /proc/partitions）
BS=1048576               # Android 8 的 toybox dd 不吃 "1M"，要寫數字
COUNT=$((SIZE / BS))

mkdir -p "$OUT"

echo "=== 前置檢查 ==="
MSYS_NO_PATHCONV=1 "$ADB" shell "su -c 'id'" | sed 's/^/  root: /'
MSYS_NO_PATHCONV=1 "$ADB" shell "su -c 'ls -l $BLK'" | sed 's/^/  block: /'
echo "  目標: $OUT/$PART.img  ($SIZE bytes)"
echo

echo "=== dd（約需數分鐘）==="
# exec-out：不做 CRLF 轉換，二進位才不會壞
# su -c 會把 dd 的 stderr 併進 stdout，所以檔尾會多出「N+0 records in...」摘要
time MSYS_NO_PATHCONV=1 "$ADB" exec-out \
    "su -c 'dd if=$BLK bs=$BS count=$COUNT'" > "$OUT/$PART.raw"

RAW=$(stat -c %s "$OUT/$PART.raw")
echo
echo "  取得 $RAW bytes（預期 $SIZE + dd 摘要）"
if [ "$RAW" -lt "$SIZE" ]; then
    echo "!!! 比分割區還小，傳輸不完整" >&2
    exit 1
fi

echo "=== 截掉檔尾的 dd 摘要 ==="
tail -c +$((SIZE + 1)) "$OUT/$PART.raw" | tr -d '\0' | sed 's/^/  摘要: /'
head -c "$SIZE" "$OUT/$PART.raw" > "$OUT/$PART.img"
rm -f "$OUT/$PART.raw"

echo
echo "=== 結果 ==="
ls -l "$OUT/$PART.img"
sha256sum "$OUT/$PART.img" | tee "$OUT/$PART.img.sha256"

echo
echo "步驟完成。掛載方式（在 WSL 內，唯讀）："
echo "  sudo mkdir -p /mnt/zs_system"
echo "  sudo mount -o ro,loop $DEVICE_PATH/images/system.img /mnt/zs_system"
