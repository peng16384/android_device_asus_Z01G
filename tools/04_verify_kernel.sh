#!/usr/bin/env bash
# 刷機前的離線驗證
#
# 這一步不碰手機，目的是在 PC 上盡可能證明「自編 kernel 跟原廠那顆是同一個東西」。
# 四項檢查：版本字串、附加 DTB、config 差異、大小。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -euo pipefail

WORK="$HOME/zs551kl"
KDIR="$WORK/kernel/msm-4.4"
PROJ="$DEVICE_PATH"
BUILT="$KDIR/out/arch/arm64/boot/Image.gz-dtb"
STOCK="$PROJ/_docs/backup/boot.img"
DUMP="$DEVICE_PATH/docs/reference"
TOOLS="$PROJ/tools"

[ -f "$BUILT" ] || { echo "!!! 找不到 $BUILT，先跑步驟 3" >&2; exit 1; }

echo "############################################################"
echo "# 檢查 1／2：版本字串 + 附加 DTB（自編 vs 原廠）"
echo "############################################################"
python3 "$TOOLS/kernelcheck.py" "$BUILT" "$STOCK"

echo
echo "############################################################"
echo "# 檢查 3：out/.config vs 手機 /proc/config.gz"
echo "############################################################"
grep -E '^CONFIG_' "$KDIR/out/.config"            | sort > /tmp/built.cfg
grep -E '^CONFIG_' "$DUMP/running_kernel_config.txt" | sort > /tmp/phone.cfg
echo "  自編 .config       : $(wc -l < /tmp/built.cfg) 條"
echo "  手機 /proc/config.gz: $(wc -l < /tmp/phone.cfg) 條"
echo
echo "  --- 自編有、手機沒有 ---"
comm -23 /tmp/built.cfg /tmp/phone.cfg | sed 's/^/    /' || true
echo "  --- 手機有、自編沒有 ---"
comm -13 /tmp/built.cfg /tmp/phone.cfg | sed 's/^/    /' || true
echo
echo "  差異總數: $(comm -3 /tmp/built.cfg /tmp/phone.cfg | wc -l)"

echo
echo "############################################################"
echo "# 檢查 4：大小"
echo "############################################################"
BUILT_SZ=$(stat -c %s "$BUILT")
STOCK_SZ=$(python3 - "$STOCK" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read(64)
print(struct.unpack_from('<I', d, 8)[0])
PY
)
echo "  自編 Image.gz-dtb : $(printf "%'d" "$BUILT_SZ") bytes"
echo "  原廠 kernel blob  : $(printf "%'d" "$STOCK_SZ") bytes"
python3 - "$BUILT_SZ" "$STOCK_SZ" <<'PY'
import sys
b, s = int(sys.argv[1]), int(sys.argv[2])
d = (b - s) / s * 100
print(f'  差異              : {b-s:+,} bytes ({d:+.2f} %)')
print('  判定              : ' + ('OK（在 ±5 % 內）' if abs(d) <= 5 else '!!! 超出 ±5 %，需要調查'))
PY

echo
echo "步驟 4 完成"
