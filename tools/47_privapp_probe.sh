#!/bin/bash
O=$HOME/lineage-16.0/out/target/product/Z01G/system
echo "=== priv-app 目錄 ==="
ls -d $O/priv-app $O/vendor/priv-app 2>&1
echo "--- system/priv-app ---"; ls $O/priv-app 2>/dev/null
echo "--- vendor/priv-app ---"; ls $O/vendor/priv-app 2>/dev/null
echo
echo "=== 參考樹的 privapp-permissions-qti.xml（oneplus）==="
cat $HOME/zs551kl/reference/oneplus_common/configs/privapp-permissions-qti.xml
