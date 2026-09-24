#!/usr/bin/env bash
#
# 比對兩個 ROM zip 的 /system 內容：多了什麼、少了什麼、哪些檔案大小變了。
#
#   bash tools/105_diff_rom_zips.sh <舊.zip> <新.zip>
#
# 在 WSL 內執行（要 sudo 掛 loop）。
#
# ## 為什麼需要
#
# 這一輪只換了 ims.apk，新 zip 卻比上一版小 1.8 MB。system.transfer.list
# 的總區塊數差了 1840 個（約 7 MB）—— 是內容真的變了，不是壓縮差異。
# 解開兩個映像比對才發現：
#     只在舊版：vendor/lib/modules/qca_cld3_wlan.ko
#     wil6210.ko / msm_11ad_proxy.ko 大小不同、modules.dep 147 -> 482
# 原因是 blob 清單與 kernel 建置搶 vendor/lib/modules/，誰勝出看建置順序
# （見 tools/31 的 EXCLUDE_EXACT 開頭那段）。
#
# 「只改了 X」的建置，產物裡就應該只有 X 變了。刷之前用這支確認一次，
# 比刷完再發現某個功能不見便宜得多。
#
# 大小不同的清單裡，大量幾十 bytes 的 .so 差異是正常的（建置時間戳、
# build id）；要看的是「只在一邊」與差異大的那幾個。
set -e -o pipefail

OLD=$1; NEW=$2
[ -f "$OLD" ] && [ -f "$NEW" ] || { echo "用法：$0 <舊.zip> <新.zip>" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
BR=${BR:-$HOME/lineage-16.0/out/host/linux-x86/bin/brotli}
[ -x "$BR" ] || { echo "!!! 找不到 brotli：$BR（AOSP 編過一次就會有）" >&2; exit 1; }
W=$(mktemp -d "$HOME/zipdiff.XXXX")
trap 'sudo umount "$W"/mnt_* 2>/dev/null || true; rm -rf "$W"' EXIT

for n in old new; do
    Z=$OLD; [ $n = new ] && Z=$NEW
    mkdir -p "$W/$n" "$W/mnt_$n"
    ( cd "$W/$n"
      unzip -q -o "$Z" system.new.dat.br system.transfer.list
      echo "$n: $(sed -n 2p system.transfer.list) 個區塊  ($(basename "$Z"))"
      "$BR" -d system.new.dat.br -o system.new.dat && rm -f system.new.dat.br
      python3 "$HERE/105_sdat2img.py" system.transfer.list system.new.dat system.img >/dev/null
      rm -f system.new.dat )
    sudo mount -o ro,loop "$W/$n/system.img" "$W/mnt_$n"
    sudo find "$W/mnt_$n" -printf '%P\t%s\t%y\n' | sort > "$W/$n.list"
    sudo umount "$W/mnt_$n"
    rm -f "$W/$n/system.img"
done

cd "$W"
echo
echo "== 只在舊版 =="
comm -23 <(cut -f1 old.list) <(cut -f1 new.list) | sed 's/^/    /'
echo "== 只在新版 =="
comm -13 <(cut -f1 old.list) <(cut -f1 new.list) | sed 's/^/    /'
echo "== 大小差超過 1 KB 的 =="
join -t $'\t' old.list new.list \
    | awk -F'\t' '$2!=$4 { d=$4-$2; if (d>1024 || d<-1024) printf "    %+9d  %s  (%d -> %d)\n", d, $1, $2, $4 }' \
    | sort -k1,1n
echo "== 大小有變的共 $(join -t $'\t' old.list new.list | awk -F'\t' '$2!=$4' | wc -l) 個 =="
