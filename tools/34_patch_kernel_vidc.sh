#!/usr/bin/env bash
# kernel patch：補上 msm_vidc.h 缺少的 HDR transfer 列舉
#
#   wsl -- bash $DEVICE_PATH/tools/34_patch_kernel_vidc.sh
#
# 問題：
#   hardware/qcom/media-caf/msm8998/mm-video-v4l2/vidc/vdec/src/omx_vdec_v4l2.cpp
#     error: use of undeclared identifier 'MSM_VIDC_TRANSFER_SMPTE_ST2084'
#     error: use of undeclared identifier 'MSM_VIDC_TRANSFER_HLG'
#
#   LineageOS 的 media-caf 對應的是較新的 CAF msm-4.4，而 ASUS 1911.117 的
#   include/uapi/media/msm_vidc.h 列舉停在 MSM_VIDC_TRANSFER_BT_2020_12 = 15。
#
# 為什麼這三個值是確定的：
#   這個列舉直接對應 H.273 / HEVC VUI 的 transfer_characteristics 標準表，
#   現有的 1..15 全部與該表一致（1=BT709、7=SMPTE240M、13=sRGB、14/15=BT2020）。
#   依該表：16 = SMPTE ST 2084 (PQ)、17 = SMPTE ST 428-1、18 = ARIB STD-B67 (HLG)。
#   較新的 CAF msm-4.4 tag 用的也是這三個值。
#
# 為什麼之前編得過：
#   第一次完整編譯時，libOmxVdec 在 kernel 的 headers_install 完成「之前」就編掉了，
#   於是用到 bionic 內建的較新 kernel headers。kernel 產物存在之後，
#   KERNEL_OBJ/usr/include 優先，才暴露出這個差異。屬於建置順序造成的偶然。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -o pipefail

# 兩份都要改：~/zs551kl 是原始工作樹（有自己的 git），
# ~/lineage-16.0/kernel/asus/msm8998 是 cp -al 出來的硬連結複本。
# sed -i 會斷開硬連結，所以兩邊分別處理。
FILES=(
  "$HOME/zs551kl/kernel/msm-4.4/include/uapi/media/msm_vidc.h"
  "$HOME/lineage-16.0/kernel/asus/msm8998/include/uapi/media/msm_vidc.h"
)

ANCHOR='MSM_VIDC_TRANSFER_BT_2020_12 = 15,'
ADD='	MSM_VIDC_TRANSFER_SMPTE_ST2084 = 16,\n	MSM_VIDC_TRANSFER_SMPTE_ST_428 = 17,\n	MSM_VIDC_TRANSFER_HLG = 18,'

for f in "${FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "  [跳過] 找不到 $f"
        continue
    fi
    if grep -q "MSM_VIDC_TRANSFER_SMPTE_ST2084" "$f"; then
        echo "  [已有] $f"
        continue
    fi
    if ! grep -q "$ANCHOR" "$f"; then
        echo "  !!! 找不到錨點 '$ANCHOR'：$f" >&2
        exit 1
    fi
    sed -i "s|\t$ANCHOR|\t$ANCHOR\n$ADD|" "$f"
    echo "  [已補] $f"
done

echo
echo "=== 結果 ==="
grep -n "MSM_VIDC_TRANSFER_BT_2020_12\|MSM_VIDC_TRANSFER_SMPTE_ST2084\|MSM_VIDC_TRANSFER_SMPTE_ST_428\|MSM_VIDC_TRANSFER_HLG" \
    "$HOME/lineage-16.0/kernel/asus/msm8998/include/uapi/media/msm_vidc.h" | sed 's/^/  /'

echo
echo "=== 在 kernel 原始碼樹留下 commit（方便日後產生 patch）==="
K="$HOME/zs551kl/kernel/msm-4.4"
if [ -d "$K/.git" ]; then
    git -C "$K" add include/uapi/media/msm_vidc.h
    if git -C "$K" diff --cached --quiet; then
        echo "  沒有變更"
    else
        git -C "$K" commit -q -m "uapi: msm_vidc: 補上 HDR transfer 列舉 (ST2084 / ST428 / HLG)

LineageOS 16.0 的 hardware/qcom/media-caf/msm8998 需要這三個值，
ASUS 1911.117 的 header 停在 MSM_VIDC_TRANSFER_BT_2020_12 = 15。

值依 H.273 / HEVC VUI transfer_characteristics 標準表，
與較新的 CAF msm-4.4 tag 一致。"
        git -C "$K" log --oneline -1 | sed 's/^/  /'
    fi
fi

echo
echo "完成。清掉 libOmxVdec 的中間產物後重編："
echo "  rm -rf ~/lineage-16.0/out/target/product/Z01G/obj*/SHARED_LIBRARIES/libOmxVdec_intermediates"
