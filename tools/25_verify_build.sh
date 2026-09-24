#!/usr/bin/env bash
# 驗證編出來的產物
#
#   wsl -- bash $DEVICE_PATH/tools/25_verify_build.sh
#
# 刷機前先在 PC 上確認：
#   - zip 結構完整、內容合理
#   - boot.img 裡的 kernel 真的是我們驗證過的那顆
#   - boot header 參數與原廠一致（尤其 base=0 這個不尋常的值）
#   - 各映像沒有超過分割區大小
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

SRC="$HOME/lineage-16.0"
OUT="$SRC/out/target/product/Z01G"
PROJ=$DEVICE_PATH
ZIP=$(ls -t "$OUT"/lineage-16.0-*-UNOFFICIAL-Z01G.zip 2>/dev/null | head -1)

[ -n "$ZIP" ] || { echo "!!! 找不到 zip" >&2; exit 1; }

echo "=== 產物 ==="
ls -lh "$ZIP" "$OUT"/boot.img "$OUT"/recovery.img 2>/dev/null | sed 's/^/  /'

echo
echo "=== 分割區大小檢查 ==="
awk -v b="$(stat -c %s "$OUT/boot.img")" -v r="$(stat -c %s "$OUT/recovery.img")" '
BEGIN{
  bp=33554432; rp=33554432;
  printf "  boot.img     %12d / %12d  (%.1f%%)  %s\n", b, bp, b/bp*100, (b<=bp?"OK":"!!! 超過");
  printf "  recovery.img %12d / %12d  (%.1f%%)  %s\n", r, rp, r/rp*100, (r<=rp?"OK":"!!! 超過");
}'

echo
echo "=== zip 內容 ==="
unzip -l "$ZIP" | head -20 | sed 's/^/  /'
echo "  ..."
echo "  檔案總數: $(unzip -l "$ZIP" | tail -1 | awk '{print $2}')"

echo
echo "=== zip 完整性 ==="
if unzip -t "$ZIP" > /tmp/ziptest.log 2>&1; then
    echo "  OK（$(grep -c 'testing:' /tmp/ziptest.log) 個項目通過）"
else
    echo "  !!! 有問題"
    tail -5 /tmp/ziptest.log | sed 's/^/    /'
fi

echo
echo "=== boot.img 內容（與自編 kernel 比對）==="
python3 "$PROJ/tools/bootimg.py" info "$OUT/boot.img" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for k in ('page_size','header_version','kernel_size','kernel_addr','ramdisk_size',
          'ramdisk_addr','second_addr','tags_addr','os_version','os_patch_level'):
    print(f'  {k:16s} {d[k]}')
print(f'  cmdline          {d[\"cmdline\"][:90]}...')
"

echo
echo "=== boot.img 裡的 kernel ==="
python3 "$PROJ/tools/kernelcheck.py" "$OUT/boot.img" 2>&1 | sed -n '3,20p'

echo
echo "=== sha256 ==="
sha256sum "$ZIP" "$OUT"/boot.img "$OUT"/recovery.img | sed 's/^/  /'
