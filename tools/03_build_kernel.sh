#!/usr/bin/env bash
# 編譯 kernel
#
# 目標：產出 out/arch/arm64/boot/Image.gz-dtb，內容要能對得上原廠
#       （4.4.78-perf+、附加 3 個 DTB、config 與 /proc/config.gz 相符）
#
# KBUILD_BUILD_USER/HOST 刻意不偽裝成原廠的 android@mcrd1-13 ——
# 這樣刷進去後 uname -a 就能一眼確認手機跑的是「我們編的」還是原廠 kernel。
# 建置身分與 WSL distro：需要時用環境變數覆蓋
#   BUILD_USER=alice WSL_DISTRO=ubuntu2004 bash tools/xxx.sh
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

BUILD_USER="${BUILD_USER:-${SUDO_USER:-$(id -un)}}"

set -euo pipefail

WORK="$HOME/zs551kl"
KDIR="$WORK/kernel/msm-4.4"
OUT="$KDIR/out"
LOGDIR="$DEVICE_PATH/docs"
mkdir -p "$LOGDIR"

cd "$KDIR"

# setlocalversion 讀這個檔並直接當成版本尾綴 → 重現原廠的 "4.4.78-perf+"
# （CONFIG_LOCALVERSION="-perf" 提供 -perf，這裡補上 +）
echo "+" > .scmversion

export ARCH=arm64
export SUBARCH=arm
export CROSS_COMPILE="$WORK/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
export CROSS_COMPILE_ARM32="$WORK/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-builder}"
export KBUILD_BUILD_HOST="zs551kl-wsl"

JOBS="$(nproc)"

echo "=== 編譯設定 ==="
echo "  KDIR              = $KDIR"
echo "  CROSS_COMPILE     = $CROSS_COMPILE"
echo "  CROSS_COMPILE_ARM32 = $CROSS_COMPILE_ARM32"
echo "  jobs              = $JOBS"
"${CROSS_COMPILE}gcc" --version | head -1

echo
echo "=== make zs551kl-perf_defconfig ==="
make O="$OUT" zs551kl-perf_defconfig 2>&1 | tail -5

echo
echo "=== make -j$JOBS（完整 log 寫到 $LOGDIR/build.log）==="
set +e
time make O="$OUT" -j"$JOBS" > "$LOGDIR/build.log" 2>&1
RC=$?
set -e

echo
echo "=== 警告／錯誤統計 ==="
echo "  error:   $(grep -ci 'error:'   "$LOGDIR/build.log" || true)"
echo "  warning: $(grep -ci 'warning:' "$LOGDIR/build.log" || true)"

if [ $RC -ne 0 ]; then
    echo
    echo "!!! 編譯失敗（rc=$RC），最後 40 行："
    tail -40 "$LOGDIR/build.log"
    exit $RC
fi

echo
echo "=== 產物 ==="
ls -l "$OUT/arch/arm64/boot/"Image* 2>/dev/null || true

echo
echo "步驟 3 完成"
