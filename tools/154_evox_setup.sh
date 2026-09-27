#!/usr/bin/env bash
#
# Evolution X vic：把 Z01G 需要的東西放進原始碼樹（~/evox-vic，tools/153 同步的）
#
#   bash device/asus/Z01G/tools/154_evox_setup.sh
#
# 可重跑。做的事（與 LineageOS 22.2 是同一套 device tree / kernel / blob / patch）：
#   1. kernel/asus/msm8998   <- $KURL 的 $KBR（預設是公開的 kernel repo）
#   2. vendor/evolution-priv/keys <- ~/.android-certs（與 LineageOS 共用同一套私鑰；keys.mk 路徑不同）
#   3. device tree + 兩個 vendor 模組 <- tools/127（在這棵樹重新 extract：makefile 要配這棵樹的 extract_utils）
#   4. patches               <- tools/136（4 個都能直接套在 Evolution X 的 fork 上，2026-09-27 確認）
set -e -o pipefail

export SRC=${SRC:-$HOME/evox-vic}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄
K=$SRC/kernel/asus/msm8998
KURL=${KURL:-https://github.com/peng16384/android_kernel_asus_msm8998}
KBR=${KBR:-lineage-22.2-z01g}
[ -d "$SRC/.repo" ] || { echo "!!! $SRC 不是 repo 樹（先跑 tools/153）"; exit 1; }

echo "=== 1. kernel ==="
if [ ! -d "$K/.git" ]; then
    mkdir -p "$(dirname "$K")"
    # 不能 --reference 22.2 那份：它是淺層 clone（git 拒絕以 shallow repo 當 reference）
    git clone -q -b "$KBR" "$KURL" "$K"
fi
git -C "$K" fetch -q origin && git -C "$K" checkout -q "$KBR" && git -C "$K" merge -q --ff-only "origin/$KBR"
echo "  $(git -C "$K" log --oneline -1)"
L22=$HOME/lineage-22.2/kernel/asus/msm8998   # 有 LineageOS 那棵的話，確認兩個 ROM 用同一顆 kernel
if [ -d "$L22/.git" ]; then
    [ "$(git -C "$K" rev-parse HEAD^{tree})" = "$(git -C "$L22" rev-parse HEAD^{tree})" ] \
        && echo "  與 LineageOS 那棵的 kernel 相同" || echo "  ⚠ 與 LineageOS 那棵的 kernel 不同"
fi

echo "=== 2. 私鑰 -> vendor/evolution-priv/keys ==="
KD=$SRC/vendor/evolution-priv/keys
mkdir -p "$KD"; chmod 700 "$SRC/vendor/evolution-priv" "$KD"
cp -p "$HOME"/.android-certs/* "$KD/"
echo 'PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/evolution-priv/keys/releasekey' > "$KD/keys.mk"
cat > "$KD/BUILD.bazel" <<'EOB'
filegroup(
    name = "android_certificate_directory",
    srcs = glob([
        "*.pk8",
        "*.pem",
    ]),
    visibility = ["//visibility:public"],
)
EOB
echo "  $(ls "$KD" | wc -l) 個檔；releasekey $(openssl x509 -in "$KD/releasekey.x509.pem" -noout -fingerprint -sha256 | cut -d= -f2 | cut -c1-23)…"

echo "=== 3. device tree + vendor（tools/127）==="
bash "$PROJ/tools/127_extract_22.sh" | tail -4

echo "=== 4. patches（tools/136）==="
bash "$PROJ/tools/136_apply_patches_22.sh"

df -h / | tail -1
