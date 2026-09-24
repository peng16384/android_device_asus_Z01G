#!/usr/bin/env bash
# 取得與原廠相同世代的 AOSP prebuilt GCC 4.9 toolchain
#
# 原廠 kernel 的編譯器字串是：gcc version 4.9.x 20150123 (prerelease) (GCC)
# → AOSP 的 aarch64-linux-android-4.9 prebuilt。
# msm-4.4 編 arm64 時還需要一個 32-bit toolchain 來編 compat vDSO（CROSS_COMPILE_ARM32）。
set -euo pipefail

WORK="$HOME/zs551kl"
mkdir -p "$WORK"
cd "$WORK"

BASE="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86"

clone_tc() {
    local url="$1" dir="$2"
    if [ -d "$dir" ]; then
        echo "=== $dir 已存在，跳過 ==="
        return 0
    fi
    # 依序嘗試幾個 Android 9 世代的 ref
    for ref in android-9.0.0_r61 pie-release master; do
        echo "=== clone $dir @ $ref ==="
        if git clone --depth 1 -b "$ref" "$url" "$dir" 2>&1 | tail -3; then
            echo "    -> 成功（ref=$ref）"
            return 0
        fi
        rm -rf "$dir"
    done
    echo "!!! $dir clone 失敗" >&2
    return 1
}

clone_tc "$BASE/aarch64/aarch64-linux-android-4.9" aarch64-linux-android-4.9
clone_tc "$BASE/arm/arm-linux-androideabi-4.9"     arm-linux-androideabi-4.9

echo
echo "=== 版本確認（gcc 應為 4.9.x 20150123 prerelease）==="
./aarch64-linux-android-4.9/bin/aarch64-linux-android-gcc --version | head -1
./arm-linux-androideabi-4.9/bin/arm-linux-androideabi-gcc --version | head -1

echo
echo "=== 大小 ==="
du -sh aarch64-linux-android-4.9 arm-linux-androideabi-4.9

echo
echo "步驟 2 完成"
