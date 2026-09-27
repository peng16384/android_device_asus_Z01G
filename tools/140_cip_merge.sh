#!/usr/bin/env bash
#
# 22.2 kernel：把 CIP 4.4（上游 4.4.302 之後的長期維護，SLTS 到 2027）的修補合併進 kernel/asus/msm8998
#
#   bash device/asus/Z01G/tools/140_cip_merge.sh [CIP 標籤，預設 v4.4.302-cip114] [base，預設 v4.4.302-cip68]
#
# ⚠ base 不能用上游的 v4.4.302：CIP 分支從 2017 年起就帶著大量「為 Renesas 板子回移的新功能」（OPP、clk 的新 API…），
#   那些從沒進過上游 4.4.302；v4.4.302..cipNNN 的差異會把它們一起算進來（opp/core.c +343 行就是）。
#   base = CIP 合併上游 4.4.302 的第一個標籤 v4.4.302-cip68（2022-02-14）：base -> theirs 只剩 4.4.302 之後的修補；
#   我們的檔案沒有那些 CIP 功能，合併時會照 ours 保留「沒有」，只有修補剛好碰到那些功能的地方才衝突
#
# 前提：~/cip-4.4 已淺層 fetch 了 base 與 CIP 標籤（git fetch --shallow-since=2022-02-01 ...）；
#       out/ 裡有編過的 kernel（KERNEL_OBJ 的 .cmd 用來判斷哪些檔案有被編到）。
#
# 為什麼不能直接 git merge：kernel repo 是從 4.4.302 的原始碼快照建的（21 個 commit），跟上游沒有共同歷史。
#
# 做法：
#   1. 範圍 = CIP 修改過的檔案 ∩ 這顆 kernel 實際用到的檔案（KERNEL_OBJ/**/.*.o.cmd 列的每個 .c/.h/.S）。
#      CIP 的 5,848 個 commit 改了 3,773 個檔案，大多是其他架構與這台沒有的驅動；刪掉的只有 firmware/ 的舊韌體
#   2. 在暫存 repo 做一次三方合併：base = CIP 的 v4.4.302-cip68、ours = 我們的檔案、theirs = CIP 的檔案，
#      `git merge -X diff-algorithm=histogram`（WSL 的 git 2.25 的 merge-file 只有 myers，會默默丟修改，見 merge3.sh）
#   3. 結果放到 kernel repo 的 z01g-cip 分支；衝突的檔案保留 diff3 標記，列出來人工處理
#
# 不 commit、不動 z01g 分支。
set -e -o pipefail

TAG=${1:-v4.4.302-cip114}
BASE=${2:-v4.4.302-cip68}
CIP=~/cip-4.4
K=~/lineage-22.2/kernel/asus/msm8998
OBJ=${OBJ:-$HOME/lineage-22.2/out-release/target/product/Z01G/obj/KERNEL_OBJ}   # 開發用的 out/ 已刪（2026-09-27）

cd "$CIP"
for r in "$TAG" "$BASE"; do git rev-parse -q --verify "$r" >/dev/null || { echo "!!! $CIP 沒有 $r"; exit 1; }; done

# 1. 範圍
find "$OBJ" -name '.*.o.cmd' -print0 | xargs -0 cat 2>/dev/null \
    | grep -aoE "kernel/asus/msm8998/[^ :\\\\]+\.(c|h|S)" | sed "s|.*kernel/asus/msm8998/||" | sort -u > used_files.txt
# ↑ 不綁前綴：發布版（tools/144）是從 /src/lineage-22.2 編的，.o.cmd 裡的路徑不是 $K
git diff --diff-filter=M --name-only "$BASE" "$TAG" | sort > cip_modified.txt
comm -12 cip_modified.txt used_files.txt > relevant.txt
echo "  範圍：CIP 修改 $(wc -l < cip_modified.txt) 個檔、這顆 kernel 用到 $(wc -l < used_files.txt) 個 -> 交集 $(wc -l < relevant.txt)"

# 2. 三方合併
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
git -C "$T" init -q
git -C "$T" config user.email cip@localhost; git -C "$T" config user.name cip
git -C "$T" config core.autocrlf false; git -C "$T" config merge.conflictstyle diff3
git -C "$T" config merge.renameLimit 0
put() {  # put <ref|OURS>
    while read -r f; do
        mkdir -p "$T/$(dirname "$f")"
        if [ "$1" = OURS ]; then cp "$K/$f" "$T/$f"; else git show "$1:$f" > "$T/$f"; fi
    done < relevant.txt
    git -C "$T" add -A
}
put "$BASE";  git -C "$T" commit -q -m base
git -C "$T" checkout -q -b ours;  put OURS; git -C "$T" commit -q --allow-empty -m ours
git -C "$T" checkout -q master; git -C "$T" checkout -q -b theirs; put "$TAG"; git -C "$T" commit -q --allow-empty -m theirs
git -C "$T" checkout -q ours
set +e
git -C "$T" merge -q --no-edit -X diff-algorithm=histogram -X no-renames theirs > "$CIP/merge.log" 2>&1
set -e
git -C "$T" diff --name-only --diff-filter=U > "$CIP/conflicts.txt" || true
echo "  衝突：$(wc -l < "$CIP/conflicts.txt") 個檔（清單：$CIP/conflicts.txt）"

# 3. 放進 kernel 的 z01g-cip 分支
cd "$K"
[ -z "$(git status --porcelain)" ] || { echo "!!! kernel 工作樹不乾淨"; exit 1; }
git checkout -q -B z01g-cip z01g
while read -r f; do cp "$T/$f" "$K/$f"; done < "$CIP/relevant.txt"
echo "  已放進 $K（分支 z01g-cip，未 commit）：$(git status --porcelain | wc -l) 個檔有變動"
