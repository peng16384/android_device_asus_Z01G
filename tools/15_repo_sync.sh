#!/usr/bin/env bash
# 同步 LineageOS 16.0 原始碼
#
# 以一般使用者執行，不要用 root：
#   wsl -- bash $DEVICE_PATH/tools/15_repo_sync.sh
#
# 必須放在 WSL 的 ext4（NTFS 不分大小寫，AOSP 有同名不同大小寫的檔案會直接爆）。
#
# 約 60–80 GB，依網速可能要 1–3 小時。可重複執行（repo sync 會續傳）。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -uo pipefail

SRC="$HOME/lineage-16.0"
MANIFEST_URL="https://github.com/LineageOS/android.git"
BRANCH="lineage-16.0"
LOG=$DEVICE_PATH/docs/repo_sync.log
JOBS=8          # 對 GitHub 不要開太大，容易被限流

mkdir -p "$(dirname "$LOG")" "$SRC"
cd "$SRC"

echo "=== 環境 ==="
echo "  目錄   : $SRC  ($(df -T . | tail -1 | awk '{print $2}'))"
echo "  可用   : $(df -h . | tail -1 | awk '{print $4}')"
echo "  repo   : $(command -v repo)"
echo "  java   : $(java -version 2>&1 | head -1)"
echo "  log    : $LOG"
echo

if [ ! -d .repo ]; then
    echo "=== repo init ==="
    # 注意：--git-lfs 是布林旗標，不吃 =false（給值會被 repo 拒絕）
    repo init -u "$MANIFEST_URL" -b "$BRANCH" --no-clone-bundle 2>&1 | tail -20
    RC=${PIPESTATUS[0]}
    if [ "$RC" -ne 0 ]; then
        echo "!!! repo init 失敗 (rc=$RC)" >&2
        exit "$RC"
    fi
else
    echo "=== .repo 已存在，跳過 init ==="
fi

echo
echo "=== 檢查 manifest 有沒有用已停用的 git:// 協定 ==="
# GitHub 2021 年停用了 git:// 協定，而 lineage-16.0 是 2018–2019 年的 manifest
if grep -rn 'fetch="git://' .repo/manifests/*.xml 2>/dev/null | head -5; then
    echo "  !!! 發現 git:// —— sync 會失敗，需要改成 https://"
else
    echo "  沒有 git://，OK"
fi

echo
echo "=== repo sync（-j$JOBS，完整輸出在 $LOG）==="
date '+  開始 %F %T'
repo sync -c -j"$JOBS" --no-tags --no-clone-bundle --force-sync --fail-fast > "$LOG" 2>&1
RC=$?
date '+  結束 %F %T'

echo
if [ "$RC" -ne 0 ]; then
    echo "!!! repo sync 失敗 (rc=$RC)，最後 30 行："
    tail -30 "$LOG"
    exit "$RC"
fi

echo "=== 結果 ==="
du -sh "$SRC" 2>/dev/null | sed 's/^/  總大小 /'
echo "  專案數 $(repo list 2>/dev/null | wc -l)"
df -h . | tail -1 | sed 's/^/  剩餘 /'

echo
echo "=== 補抓 Git LFS 內容 ==="
# repo sync 成功 != LFS 內容到位。
# 裝了 git-lfs 只是讓 checkout 不報錯，實際大檔仍可能只是 134 bytes 的指標檔，
# 要等編到 50% 簽 webview APK 時才會以 "zip END header not found" 爆出來。
bash $DEVICE_PATH/tools/23_fetch_lfs.sh 2>&1 | sed 's/^/  /'

echo
echo "sync 完成。"
