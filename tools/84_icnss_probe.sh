#!/bin/bash
Q=$HOME/zs551kl/kernel/msm-4.4/drivers/staging/qcacld-3.0
echo "=== pld_snoc.h 前 40 行 ==="
sed -n '1,40p' "$Q/core/pld/src/pld_snoc.h"
echo
echo "=== 三個缺的函式在 qcacld 哪裡用 ==="
grep -rn 'icnss_block_shutdown\|icnss_is_fw_down\|icnss_is_rejuvenate' "$Q" | head
