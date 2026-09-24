#!/usr/bin/env bash
# 補抓 Git LFS 的實際內容
#
#   wsl -- bash $DEVICE_PATH/tools/23_fetch_lfs.sh
#
# 起因：編到 50% 時 webview 的 APK 簽章失敗
#   java.util.zip.ZipException: zip END header not found
# 一看 external/chromium-webview/prebuilt/arm64/webview.apk 只有 134 bytes：
#   version https://git-lfs.github.com/spec/v1
#   oid sha256:446ead...
#   size 243509357
# 是 LFS 的指標檔，不是真正的 APK。
#
# 注意 find 的 -size：單位是 1K 區塊且無條件進位，-size -1k 只會匹配 0 byte 的檔案。
# 134 bytes 的指標檔要用 -size -4096c（以 byte 為單位）才抓得到。
#
# 也就是說：裝了 git-lfs 讓 repo sync 不再報錯（checkout 過得去），
# 但實際的大檔還是沒下載。要在各個 LFS repo 裡另外跑 git lfs pull。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

SRC="$HOME/lineage-16.0"
cd "$SRC"

echo "=== 找出還是指標檔的 LFS 檔案 ==="
# LFS 指標檔很小且開頭固定，用大小先過濾再確認內容，比全樹 grep 快得多
mapfile -t PTRS < <(
    find . -path ./.repo -prune -o -type f -size -4096c -print 2>/dev/null \
    | while read -r f; do
        if head -c 45 "$f" 2>/dev/null | grep -q '^version https://git-lfs'; then
            echo "$f"
        fi
      done
)
echo "  找到 ${#PTRS[@]} 個"
for p in "${PTRS[@]}"; do
    printf '    %-60s %s bytes\n' "$p" "$(stat -c %s "$p")"
done

if [ "${#PTRS[@]}" -eq 0 ]; then
    echo "  沒有待抓的 LFS 檔案"
    exit 0
fi

echo
echo "=== 推出需要 git lfs pull 的 repo ==="
mapfile -t REPOS < <(
    for p in "${PTRS[@]}"; do
        d=$(dirname "$p")
        # 往上找到含 .git 的目錄
        while [ "$d" != "." ] && [ ! -e "$d/.git" ]; do d=$(dirname "$d"); done
        [ -e "$d/.git" ] && echo "$d"
    done | sort -u
)
printf '    %s\n' "${REPOS[@]}"

echo
echo "=== 逐一 git lfs pull ==="
FAIL=0
for r in "${REPOS[@]}"; do
    echo "  --- $r"
    if ( cd "$r" && git lfs pull 2>&1 | tail -3 | sed 's/^/      /' ); then
        # 確認真的抓下來了
        ( cd "$r" && find . -type f -size -4096c 2>/dev/null \
            | while read -r f; do
                head -c 45 "$f" 2>/dev/null | grep -q '^version https://git-lfs' && echo "      !!! 仍是指標檔: $f"
              done )
    else
        echo "      !!! 失敗"
        FAIL=1
    fi
done

echo
echo "=== 結果 ==="
for p in "${PTRS[@]}"; do
    printf '    %-60s %s\n' "$p" "$(du -h "$p" 2>/dev/null | cut -f1)"
done
exit "$FAIL"
