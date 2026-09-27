#!/usr/bin/env bash
#
# 22.2：ASUS 清單裡哪些 .so / 執行檔，在 22.2 原始碼樹也有同名模組（在 lineage22 distro 內）
#
#   bash device/asus/Z01G/tools/129_asus_vs_source_22.sh
#
# 那些是 AOSP / CAF 自己會編的東西（Oreo 時代 ASUS 一起放進 vendor 映像），收 prebuilt 會
#   - 依賴 22.2 已改名或移除的模組（build graph：depends on undefined module）
#   - 或與原始碼版本同時存在，誰被裝進去看 namespace 與 PRODUCT_PACKAGES
# 列出來人工決定是否加進 tools/125 的 FROM_SOURCE。
#
# 模組名索引：掃 Android.bp 的 name:（第一次跑要幾分鐘，快取在 out/z01g_bp_names.txt）
set -e -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄
LIST=$PROJ/proprietary-files.txt
IDX=$SRC/out/z01g_bp_names.txt
cd "$SRC"

if [ ! -s "$IDX" ] || [ "${REINDEX:-0}" = 1 ]; then
    echo "建模組名索引…"
    find . -path ./out -prune -o -path ./vendor/asus -prune -o -path ./.repo -prune -o \
         -name Android.bp -print0 |
        xargs -0 -P 16 grep -HoE '^\s*name:\s*"[^"]+"' 2>/dev/null |
        sed -E 's|^\./([^:]+)/Android\.bp:\s*name:\s*"([^"]+)"|\2 \1|' |
        sort -u > "$IDX"
    echo "  $(wc -l < "$IDX") 個模組"
fi

grep -vE '^\s*(#|$)' "$LIST" | sed 's/[|;].*//; s/^-//; s/.*://' |
    grep -E '^vendor/(lib|lib64|bin)/' |
    while read -r p; do
        b=$(basename "$p"); stem=${b%.so}
        hit=$(awk -v n="$stem" '$1==n {print $2; exit}' "$IDX")
        if [ -n "$hit" ]; then printf '%-60s %s\n' "$p" "$hit"; fi
    done | sort -k2
# 2026-09-25 刻意留下的（其餘都已加進 tools/125 的 FROM_SOURCE）：
#   libjni / libsdedrm     只是同名：rust 的 jni crate、sm8250 的 display（不在我們的 namespace）
#   libjson                ASUS 的 QTI blob 連的是 Oreo 那版 json-c；換版本 ABI 可能不同，先用原廠的
#   init.qcom.usb.sh       ASUS 的 init.asus.usb.rc 配它；init rc 那一輪再決定
