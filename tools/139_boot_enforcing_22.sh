#!/usr/bin/env bash
#
# 22.2：做 enforcing / permissive 兩顆 boot.img，切換與回退都只要 fastboot flash boot（10 秒）
#
#   bash device/asus/Z01G/tools/139_boot_enforcing_22.sh
#
# 前提：out/ 裡剛編好的是 permissive 版（BoardConfig 還有 androidboot.selinux=permissive）。
# 做法：先把現成的 boot.img 存成 boot-permissive-rollback.img，拿掉那一行後 m bootimage，存成
#       boot-enforcing.img。之後 BoardConfig 就維持 enforcing（下一次完整編譯的 zip 也是 enforcing）。
#
# ⚠ 22.2 的 SELinux 政策在 /system（vendor 在 system 裡），不在 boot.img —— 政策改了要刷整包 zip；
#   boot.img 只決定 permissive / enforcing 這一個開關（16.0 是整份政策都在 ramdisk）。
set -e -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄
BC=$PROJ/BoardConfig.mk
DEST=$PROJ/out
O=$SRC/out/target/product/Z01G

cmdline() { python3 - "$1" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
print(d[64:64 + 512].split(b'\0')[0].decode())
PY
}

grep -q '^BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive' "$BC" || { echo "!!! BoardConfig 已經不是 permissive，out/ 的 boot.img 不能當 rollback"; exit 1; }
cmdline "$O/boot.img" | grep -q 'androidboot.selinux=permissive' || { echo "!!! out/ 的 boot.img 不是 permissive 版"; exit 1; }
cp "$O/boot.img" "$DEST/boot-permissive-rollback.img"
echo "  rollback：$(cmdline "$DEST/boot-permissive-rollback.img" | grep -o 'androidboot.selinux=[a-z]*')"

sed -i 's/^BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive$/# （2026-09-26 起 enforcing；permissive 版的 boot.img 見 tools\/139）/' "$BC"
bash "$PROJ/tools/123_place_tree_22.sh" | tail -1
cd "$SRC"
source build/envsetup.sh >/dev/null
breakfast Z01G >/dev/null
m bootimage > out/bootimage.log 2>&1 || { tail -20 out/bootimage.log; exit 1; }
cp "$O/boot.img" "$DEST/boot-enforcing.img"

c=$(cmdline "$DEST/boot-enforcing.img")
echo "$c" | grep -q 'selinux=permissive' && { echo "!!! enforcing 版還帶 permissive"; exit 1; }
echo "  enforcing：header cmdline ${#c} bytes（上限 400）"
[ ${#c} -le 400 ]
sha256sum "$DEST/boot-enforcing.img" "$DEST/boot-permissive-rollback.img" | sed 's/^/  /'
