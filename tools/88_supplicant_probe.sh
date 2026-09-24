#!/bin/bash
K=/mnt/zs_system
S=$HOME/lineage-16.0
for f in wpa_supplicant_overlay.conf p2p_supplicant_overlay.conf; do
  echo "=== $f ==="; cat "$K/vendor/etc/wifi/$f"; echo
done
echo "=== AOSP 有沒有 wpa_supplicant 原始碼 ==="
ls -d "$S/external/wpa_supplicant_8" 2>&1
ls "$S/external/wpa_supplicant_8/wpa_supplicant/" 2>/dev/null | head -5
echo "--- 它的 rc ---"
find "$S/external/wpa_supplicant_8" -name '*.rc' 2>/dev/null | head
echo
echo "=== qcwcn 的 driver cmd lib 在不在 ==="
ls -d "$S/hardware/qcom/wlan/qcwcn/wpa_supplicant_8_lib" 2>&1
