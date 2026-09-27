#!/usr/bin/env bash
#
# 下載 LineageOS 22.2 原始碼（在 lineage22 distro 內，~/lineage-22.2）
#
#   bash device/asus/Z01G/tools/121_repo_sync_22.sh
#
# 可重跑：repo sync 本身是增量的，中斷後再跑一次就會接著做。
#
# ## 為什麼 --depth=1
#
# 官方建議 400 GB。淺層同步不下載 git 歷史，原始碼約 120 GB
# （完整歷史的話 .repo 會多出一倍以上）。代價是不能在樹裡 git log / bisect 上游 ——
# 需要歷史的個別專案，之後可以單獨 `git fetch --unshallow`。
#
# ## LFS
#
# 16.0 踩過：repo sync 成功 ≠ LFS 內容到位（webview 的 apk 是 134 bytes 的指標檔）。
# 同步完用 git lfs ls-files 檢查每個有 LFS 的專案，指標檔（開頭 version https://git-lfs）
# 一個都不能有。
set -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
JOBS=${JOBS:-8}
mkdir -p "$SRC"; cd "$SRC"

if [ ! -d .repo ]; then
    echo "=== repo init ==="
    repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 \
        --git-lfs --depth=1 --no-clone-bundle || exit 1
fi

echo "=== repo sync（-j$JOBS）==="
date '+  開始 %F %T'
repo sync -c -j"$JOBS" --no-tags --no-clone-bundle --optimized-fetch --prune --force-sync
rc=$?
date '+  結束 %F %T'
echo "  rc=$rc"
[ $rc -eq 0 ] || exit $rc

echo "=== LFS 檢查 ==="
bad=0
while read -r p; do
    [ -d "$p" ] || continue
    n=$(cd "$p" && git lfs ls-files 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] || continue
    ptr=$(cd "$p" && git lfs ls-files -n 2>/dev/null | while read -r f; do
            [ -f "$f" ] && head -c 40 "$f" | grep -q "^version https://git-lfs" && echo "$f"; done | wc -l)
    printf '  %-60s LFS %4d  指標檔 %d\n' "$p" "$n" "$ptr"
    bad=$((bad + ptr))
done < <(repo list -p)
echo "  LFS 指標檔合計：$bad"
[ $bad -eq 0 ] || { echo "!!! 有 LFS 內容沒下載（repo forall -c git lfs pull）" >&2; exit 2; }

du -sh "$SRC" "$SRC/.repo" 2>/dev/null
df -h / | tail -1
