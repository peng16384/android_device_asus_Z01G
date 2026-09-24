#!/usr/bin/env bash
# 把 qcacld-3.0 接進我們的 kernel 樹。
#
# 背景見 tools/75_fetch_qcacld.sh 的檔頭：原廠的 qca_cld3_wlan.ko 因為
# modversions CRC 全不合而不能用，必須自己編。
#
# 三個目錄必須是 drivers/staging/ 下的同層目錄 —— qcacld 的 Kbuild 是寫死相對路徑：
#     WLAN_COMMON_ROOT := ../qca-wifi-host-cmn
#
# 編成 built-in（CONFIG_QCA_CLD_WLAN=y）而不是模組，理由：
#   1. 完全繞過模組簽章（CONFIG_MODULE_SIG_FORCE=y）
#   2. LineageOS 的 OnePlus msm8998（同平台同版本）就是這樣設的
#   3. 驅動在 kernel 裡，開機就會註冊到 icnss，不必靠 HAL insmod
#      —— HAL 那邊改用 WIFI_DRIVER_STATE_CTRL_PARAM 寫 sysfs 觸發
set -euo pipefail

SRC="$HOME/zs551kl/qcacld_src/drivers/staging"
KSRC="$HOME/zs551kl/kernel/msm-4.4"
KAOSP="$HOME/lineage-16.0/kernel/asus/msm8998"
STG="$KSRC/drivers/staging"
DEF="$KSRC/arch/arm64/configs/zs551kl-perf_defconfig"

for d in qcacld-3.0 qca-wifi-host-cmn fw-api; do
    [ -d "$SRC/$d" ] || { echo "!!! 找不到 $SRC/$d，先跑 tools/75_fetch_qcacld.sh" >&2; exit 1; }
done

echo "=== 1. 複製三個目錄 ==="
for d in qcacld-3.0 qca-wifi-host-cmn fw-api; do
    if [ -d "$STG/$d" ]; then
        echo "  = $d 已存在，跳過"
    else
        cp -a "$SRC/$d" "$STG/$d"
        echo "  + $d（$(find "$STG/$d" -type f | wc -l) 個檔案）"
    fi
done

echo
echo "=== 2. drivers/staging/Kconfig ==="
if grep -q 'qcacld-3.0/Kconfig' "$STG/Kconfig"; then
    echo "  = 已經接好"
else
    # 插在 endif # STAGING 之前
    python3 - "$STG/Kconfig" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding='utf-8', newline='').read()
anchor = 'endif # STAGING'
add = ('source "drivers/staging/qcacld-3.0/Kconfig"\n\n' + anchor)
assert anchor in s, 'Kconfig 裡找不到 endif # STAGING'
io.open(p, 'w', encoding='utf-8', newline='\n').write(s.replace(anchor, add, 1))
PY
    echo "  + source \"drivers/staging/qcacld-3.0/Kconfig\""
fi

echo
echo "=== 3. drivers/staging/Makefile ==="
if grep -q 'qcacld-3.0/' "$STG/Makefile"; then
    echo "  = 已經接好"
else
    printf 'obj-$(CONFIG_QCA_CLD_WLAN)\t+= qcacld-3.0/\n' >> "$STG/Makefile"
    echo "  + obj-\$(CONFIG_QCA_CLD_WLAN) += qcacld-3.0/"
fi

echo
echo "=== 4. defconfig ==="
if grep -q '^CONFIG_QCA_CLD_WLAN=' "$DEF"; then
    echo "  = 已經有 CONFIG_QCA_CLD_WLAN"
else
    cat >> "$DEF" <<'CFG'

#
# Qualcomm Atheros CLD WLAN（qcacld-3.0）
#
# 設定抄自 LineageOS/android_kernel_oneplus_msm8998 的 lineage_oneplus5_defconfig
# —— 同樣是 msm8998 + WCN3990（ICNSS）+ LineageOS 16，平台設定完全吻合
#（CNSS / CNSS2 都不開，只開 ICNSS）。
#
# 編成 built-in 而不是模組：繞過 CONFIG_MODULE_SIG_FORCE，
# 而且原廠那顆 qca_cld3_wlan.ko 的 modversions CRC 本來就對不上我們的 kernel
#（380 個符號裡 169 個不合，見 tools/71_ko_crc_check.py）。
#
CONFIG_CNSS_UTILS=y
CONFIG_QCA_CLD_WLAN=y
CONFIG_QCACLD_WLAN_LFR3=y
CONFIG_PRIMA_WLAN_OKC=y
CONFIG_PRIMA_WLAN_11AC_HIGH_TP=y
CONFIG_WLAN_FEATURE_11W=y
CONFIG_WLAN_FEATURE_LPSS=y
CONFIG_QCOM_VOWIFI_11R=y
CONFIG_QCACLD_FEATURE_NAN=y
CONFIG_QCACLD_FEATURE_GREEN_AP=y
CONFIG_HELIUMPLUS=y
CONFIG_QCOM_TDLS=y
CONFIG_QCOM_LTE_COEX=y
CONFIG_WLAN_OFFLOAD_PACKETS=y
CONFIG_WLAN_FASTPATH=y
CONFIG_WLAN_NAPI=y
CONFIG_WLAN_TX_FLOW_CONTROL_V2=y
CONFIG_MCC_TO_SCC_SWITCH=y
CONFIG_QCACLD_WLAN_LFR2=y
CONFIG_WLAN_FEATURE_DISA=y
CONFIG_WLAN_FEATURE_FILS=y
CONFIG_WLAN_FEATURE_PKT_CAPTURE=y
CFG
    echo "  + 加入 23 條 qcacld 設定"
fi

echo
echo "=== 5. 在 kernel repo 留 commit ==="
cd "$KSRC"
if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
    echo "  = 沒有變更"
else
    git add -A
    git commit -q -m "staging: 加入 qcacld-3.0（WCN3990 / ICNSS）

ASUS 釋出的 GPL kernel 樹裡沒有 qcacld —— 他們是外掛編譯的。
而原廠的 qca_cld3_wlan.ko 不能直接用：modversions 的符號 CRC 與我們自編的
kernel 全面對不上（380 個裡 169 個不合，連 br_netfilter 這種小模組都不合），
代表 ASUS 出貨的 kernel 與釋出的原始碼不完全一致。

來源：LineageOS/android_kernel_oneplus_msm8998 的 lineage-16.0
（同平台 msm8998、同 WCN3990/ICNSS、同 LineageOS 版本，
  drivers/staging 底下三個目錄已接好 msm-4.4 的 Kconfig/Makefile）。

編成 built-in（=y）而不是模組，繞過 CONFIG_MODULE_SIG_FORCE。
平台側條件本來就齊備 —— dmesg 已顯示
  icnss: Platform driver probed successfully
  icnss: WLAN FW is ready: 0xd87
只差這顆驅動註冊上去生出 wlan0。"
    echo "  + $(git log -1 --format='%h %s' | head -1)"
fi

echo
echo "=== 6. 同步到 AOSP 樹 ==="
# 16_place_trees.sh 是用 cp -al 硬連結複製，新增的檔案不會自己出現，
# 修改過的檔案也會因為 sed -i / cp 斷開連結而不同步，所以要明確 rsync。
rsync -a --delete --exclude '.git' --exclude 'out' "$KSRC/" "$KAOSP/"
echo "  qcacld-3.0 在 AOSP 樹裡：$(find "$KAOSP/drivers/staging/qcacld-3.0" -type f 2>/dev/null | wc -l) 個檔案"
grep -c 'QCA_CLD_WLAN' "$KAOSP/arch/arm64/configs/zs551kl-perf_defconfig"
