#!/usr/bin/env bash
#
# 建立 22.2 的 device/asus/Z01G 骨架：從 OnePlus msm8998-common + dumpling（lineage-22.2）複製
#
#   bash device/asus/Z01G/tools/122_scaffold_z01g_22.sh
#
# 只做一次（目標已存在就中止）。之後的修改都直接在
# device tree 根目錄 上做、進 git —— 第一個 commit 就是這支的輸出，
# 方便之後 diff 出「我們改了 OnePlus 的哪些地方」。
#
# 兩棵合成一棵：ZS551KL 只有一支機型，不拆 common（與 16.0 相同）。
# 不複製的（OnePlus 專屬）：
#   ifaa/（支付寶指紋）、pocketmode/、touch/（OnePlus 觸控 HAL）、livedisplay/（先不要）、
#   lineage.dependencies（hardware/oneplus、OnePlus kernel）、
#   dumpling 的 board-info.txt（OnePlus bootloader 的 assert）、keylayout/gf_input.kl、
#   proprietary-files*.txt（blob 清單另外重做）
set -e -o pipefail

REF=${REF:-$HOME/ref}
C=$REF/android_device_oneplus_msm8998-common
D=$REF/android_device_oneplus_dumpling
OUT=${OUT:?"輸出目錄（這支只在最初建樹時用過一次，留作紀錄）"}

[ -e "$OUT" ] && { echo "!!! $OUT 已存在，這支只在一開始跑一次" >&2; exit 1; }
mkdir -p "$OUT"

echo "=== msm8998-common（$(git -C $C log -1 --format=%h)）==="
for p in Android.bp BoardConfigCommon.mk common.mk config.fs extract-files.py \
         framework_compatibility_matrix.xml manifest.xml setup-makefiles.py \
         system.prop system_ext.prop vendor.prop \
         audio configs init overlay overlay-lineage recovery releasetools rootdir \
         rro_overlays seccomp_policy sepolicy wifi; do
    cp -r "$C/$p" "$OUT/"
done

echo "=== dumpling（$(git -C $D log -1 --format=%h)）-> dumpling/（參考用，逐項併入後刪掉）==="
mkdir -p "$OUT/_dumpling"
for p in Android.bp AndroidProducts.mk BoardConfig.mk device.mk lineage_dumpling.mk vendor.prop \
         audio overlay overlay-lineage rootdir rro_overlays sepolicy; do
    cp -r "$D/$p" "$OUT/_dumpling/"
done

cat > "$OUT/ORIGIN.md" <<EOF
# 來源

這棵樹的第一版（commit「22.2 device tree：OnePlus 原樣」）是下面兩棵的複製，由
tools/122_scaffold_z01g_22.sh 產生：

| | repo | branch | commit |
|---|---|---|---|
| common | LineageOS/android_device_oneplus_msm8998-common | lineage-22.2 | $(git -C $C log -1 --format='%H %cs') |
| dumpling | LineageOS/android_device_oneplus_dumpling | lineage-22.2 | $(git -C $D log -1 --format='%H %cs') |

授權：Apache-2.0（各檔案標頭）。dumpling 的檔案先放 _dumpling/，逐項併入後刪除。
EOF
find "$OUT" -type f | wc -l
