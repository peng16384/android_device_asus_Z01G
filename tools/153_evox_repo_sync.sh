#!/usr/bin/env bash
#
# Evolution X vic（Android 15，基底 LineageOS 22.2）：下載原始碼（在 lineage22 distro 內，~/evox-vic）
#
#   bash device/asus/Z01G/tools/153_evox_repo_sync.sh
#
# 可重跑：repo sync 是增量的，中斷後再跑一次就會接著做。
#
# 與 tools/121（LineageOS 22.2）同一套做法：--depth=1（不下載 git 歷史）、--git-lfs，
# 結束後檢查 LFS 指標檔（16.0 踩過：repo sync 成功 ≠ LFS 內容到位）。
# Evolution X 內建 GApps（vendor/gms），那一包是 LFS，特別要檢查。
#
# 與 LineageOS 的差別（manifest 看過）：build/make、frameworks/native、hardware/interfaces、
# packages/apps/Updater、device/lineage/sepolicy 都換成 Evolution X 自己的 fork；
# vendor/lineage 的內容是 vendor_evolution。我們在 22.2 的 4 個 patch 要重新確認套不套得上（tools/136）。
set -o pipefail

SRC=${SRC:-$HOME/evox-vic}
JOBS=${JOBS:-8}
mkdir -p "$SRC"; cd "$SRC"

if [ ! -d .repo ]; then
    echo "=== repo init ==="
    repo init -u https://github.com/Evolution-X/manifest -b vic \
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
