#!/bin/bash
F=$HOME/lineage-16.0/system/libhidl/transport/ServiceManagement.cpp
echo "=== getService 的 transport 判斷 ==="
sed -n '/^static.*getRawServiceInternal\|vintfLegacy\|vintfHwbinder\|vintfPassthru/,+2p' "$F" | head -40
echo
echo "=== isLegacyTreble / kLegacy 的定義 ==="
grep -n -B3 -A12 'isTrebleTestingOverride\|Legacy' "$F" | head -50
