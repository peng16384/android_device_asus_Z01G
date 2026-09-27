#!/usr/bin/env bash
#
# 22.2：把 kernel 的修改匯出成可以公開的分支（GPL：發布 boot.img 就要能給對應的原始碼）
#
#   bash device/asus/Z01G/tools/149_export_kernel_public.sh
#
# 產物：~/kernel-public（獨立的 clone），分支 lineage-22.2-z01g = 我們 z01g 分支上的每一個 commit，
#       只把作者 / 提交者換成公開身分（時間保留）。本機的 kernel/asus/msm8998 與 origin 都不動。
#
# 基底 d152ec62 是 LineageOS/android_kernel_qcom_msm8998（lineage-20）的 commit（kernel 移植紀錄
# 「新 kernel 的底」一節），而這個 clone 是 shallow 的
# -> 在 GitHub 上 fork 那個 repo（可改名成 android_kernel_asus_msm8998），再從這裡 push 這個分支
#    （fork 裡已經有基底，shallow 推得上去）：
#       cd ~/kernel-public
#       git remote add public https://github.com/peng16384/android_kernel_asus_msm8998.git   # fork 的網址
#       git push public lineage-22.2-z01g
#
# 檢查（任一不過就停，不留分支）：
#   - 範圍內每個 commit 的作者 / 提交者都已換掉；上游的 commit（基底之前）一個都沒碰
#   - 換身分前後的 tree 完全相同（只改 metadata）
#   - commit 訊息、作者欄、整個 diff（基底 -> 頂端）不含 ~/pii 的樣式
set -e -o pipefail

KSRC=${KSRC:-$HOME/lineage-22.2/kernel/asus/msm8998}
BR=${BR:-z01g}
BASE=${BASE:-d152ec623891d141ad5231ef5033c068e82ba1b1}
OUT=${OUT:-$HOME/kernel-public}
PUB_BR=lineage-22.2-z01g
PUB_NAME=peng16384
PUB_MAIL=158992409+peng16384@users.noreply.github.com
PII=${PII:-$HOME/pii}

[ -f "$PII/public.txt" ] && [ -f "$PII/secret.txt" ] || { echo "!!! 找不到 $PII 的樣式檔"; exit 1; }
[ ! -e "$OUT" ] || { echo "!!! $OUT 已經存在（要重做就先自己刪掉它）"; exit 1; }

echo "=== 1. clone（$KSRC 的 $BR）==="
git clone -q --no-local --single-branch -b "$BR" "$KSRC" "$OUT"
cd "$OUT"
git remote remove origin
rm -rf .git/refs/remotes          # remove 會留下斷掉的 origin/HEAD，gc 會因它失敗
git checkout -q -b "$PUB_BR"
git branch -q -D "$BR"
n=$(git rev-list --count "$BASE"..HEAD)
echo "  基底之後 $n 個 commit；基底：$(git log -1 --format='%h %an: %s' "$BASE")"
TREE_BEFORE=$(git rev-parse HEAD^{tree})

echo "=== 2. 換身分（只動 $BASE 之後的）==="
export FILTER_BRANCH_SQUELCH_WARNING=1
git filter-branch -f --env-filter "
    export GIT_AUTHOR_NAME='$PUB_NAME' GIT_AUTHOR_EMAIL='$PUB_MAIL'
    export GIT_COMMITTER_NAME='$PUB_NAME' GIT_COMMITTER_EMAIL='$PUB_MAIL'
" -- "$BASE"..HEAD >/dev/null
rm -rf .git/refs/original
git reflog expire --expire=now --all
git gc -q --prune=now

fail=0
bad() { echo "  !!!   $1"; fail=1; }
echo "=== 3. 檢查 ==="
[ "$(git rev-parse HEAD^{tree})" = "$TREE_BEFORE" ] && echo "  OK    tree 與原分支完全相同" || bad "tree 變了"
[ "$(git rev-list --count "$BASE"..HEAD)" = "$n" ] && echo "  OK    仍是 $n 個 commit" || bad "commit 數變了"
git merge-base --is-ancestor "$BASE" HEAD && echo "  OK    基底沒被改寫" || bad "基底被改寫了"
others=$(git log --format='%an <%ae>%n%cn <%ce>' "$BASE"..HEAD | sort -u | grep -vx "$PUB_NAME <$PUB_MAIL>" || true)
[ -z "$others" ] && echo "  OK    作者 / 提交者全是 $PUB_NAME" || bad "還有別的身分：$others"
scan() {   # $1 = 樣式檔；看 commit 訊息 + 作者欄 + 完整 diff
    { git log --format='%an %ae %cn %ce%n%B' "$BASE"..HEAD; git diff "$BASE" HEAD; } | grep -caiF -f "$1" || true
}
p=$(scan "$PII/public.txt"); s=$(scan "$PII/secret.txt")
[ "$p" = 0 ] && echo "  OK    public 樣式：0" || bad "public 樣式命中 $p 行"
[ "$s" = 0 ] && echo "  OK    secret 樣式：0" || bad "secret 樣式命中 $s 行"

if [ $fail != 0 ]; then
    cd / && rm -rf "$OUT"
    echo "!!! 沒過，已刪掉 $OUT"; exit 1
fi
echo
git log --format='  %h %an %ad %s' --date=short -3
echo "  ..."
echo
echo "完成：$OUT 的 $PUB_BR（頂端 $(git rev-parse --short HEAD)）。push 方式見本檔開頭。"
