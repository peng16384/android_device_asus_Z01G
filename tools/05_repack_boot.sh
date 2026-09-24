#!/usr/bin/env bash
# 重打包 boot.img
#
# 核心是「空對照」：先用原廠 kernel + 原廠 ramdisk 重打包一次，
# 如果輸出跟 _docs/backup/boot.img 逐 byte 相同，就證明打包流程沒有引入任何差異。
# 通過之後才換成自編 kernel —— 這樣萬一刷進去開不了機，可以確定問題出在 kernel，
# 不是出在打包。
#
# 產物：work/repack/boot-custom.img
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -euo pipefail

WORK="$HOME/zs551kl"
KDIR="$WORK/kernel/msm-4.4"
PROJ="$DEVICE_PATH"
TOOLS="$PROJ/tools"
STOCK="$PROJ/_docs/backup/boot.img"
BUILT="$KDIR/out/arch/arm64/boot/Image.gz-dtb"
RP="$PROJ/work/repack"

[ -f "$BUILT" ] || { echo "!!! 找不到 $BUILT，先跑步驟 3" >&2; exit 1; }
[ -f "$STOCK" ] || { echo "!!! 找不到原廠 $STOCK" >&2; exit 1; }

mkdir -p "$RP"

echo "############################################################"
echo "# 1. 拆解原廠 boot.img（唯讀，不會動到 _docs）"
echo "############################################################"
python3 "$TOOLS/bootimg.py" info "$STOCK"
echo
python3 "$TOOLS/bootimg.py" unpack "$STOCK" "$RP/stock"

echo
echo "############################################################"
echo "# 2. 空對照：原廠 kernel + 原廠 ramdisk 重打包，應逐 byte 相同"
echo "############################################################"
python3 "$TOOLS/bootimg.py" repack \
    --template "$STOCK" \
    --kernel   "$RP/stock/kernel" \
    --ramdisk  "$RP/stock/ramdisk" \
    --second   "$RP/stock/second" \
    --out      "$RP/boot-nulltest.img"
echo
if python3 "$TOOLS/bootimg.py" compare "$RP/boot-nulltest.img" "$STOCK"; then
    echo
    echo ">>> 空對照通過：打包流程不會改變任何一個 byte"
else
    echo
    echo "!!! 空對照失敗 —— 打包流程有問題，不要繼續刷機" >&2
    exit 1
fi

echo
echo "############################################################"
echo "# 3. 換上自編 kernel（ramdisk 沿用原廠）"
echo "############################################################"
cp "$BUILT" "$RP/kernel-custom"
python3 "$TOOLS/bootimg.py" repack \
    --template "$STOCK" \
    --kernel   "$RP/kernel-custom" \
    --ramdisk  "$RP/stock/ramdisk" \
    --second   "$RP/stock/second" \
    --out      "$RP/boot-custom.img"

echo
echo "############################################################"
echo "# 4. 成品檢查"
echo "############################################################"
python3 "$TOOLS/bootimg.py" info "$RP/boot-custom.img"
echo
echo "=== 自編 boot 內的 kernel ==="
python3 "$TOOLS/kernelcheck.py" "$RP/boot-custom.img"

echo
echo "=== sha256 ==="
sha256sum "$RP/boot-custom.img" "$STOCK" | sed 's/^/  /'
sha256sum "$RP/boot-custom.img" > "$RP/boot-custom.img.sha256"

echo
echo "步驟 5 完成"
echo "  待刷檔案 : $RP/boot-custom.img"
echo "  還原檔案 : $STOCK"
echo "  ※ 尚未對手機做任何寫入，步驟 6 需要使用者明確同意。"
