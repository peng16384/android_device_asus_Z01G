#!/bin/bash
O=$HOME/lineage-16.0/out/target/product/Z01G/system
for f in $O/vendor/manifest.xml $O/vendor/etc/vintf/manifest.xml $O/etc/vintf/manifest.xml; do
  printf "%-60s  %8s bytes  gnss/nfc/wfd 命中 %s\n" "${f#$O}" "$(stat -c%s $f)" \
    "$(grep -c 'android.hardware.gnss\|vendor.qti.gnss\|hardware.nfc\|wifidisplayhal' $f)"
done
echo
echo "=== 哪一份是我們的（會有我們加的中文註解）==="
for f in $O/vendor/manifest.xml $O/vendor/etc/vintf/manifest.xml $O/etc/vintf/manifest.xml; do
  printf "%-60s  %s\n" "${f#$O}" "$(grep -qc 'bring-up 期間被停用' $f && echo '是我們的' || echo '不是')"
done
echo
echo "=== device.mk 把 manifest 裝到哪 ==="
grep -n 'manifest' $HOME/lineage-16.0/device/asus/Z01G/device.mk
echo
echo "=== proprietary-files.txt 裡有沒有收原廠 manifest ==="
grep -n 'manifest' $HOME/lineage-16.0/device/asus/Z01G/proprietary-files.txt
