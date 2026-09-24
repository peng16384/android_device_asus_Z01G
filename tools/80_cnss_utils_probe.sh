#!/bin/bash
K=$HOME/zs551kl/kernel/msm-4.4
B=https://raw.githubusercontent.com/LineageOS/android_kernel_oneplus_msm8998/lineage-16.0
curl -sS --max-time 25 "$B/drivers/net/wireless/cnss_utils/cnss_utils.c" -o /tmp/cnss_utils_op.c
echo "=== cnss_utils.c 差異統計 ==="
diff -u "$K/drivers/net/wireless/cnss_utils/cnss_utils.c" /tmp/cnss_utils_op.c | grep -cE '^[+-][^+-]'
echo "--- 差異內容 ---"
diff -u "$K/drivers/net/wireless/cnss_utils/cnss_utils.c" /tmp/cnss_utils_op.c
