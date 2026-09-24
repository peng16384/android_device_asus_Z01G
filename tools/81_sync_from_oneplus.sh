#!/usr/bin/env bash
# 從 LineageOS 的 OnePlus msm8998 kernel 取單一檔案覆蓋我們的版本。
#
# 用途：qcacld-3.0 是從那棵樹搬過來的，會用到一些 ASUS 的 msm-4.4
# 樹裡比較舊、還沒有的平台 API。逐個補比整棵樹換掉安全得多。
#
# 用法：
#     bash tools/81_sync_from_oneplus.sh <kernel 樹內的相對路徑> [更多路徑...]
# 例：
#     bash tools/81_sync_from_oneplus.sh include/net/cnss_utils.h \
#          drivers/net/wireless/cnss_utils/cnss_utils.c
#
# 每次都會先印 diff 摘要，再覆蓋；最後統一 commit 並同步到 AOSP 樹。
set -euo pipefail

BASE=https://raw.githubusercontent.com/LineageOS/android_kernel_oneplus_msm8998/lineage-16.0
KSRC="$HOME/zs551kl/kernel/msm-4.4"
KAOSP="$HOME/lineage-16.0/kernel/asus/msm8998"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

[ $# -gt 0 ] || { echo "用法：$0 <相對路徑> [...]" >&2; exit 1; }

changed=()
for rel in "$@"; do
    out="$TMP/$(echo "$rel" | tr / _)"
    if ! curl -sS --fail --max-time 30 "$BASE/$rel" -o "$out"; then
        echo "  !! 取不到 $rel"; continue
    fi
    if [ -f "$KSRC/$rel" ] && cmp -s "$KSRC/$rel" "$out"; then
        echo "  =  $rel（內容相同）"
        continue
    fi
    n=$(diff -u "$KSRC/$rel" "$out" 2>/dev/null | grep -cE '^[+-][^+-]' || true)
    echo "  +  $rel（$n 行差異）"
    mkdir -p "$(dirname "$KSRC/$rel")"
    cp -f "$out" "$KSRC/$rel"
    changed+=("$rel")
done

[ ${#changed[@]} -gt 0 ] || { echo "沒有變更"; exit 0; }

cd "$KSRC"
git add -A
git commit -q -m "從 LineageOS OnePlus msm8998 同步平台 API

$(printf '  %s\n' "${changed[@]}")

qcacld-3.0 是從那棵樹搬過來的，會用到 ASUS 這棵 msm-4.4 還沒有的平台 API。"
echo "  commit: $(git log -1 --format='%h %s' | head -1)"

rsync -a --delete --exclude '.git' --exclude 'out' "$KSRC/" "$KAOSP/"
echo "  已同步到 AOSP 樹"
