#!/usr/bin/env bash
# 找出 vendor/asus/Z01G 的 blob 模組與 LineageOS 原始碼的名稱衝突
#
#   wsl -- bash $DEVICE_PATH/tools/19_find_module_conflicts.sh
#
# 起因：m nothing 報
#   error: vendor/asus/Z01G: MODULE.TARGET.JAVA_LIBRARIES.qti-telephony-common
#          already defined by hardware/lineage/telephony
#
# LineageOS 有些 QTI 元件是從原始碼編的（hardware/lineage/telephony、
# vendor/codeaurora/telephony 等），那些就不該再當 blob 塞進去。
#
# 一個一個試太慢（每次 m nothing 要 13 秒，而且只報第一個），
# 這支腳本直接比對模組名稱，一次找齊。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

SRC="$HOME/lineage-16.0"
VMK="$SRC/vendor/asus/Z01G/Android.mk"
OUT=$DEVICE_PATH/blobs/module_conflicts.txt

[ -f "$VMK" ] || { echo "!!! 找不到 $VMK" >&2; exit 1; }
cd "$SRC"

echo "=== 我們的 blob 模組 ==="
grep -oP '^LOCAL_MODULE := \K.*' "$VMK" | sort -u > /tmp/ours.txt
echo "  $(wc -l < /tmp/ours.txt) 個"

echo
echo "=== 掃描樹中其他 LOCAL_MODULE / name 定義 ==="
# Android.mk 的 LOCAL_MODULE、Android.bp 的 name:
grep -rhoP '^\s*LOCAL_MODULE\s*:=\s*\K\S+' \
    --include='Android.mk' \
    device hardware vendor frameworks packages external system 2>/dev/null \
    | sort -u > /tmp/theirs_mk.txt
grep -rhoP '^\s*name:\s*"\K[^"]+' \
    --include='Android.bp' \
    device hardware vendor frameworks packages external system 2>/dev/null \
    | sort -u > /tmp/theirs_bp.txt
cat /tmp/theirs_mk.txt /tmp/theirs_bp.txt | sort -u > /tmp/theirs.txt
echo "  樹中共 $(wc -l < /tmp/theirs.txt) 個模組名"

echo
echo "=== 衝突（我們的 blob 與別處同名）==="
: > "$OUT"
while IFS= read -r m; do
    # 排除我們自己那份
    hits=$(grep -rl --include='Android.mk' -P "^\s*LOCAL_MODULE\s*:=\s*${m}\s*$" \
            device hardware vendor frameworks packages external system 2>/dev/null \
            | grep -v '^vendor/asus/Z01G/')
    hits_bp=$(grep -rl --include='Android.bp' -P "^\s*name:\s*\"${m}\"" \
            device hardware vendor frameworks packages external system 2>/dev/null)
    all=$(printf '%s\n%s\n' "$hits" "$hits_bp" | grep -v '^$' | sort -u)
    if [ -n "$all" ]; then
        printf '%s\n' "$m" >> "$OUT"
        printf '  %-45s <- %s\n' "$m" "$(echo "$all" | tr '\n' ' ')"
    fi
done < <(grep -F -x -f /tmp/theirs.txt /tmp/ours.txt)

echo
N=$(wc -l < "$OUT")
echo "共 $N 個衝突，已寫到 $OUT"
if [ "$N" -gt 0 ]; then
    echo
    echo "這些模組 LineageOS 會自己從原始碼編，要從 proprietary-files.txt 移除。"
fi
exit 0
