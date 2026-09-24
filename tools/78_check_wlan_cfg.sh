#!/bin/bash
D=$HOME/zs551kl/kernel/msm-4.4/arch/arm64/configs/zs551kl-perf_defconfig
echo "=== 我們 defconfig 的基礎 WLAN 選項 ==="
for c in CONFIG_WLAN CONFIG_CFG80211 CONFIG_CFG80211_INTERNAL_REGDB \
         CONFIG_CFG80211_CERTIFICATION_ONUS CONFIG_CFG80211_REG_CELLULAR_HINTS \
         CONFIG_CFG80211_DEFAULT_PS CONFIG_CFG80211_CRDA_SUPPORT \
         CONFIG_WCNSS_MEM_PRE_ALLOC CONFIG_CLD_LL_CORE CONFIG_CNSS_GENL \
         CONFIG_CNSS_UTILS CONFIG_ICNSS CONFIG_CNSS CONFIG_CNSS2 \
         CONFIG_QCA_CLD_WLAN CONFIG_MAC80211; do
    printf "  %-38s %s\n" "$c" "$(grep -E "^($c=|# $c is not set)" "$D" || echo '（沒有這一項）')"
done
echo
echo "=== staging Kconfig/Makefile 的結尾（準備插入）==="
tail -5 $HOME/zs551kl/kernel/msm-4.4/drivers/staging/Kconfig
echo "---"
tail -5 $HOME/zs551kl/kernel/msm-4.4/drivers/staging/Makefile
