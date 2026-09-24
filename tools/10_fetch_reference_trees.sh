#!/usr/bin/env bash
# clone 參考 device tree
#
# clone 到 WSL ext4 的 ~/zs551kl/reference/，不放進專案 git
#（它們是別人的 repo，巢狀 git 會弄髒我們的 git status）
#
# 只做 --depth 1，我們要的是「目前長什麼樣」而不是歷史。
set -uo pipefail

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true

REF="$HOME/zs551kl/reference"
mkdir -p "$REF"
cd "$REF"

get() {
    local dir="$1" url="$2" branch="${3:-}"
    if [ -d "$dir/.git" ]; then
        echo "  [已存在] $dir"
        return 0
    fi
    local args=(--depth 1 --quiet)
    [ -n "$branch" ] && args+=(-b "$branch")
    if timeout 300 git clone "${args[@]}" "$url" "$dir" 2>&1 | sed 's/^/      /'; then
        local b
        b=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
        printf '  [OK]     %-34s branch=%-14s %s\n' "$dir" "$b" "$(du -sh "$dir" | cut -f1)"
    else
        echo "  [失敗]   $dir"
        rm -rf "$dir"
    fi
}

echo "=== A. 同機種 Z01G（fstab / 分割資訊最準）==="
get Z01G_shakalaca https://github.com/shakalaca/android_device_asus_Z01G
get Z01G_twrp      https://github.com/TeamWin/android_device_asus_Z01G

echo
echo "=== B. msm8998 骨架來源（LineageOS 16.0）==="
get dumpling       https://github.com/LineageOS/android_device_oneplus_dumpling        lineage-16.0
get oneplus_common https://github.com/LineageOS/android_device_oneplus_msm8998-common  lineage-16.0
get sagit          https://github.com/LineageOS/android_device_xiaomi_sagit            lineage-16.0
get xiaomi_common  https://github.com/LineageOS/android_device_xiaomi_msm8998-common   lineage-16.0

echo
echo "=== 取得的 proprietary-files.txt ==="
find "$REF" -name 'proprietary-files*.txt' -printf '%p  (%s bytes)\n' 2>/dev/null | sed 's#'"$REF"'/#  #'

echo
echo "=== 各樹的頂層檔案 ==="
for d in "$REF"/*/; do
    [ -d "$d" ] || continue
    echo "  --- $(basename "$d")"
    ls -1 "$d" | grep -vE '^\.git$' | head -20 | sed 's/^/      /'
done

echo
echo "參考樹位置：$REF"
