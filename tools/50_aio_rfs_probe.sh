#!/bin/bash
echo "=== /vendor/rfs 的完整結構（目錄 + symlink 目標）==="
cd /mnt/zs_system/vendor/rfs || exit 1
find . -type d | sort | sed 's/^/  DIR  /'
echo
find . -type l | sort | while read -r l; do printf "  LINK %-50s -> %s\n" "$l" "$(readlink "$l")"; done
echo
echo "=== 有沒有一般檔案 ==="
find . -type f | head
