#!/bin/bash
KB=$HOME/zs551kl/kernel/msm-4.4/drivers/staging/qcacld-3.0/Kbuild
echo "=== Kbuild 裡 IPA 相關 ==="
grep -n -iE 'IPA' "$KB" | head -25
