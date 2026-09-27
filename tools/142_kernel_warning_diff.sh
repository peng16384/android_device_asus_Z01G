#!/usr/bin/env bash
#
# 22.2 kernel：比較兩個分支「從頭編譯」時的編譯器警告，找出合併引入的新警告
#
#   bash device/asus/Z01G/tools/142_kernel_warning_diff.sh [舊分支 z01g] [新分支 z01g-cip]
#
# 為什麼要：CIP 合併時，「文字合得進去、語意不對」的地方常常只是警告而不是錯誤。實例：CIP 的
# tty_flip_buffer_push() 用 queue_work() 排 CAF 的 kthread_work（-Wincompatible-pointer-types 只是警告），
# 編譯通過、開機後藍牙 UART 觸發 workqueue WARN。增量編譯只會重編改過的檔案，前幾輪的警告看不到 ->
# 兩個分支各清掉 KERNEL_OBJ 從頭編一次，比較警告集合（去掉行號，避免行號位移造成假差異）。
#
# 結束時切回新分支。out/ 的 kernel 是新分支編的。
set -o pipefail

OLD=${1:-z01g}
NEW=${2:-z01g-cip}
SRC=~/lineage-22.2
K=$SRC/kernel/asus/msm8998
OBJ=$SRC/out/target/product/Z01G/obj/KERNEL_OBJ
W=~/cip-4.4/warn
mkdir -p "$W"

[ -z "$(git -C "$K" status --porcelain)" ] || { echo "!!! kernel 工作樹不乾淨"; exit 1; }
cd "$SRC"
source build/envsetup.sh >/dev/null
breakfast Z01G >/dev/null

for br in "$OLD" "$NEW"; do
    git -C "$K" checkout -q "$br"
    rm -rf "$OBJ"
    start=$(date +%s)
    m bootimage > "$W/$br.log" 2>&1
    rc=$?
    echo "  $br：rc=$rc，$(( ($(date +%s) - start) / 60 )) 分鐘，警告 $(grep -c 'warning:' "$W/$br.log")"
    # 只留 kernel 原始碼的警告，去掉行號與欄位：「檔案: warning: 訊息 [-W旗標]」
    grep -aE "msm8998/[^:]+:[0-9]+:[0-9]+: warning:" "$W/$br.log" \
        | sed -E "s|.*msm8998/||; s|:[0-9]+:[0-9]+: warning:| warning:|" | sort -u > "$W/$br.warn"
done
git -C "$K" checkout -q "$NEW"

comm -13 "$W/$OLD.warn" "$W/$NEW.warn" > "$W/new.warn"
comm -23 "$W/$OLD.warn" "$W/$NEW.warn" > "$W/gone.warn"
echo "  新增的警告 $(wc -l < "$W/new.warn") 條（$W/new.warn），消失的 $(wc -l < "$W/gone.warn") 條"
sed -E 's/.*\[(-W[^]]+)\]$/\1/' "$W/new.warn" | sort | uniq -c | sort -rn | head -20
