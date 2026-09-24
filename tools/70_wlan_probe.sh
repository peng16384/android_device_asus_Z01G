#!/bin/bash
O=$HOME/lineage-16.0/out/target/product/Z01G/system
echo "=== out 的 vendor/lib/modules ==="
ls -la "$O/vendor/lib/modules/"
echo
echo "=== 手機上的（對照）==="
echo "（前面已確認手機上沒有 qca_cld3_wlan.ko）"
