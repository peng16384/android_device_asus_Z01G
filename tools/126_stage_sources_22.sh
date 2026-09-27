#!/usr/bin/env bash
#
# 準備 22.2 的兩個 blob 抽取來源（在 lineage22 distro 內）
#
#   bash device/asus/Z01G/tools/126_stage_sources_22.sh
#
# 產出：
#   ~/asus/dump/system/     ASUS 原廠 1911.117 的 /system（vendor 在 system/vendor；
#                           extract_utils 找不到 dump/vendor 時自動改找 system/vendor）
#                           a530_pfp.fw 換成 linux-firmware 1.87.01（新 kernel 要 WHERE_AM_I）
#   OnePlus 來源直接用 ~/ref/proprietary_vendor_oneplus_msm8998-common/proprietary（不用準備）
#
# 為什麼不直接拿掛載點當來源：要換掉 a530_pfp.fw，掛載點是唯讀的。
set -e -o pipefail

IMG=${IMG:-$HOME/asus/system.img}   # lineage-16.0 分支 tools/06：root dd 整個 system 分割
IMG_SHA=f754fd05cec66bfa98ce5874751cbc5ce8665742598af850fb63788d526c5b2a   # ASUS 1911.117 的 system 分割（dd 出來的原樣）
PFP=${PFP:-$HOME/asus/a530_pfp.fw}  # linux-firmware 的 qcom/a530_pfp.fw
PFP_SHA=7ab3cd917e1f875f6a8387f8bc5efcf11ce9c88542ef2fc3cbda7d4b7b163286   # linux-firmware 1.87.01
MNT=/mnt/zs_system
DUMP=$HOME/asus/dump

echo "=== 核對 system.img（5 GiB，約 1 分鐘）==="
got=$(sha256sum "$IMG" | cut -d' ' -f1)
[ "$got" = "$IMG_SHA" ] || { echo "!!! system.img sha256 不符：$got" >&2; exit 1; }
echo "  ✓ $IMG_SHA"
got=$(sha256sum "$PFP" | cut -d' ' -f1)
[ "$got" = "$PFP_SHA" ] || { echo "!!! a530_pfp.fw sha256 不符：$got" >&2; exit 1; }

echo "=== 掛載（唯讀）==="
sudo mkdir -p "$MNT"
mountpoint -q "$MNT" || sudo mount -o ro,loop "$IMG" "$MNT"
ls "$MNT" | head -5

echo "=== 同步到 $DUMP/system ==="
mkdir -p "$DUMP/system"
sudo rsync -a --delete "$MNT/" "$DUMP/system/"
sudo chown -R "$(id -u):$(id -g)" "$DUMP"
du -sh "$DUMP/system"

echo "=== a530_pfp.fw 換成 linux-firmware 1.87.01 ==="
F="$DUMP/system/vendor/firmware/a530_pfp.fw"
printf '  原本 %s  ' "$(sha256sum "$F" | cut -c1-16)"; od -An -tx4 -j4 -N4 "$F"
cp "$PFP" "$F"
printf '  換成 %s  ' "$(sha256sum "$F" | cut -c1-16)"; od -An -tx4 -j4 -N4 "$F"

sudo umount "$MNT"
echo "=== 完成 ==="
