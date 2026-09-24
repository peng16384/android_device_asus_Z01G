#!/bin/bash
O=$HOME/lineage-16.0/out/target/product/Z01G/system
for b in lib lib64; do
  echo "=== $b ==="
  echo "--- libkeymaster1.so 缺的（U）---"
  nm -D "$O/$b/libkeymaster1.so" 2>/dev/null | awk '$1=="U"{print $2}' | grep copy_size_and_data
  echo "--- libkeymaster_messages.so 有的（T）---"
  nm -D --defined-only "$O/$b/libkeymaster_messages.so" 2>/dev/null | grep copy_size_and_data | awk '{print $3}'
  echo "--- 32/64 位元判定 ---"
  file -b "$O/$b/libkeymaster1.so" 2>/dev/null | cut -d, -f1-2
done
