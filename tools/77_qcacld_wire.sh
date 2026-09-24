#!/bin/bash
U=https://raw.githubusercontent.com/LineageOS/android_kernel_oneplus_msm8998/lineage-16.0/arch/arm64/configs/lineage_oneplus5_defconfig
OUT=$HOME/zs551kl/qcacld_src/lineage_oneplus5_defconfig
curl -sS --max-time 30 -o "$OUT" "$U" || exit 1
echo "取得 $(wc -l < "$OUT") 行"
echo
echo "=== OnePlus 的 WLAN / qcacld 相關設定 ==="
grep -nE 'QCA_CLD|QCACLD|WLAN|CNSS|CLD_|HELIUM|CFG80211|MAC80211|NAPI|TSO|LRO|PRIMA|QCOM_TDLS|QCOM_LTE|QCOM_VOWIFI|MPC_UT|LFR_|MCC_TO|64BIT_PADDR|FEATURE_' "$OUT"
