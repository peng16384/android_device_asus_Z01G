#!/usr/bin/env bash
#
# 22.2：編「要公開發布」的 ROM —— 私鑰簽名、產物裡不帶建置者的帳號 / 電腦名稱 / 家目錄路徑
#
#   bash device/asus/Z01G/tools/144_release_build_22.sh
#
# 產物：/src/lineage-22.2/out-release/target/product/Z01G/lineage-22.2-*-UNOFFICIAL-Z01G.zip
#       （實體在 ~/lineage-22.2/out-release；平常開發用的 out/ 不受影響）
#
# 前提：tools/145 產生的私鑰已放在 vendor/lineage-priv/keys（keys.mk 讓 mka bacon 直接以私鑰簽，
#       build.prop 的 ro.build.tags 變 release-keys）。沒有就停 —— 不要不小心發一版 test-keys 的。
#
# 中性化（16.0 的 tools/106 同一套；那次掃出帳號名稱出現在 build.prop、kernel 版本字串、.oat/.odex 的
# dex2oat 命令列、adbd / libart.so 的絕對路徑）：
#   帳號       BUILD_USERNAME / USER / LOGNAME -> ro.build.user；BUILD_NUMBER 否則預設 eng.<帳號>
#   電腦名稱    私有 UTS namespace（Soong 的 build_hostname.txt 直接跑 `hostname`），不動 WSL 本身
#   kernel     KBUILD_BUILD_USER / KBUILD_BUILD_HOST；kernel 的 WARN 訊息帶 __FILE__ 絕對路徑 -> 靠下一項
#   路徑       原始碼樹 bind mount 到 /src/lineage-22.2 從那裡編（換路徑 = 從頭編；ccache 以 CCACHE_BASEDIR 相對化）
#   環境       env -i 只放必要變數（WSL 的 PATH 接著 Windows 的 /mnt/c/Users/<帳號>/...）
set -e -o pipefail

# ROM=lineage（預設）或 ROM=evox（Evolution X vic，~/evox-vic，tools/153 / 154）
# 兩者用同一棵 device tree、同一顆 kernel、同一套私鑰；差別只在原始碼樹、私鑰目錄、lunch 方式、目標與 zip 名稱
ROM=${ROM:-lineage}
case "$ROM" in
    lineage) D_REAL=$HOME/lineage-22.2; D_SRC=/src/lineage-22.2; KEYS=vendor/lineage-priv/keys
             LUNCH="breakfast Z01G"; D_TARGET=bacon; ZIPGLOB='lineage-22.2-*-UNOFFICIAL-Z01G.zip' ;;
    evox)    D_REAL=$HOME/evox-vic; D_SRC=/src/evox-vic; KEYS=vendor/evolution-priv/keys
             LUNCH="lunch lineage_Z01G-bp1a-userdebug"; D_TARGET=evolution; ZIPGLOB='EvolutionX-*-Z01G-*.zip' ;;
    *) echo "!!! ROM=$ROM（lineage 或 evox）" >&2; exit 1 ;;
esac
SRC_REAL=${SRC_REAL:-$D_REAL}
SRC=${SRC:-$D_SRC}
OUTD=${OUTD:-$SRC/out-release}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄
B_USER=${B_USER:-android-build}
B_HOST=${B_HOST:-localhost}
# 只編部分目標（例如測 kernel：MKA_TARGET=bootimage），環境與中性化和正式發布版完全相同
MKA_TARGET=${MKA_TARGET:-$D_TARGET}
CLEAN_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ "${1:-}" = "--inner" ]; then
    # ---- 私有 UTS namespace 裡、以一般使用者身分 ----
    echo "  hostname=$(hostname)  USER=$USER  pwd=$SRC"
    [ "$(hostname)" = "$B_HOST" ] || { echo "!!! hostname 沒改成功" >&2; exit 1; }
    cd "$SRC"
    export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR="$CCACHE_DIR" CCACHE_BASEDIR="$SRC"
    export OUT_DIR="$OUTD"
    export BUILD_USERNAME="$B_USER"
    export BUILD_NUMBER="eng.$(date -u +%Y%m%d.%H%M%S)"
    export KBUILD_BUILD_USER="$B_USER" KBUILD_BUILD_HOST="$B_HOST"
    set +e
    source build/envsetup.sh >/dev/null 2>&1
    $LUNCH >/dev/null 2>&1 || { echo "!!! $LUNCH 失敗" >&2; exit 1; }
    set -e
    echo "  TARGET_PRODUCT=$TARGET_PRODUCT  變體=$TARGET_BUILD_VARIANT  OUT_DIR=$OUT_DIR  BUILD_NUMBER=$BUILD_NUMBER"
    date '+  開始 %F %T'
    echo "  目標：$MKA_TARGET"
    mka $MKA_TARGET > "$OUTD.log" 2>&1 || {
        echo "!!! 編譯失敗，見 $OUTD.log" >&2
        grep -nE "^(FAILED|ninja: error|error:)" "$OUTD.log" | head -20 >&2
        exit 1; }
    date '+  結束 %F %T'
    if [ "$MKA_TARGET" = "$D_TARGET" ]; then ls -lh "$OUTD"/target/product/Z01G/$ZIPGLOB
    else ls -lh "$OUTD"/target/product/Z01G/*.img; fi
    exit 0
fi

echo "=== 0. 私鑰與原始碼樹 ==="
echo "  ROM=$ROM  原始碼樹=$SRC_REAL"
[ -f "$SRC_REAL/$KEYS/keys.mk" ] && [ -f "$SRC_REAL/$KEYS/releasekey.pk8" ] \
    || { echo "!!! $KEYS 沒有私鑰（tools/145、evox 是 tools/154）—— 不編 test-keys 的發布版"; exit 1; }
echo "  releasekey：$(openssl x509 -in "$SRC_REAL/$KEYS/releasekey.x509.pem" -noout -fingerprint -sha256 | cut -d= -f2 | cut -c1-23)…"
# SRC 要明講：這裡的 $SRC 是 /src 的 bind mount 路徑，沒 export；不傳的話 123 / 136 會退回預設的 ~/lineage-22.2
SRC="$SRC_REAL" bash "$PROJ/tools/123_place_tree_22.sh" | tail -1
SRC="$SRC_REAL" bash "$PROJ/tools/136_apply_patches_22.sh"

echo "=== 1. bind mount $SRC_REAL -> $SRC ==="
sudo mkdir -p "$SRC"
mountpoint -q "$SRC" || sudo mount --bind "$SRC_REAL" "$SRC"
mountpoint -q "$SRC" && echo "  OK"
mkdir -p "$SRC_REAL/out-release"

echo "=== 2. 在私有 UTS namespace 裡以 $B_USER@$B_HOST 的身分編 ==="
SELF=$(realpath "$0")
sudo unshare --uts -- sh -c '
    hostname "$1" || exit 1
    exec sudo -u "$2" -H env -i \
        PATH="$3" HOME="$4" LANG=C.UTF-8 TERM=dumb \
        USER="$5" LOGNAME="$5" CCACHE_DIR="$4/.ccache" \
        SRC="$6" OUTD="$7" B_USER="$5" B_HOST="$1" MKA_TARGET="$9" ROM="${10}" \
        bash "$8" --inner
' _ "$B_HOST" "$(id -un)" "$CLEAN_PATH" "$HOME" "$B_USER" "$SRC" "$OUTD" "$SELF" "$MKA_TARGET" "$ROM"

echo
echo "完成。接著："
echo "  OUT_DIR=$OUTD SRC=$SRC bash $PROJ/tools/135_verify_build_22.sh      一般檢查"
echo "  bash $PROJ/tools/147_verify_release_22.sh                             私鑰簽名與個資掃描"
