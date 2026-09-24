#!/bin/bash
K=$HOME/zs551kl/kernel/msm-4.4/out
echo "=== qcacld 的 built-in.o 有沒有產生 ==="
ls -la "$K/drivers/staging/qcacld-3.0/built-in.o" 2>&1
echo
echo "=== kernel 裡有沒有 qcacld 的符號 ==="
for s in hdd_wlan_startup wlan_hdd_state_ctrl_param_create hdd_driver_init \
         pld_snoc_register_driver icnss_register_driver; do
    printf "  %-38s %s\n" "$s" "$(grep -c " $s\$" "$K/System.map" 2>/dev/null)"
done
echo
echo "=== 驅動註冊的 init 順序（built-in 會在開機時自動跑）==="
grep -E 'hdd_module_init|hdd_driver_init' "$K/System.map" | head -5
echo
echo "=== wlan_hdd_state_ctrl_param 有沒有建立 sysfs（BoardConfig 指定的路徑）==="
grep -rn 'boot_wlan' $HOME/zs551kl/kernel/msm-4.4/drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_main.c | head -5
