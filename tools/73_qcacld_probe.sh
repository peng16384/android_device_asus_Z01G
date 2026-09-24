#!/bin/bash
KSRC=$HOME/zs551kl/kernel/msm-4.4
echo "=== kernel 樹裡 WLAN 相關的既有支援 ==="
ls -d "$KSRC"/drivers/net/wireless/cnss* 2>/dev/null
echo "--- staging 底下 ---"
ls "$KSRC"/drivers/staging/ 2>/dev/null | head -20
echo
echo "=== defconfig 裡跟 WLAN 有關的全部 ==="
grep -nE 'WLAN|CNSS|CLD|ICNSS|WCNSS|CFG80211|MAC80211|NL80211' "$KSRC/arch/arm64/configs/zs551kl-perf_defconfig"
echo
echo "=== 原廠的 WLAN 韌體在哪 ==="
ls /mnt/zs_system/vendor/firmware/wlan/ 2>/dev/null
ls /mnt/zs_system/vendor/firmware/ 2>/dev/null | grep -i -E 'wlan|qca|bdwlan' | head
echo
echo "=== 網路能不能通（取原始碼用）==="
timeout 12 git ls-remote https://github.com/LineageOS/android_kernel_oneplus_msm8998 2>&1 | head -2
