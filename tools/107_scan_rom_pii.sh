#!/usr/bin/env bash
#
# 掃一個 ROM zip，確認裡面沒有個人識別資訊。
#
#   bash tools/107_scan_rom_pii.sh <rom.zip> <樣式檔> [<只列檔名的樣式檔>]
#
# 在 WSL 內執行（要 sudo 掛 loop）。
#
# 樣式檔：一行一個字串（grep -F，區分大小寫）。**放在 repo 以外**，例如
#   帳號、電腦名稱、email 帳號、SoC 序號             -> 第二個參數，會印出前後文
#   門號這種連前後文都不該出現在畫面上的             -> 第三個參數，只印檔名
#
# 掃的範圍：
#   system 映像裡的每一個檔案（system.new.dat.br -> ext4 -> loop 唯讀掛載）
#   boot.img 的 kernel（gzip 解開，含後面附加的 DTB）與 ramdisk（cpio 解開）
#   zip 本身的 META-INF/com/android/metadata、updater-script、system/build.prop
#
# 已知誤判：LatinIME.apk 帶了好幾種語言的鍵盤字典，短的樣式字串很容易
# 剛好是某個外語單字的一部分（實際遇到的是波蘭文），前後文一看就知道。
#
# 只看字串，看不到壓縮過的內容（例如 apk 裡被 deflate 的檔案、
# recovery-from-boot.p）。那些的來源若也經過同樣的建置，
# 看 kernel 與 build.prop 乾不乾淨就能判斷。
set -e -o pipefail

ZIP=$1; PAT=$2; SECRET=${3:-}
[ -f "$ZIP" ] && [ -f "$PAT" ] || { echo "用法：$0 <rom.zip> <樣式檔> [<只列檔名的樣式檔>]" >&2; exit 1; }
[ -z "$SECRET" ] || [ -f "$SECRET" ] || { echo "!!! 找不到 $SECRET" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
BR=${BR:-$HOME/lineage-16.0/out/host/linux-x86/bin/brotli}
[ -x "$BR" ] || { echo "!!! 找不到 brotli：$BR" >&2; exit 1; }
W=$(mktemp -d "$HOME/piiscan.XXXX")
trap 'mountpoint -q "$W/m" && sudo umount "$W/m"; rm -rf "$W"' EXIT
PAT=$(realpath "$PAT"); [ -z "$SECRET" ] || SECRET=$(realpath "$SECRET")

cd "$W"
unzip -q "$ZIP"
"$BR" -d system.new.dat.br -o system.new.dat && rm -f system.new.dat.br
python3 "$HERE/105_sdat2img.py" system.transfer.list system.new.dat system.img >/dev/null
rm -f system.new.dat
mkdir m && sudo mount -o ro,loop system.img m
python3 - <<'PY'
import gzip, struct, zlib
b = open("boot.img", "rb").read()
ks, _, rs = struct.unpack_from("<III", b, 8)
ps = struct.unpack_from("<I", b, 36)[0]
k = b[ps:ps + ks]
ro = ps + (ks + ps - 1) // ps * ps
d = zlib.decompressobj(16 + zlib.MAX_WBITS)
open("kernel.raw", "wb").write(d.decompress(k) + d.unused_data)
open("ramdisk.raw", "wb").write(gzip.decompress(b[ro:ro + rs]))
PY
mkdir rd && (cd rd && cpio -idm --quiet < ../ramdisk.raw)
EXTRA="kernel.raw META-INF/com/android/metadata META-INF/com/google/android/updater-script system/build.prop"

hits() { { sudo grep -rlaF -f "$1" m rd 2>/dev/null; grep -laF -f "$1" $EXTRA 2>/dev/null; } \
         | sed -e 's#^m/#/system/#' -e 's#^rd/#ramdisk:/#' | sort -u || true; }

RC=0
echo "=== $(basename "$PAT") ==="
H=$(hits "$PAT")
if [ -z "$H" ]; then echo "  乾淨"; else
    RC=1
    echo "  比中 $(echo "$H" | wc -l) 個檔案："
    echo "$H" | sed 's/^/    /' | head -50 || true
    echo "  前後文（去重）："
    RE=".{0,50}($(paste -sd'|' "$PAT" | sed 's/[.[\*^$()+?{}]/\\&/g')).{0,40}"
    # 整串要 || true：head 截斷時上游會收到 SIGPIPE，配上 pipefail 與 set -e
    # 會讓整支腳本在這裡結束 —— 下面「只列檔名」那組就根本沒掃到（踩過一次）。
    { sudo grep -rhaoE "$RE" m rd 2>/dev/null; grep -haoE "$RE" $EXTRA 2>/dev/null; } \
        | tr -c '[:print:]\n' '.' | sed -E 's/\.{3,}/…/g' | sort | uniq -c | sort -rn | head -20 | sed 's/^/    /' \
        || true
fi
if [ -n "$SECRET" ]; then
    echo "=== $(basename "$SECRET")（只列檔名）==="
    H=$(hits "$SECRET")
    if [ -z "$H" ]; then echo "  乾淨"; else RC=1; echo "$H" | sed 's/^/    /'; fi
fi
exit $RC
