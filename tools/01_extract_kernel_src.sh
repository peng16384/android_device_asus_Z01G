#!/usr/bin/env bash
# 在 WSL ext4 內解壓 ASUS kernel 原始碼，並建立 git baseline
# 必須在 WSL 內執行（ext4），不能在 /mnt/g —— symlink 與大小寫在 NTFS 上會壞。
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -euo pipefail

WORK="$HOME/zs551kl"
SRC_TGZ="$DEVICE_PATH/<原廠韌體存放處>/ASUS_Z01GD_1-15.0410.1911.117-kernel-src.tar.gz"
KDIR="$WORK/kernel/msm-4.4"

echo "=== 檔案系統確認（必須是 ext4，不能是 9p/drvfs）==="
df -T "$HOME" | tail -1

mkdir -p "$WORK"
cd "$WORK"

if [ -d "$KDIR" ]; then
    echo "=== $KDIR 已存在，跳過解壓 ==="
else
    echo "=== 解壓 $(basename "$SRC_TGZ") ==="
    time tar xzf "$SRC_TGZ"
fi

cd "$KDIR"

echo
echo "=== 版本確認（應為 4.4.78）==="
head -4 Makefile

echo
echo "=== symlink 完整性（關鍵：arm64 的 dts 是指向 arm 的 symlink）==="
ls -ld arch/arm64/boot/dts/qcom
echo "readlink: $(readlink arch/arm64/boot/dts/qcom || echo '(不是 symlink！解壓壞了)')"
echo "symlink 總數: $(find . -type l | wc -l)"
echo "斷掉的 symlink: $(find . -xtype l | wc -l)"

echo
echo "=== ZS551KL 專屬檔案 ==="
ls -1 arch/arm64/configs/zs551kl-*
ls -1 arch/arm/boot/dts/qcom/zs551kl-* | head -20

echo
echo "=== 建立 git baseline（之後的修改都疊在這個 commit 上，方便出 patch）==="
if [ -d .git ]; then
    echo "已經是 git repo，跳過"
else
    cat > .gitignore <<'EOF'
out/
*.o
*.ko
*.mod
*.mod.c
*.cmd
.tmp_versions/
Module.symvers
modules.order
System.map
vmlinux
.config
.config.old
EOF
    git init -q
    git config user.name  "${GIT_NAME:-Builder}"
    git config user.email "${GIT_EMAIL:-builder@localhost}"
    git config core.fileMode true
    git add -A
    git commit -q -m "ASUS Z01GD 15.0410.1911.117 kernel source (pristine, 未修改)"
fi
git -C "$KDIR" log --oneline
echo
echo "=== 大小 ==="
du -sh "$KDIR"

echo
echo "步驟 1 完成：$KDIR"
