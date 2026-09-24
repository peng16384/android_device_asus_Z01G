#!/bin/bash
W=$HOME/zs551kl/qcacld_src
M=$W/drivers/staging/qcacld-3.0/Makefile
echo "=== qcacld Makefile 前 60 行 ==="
sed -n '1,60p' "$M"
echo
echo "=== 找 cmn / fw-api 的引用 ==="
grep -n -iE 'cmn|fw-api|\.\./' "$M" | head -20
