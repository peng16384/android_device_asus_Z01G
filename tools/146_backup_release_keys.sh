#!/usr/bin/env bash
#
# 發布用私鑰（~/.android-certs）的加密備份 —— 要在終端機裡互動執行（會問兩次密碼）：
#
#   bash device/asus/Z01G/tools/146_backup_release_keys.sh
#
# 產物：~/Z01G_release_keys_backup.tar.gz.gpg，OUT= 可改（放到別的磁碟 / 離線保存）（AES256，對稱加密；不在任何 repo 裡）
#
# 為什麼不用一行 `tar | gpg`：資料走 stdin 時 gpg 找不到能互動的終端機問密碼，會直接失敗
# （2026-09-27 實測：沒有提示、也沒有產生檔案）。先打包成權限 600 的暫存檔，stdin 留給密碼輸入。
set -e -o pipefail

K=$HOME/.android-certs
OUT=${OUT:-$HOME/Z01G_release_keys_backup.tar.gz.gpg}
[ -d "$K" ] || { echo "!!! 找不到 $K"; exit 1; }
[ ! -e "$OUT" ] || { echo "!!! $OUT 已經存在，不覆蓋"; exit 1; }
[ -t 0 ] || { echo "!!! 要在終端機裡互動執行（gpg 要問密碼）"; exit 1; }

export GPG_TTY=$(tty)
umask 077
TMP=$(mktemp "$HOME/.keys-backup.XXXXXX.tar.gz")
trap 'rm -f "$TMP"' EXIT
tar -C "$HOME" -czf "$TMP" .android-certs
echo "打包：$(tar -tzf "$TMP" | grep -vc '/$') 個檔。接著 gpg 會問兩次密碼（這個密碼自己保管，還原時要用）"

gpg --symmetric --cipher-algo AES256 --pinentry-mode loopback -o "$OUT" "$TMP"

echo
echo "=== 驗證：用剛才的密碼解開、與原檔逐 byte 比對（不寫出任何檔案）==="
echo "（會再問一次密碼）"
if gpg --pinentry-mode loopback --decrypt "$OUT" 2>/dev/null | cmp -s - "$TMP"; then
    echo "  OK：$(du -h "$OUT" | cut -f1)  $OUT"
else
    echo "!!! 解開的內容與原檔不同（密碼打錯？），刪掉 $OUT 重做"; exit 1
fi
