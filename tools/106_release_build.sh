#!/usr/bin/env bash
#
# 編「要公開發布」的 ROM：產物裡不帶建置者的帳號、電腦名稱與家目錄路徑。
#
#   bash tools/106_release_build.sh          （在 WSL 內以一般使用者執行，內部會 sudo）
#
# 產物：$SRC/out-release/target/product/Z01G/lineage-16.0-*-UNOFFICIAL-Z01G.zip
#       （實體位置是 $SRC_REAL/out-release，平常開發用的 out/ 不受影響）
#
# ## 為什麼需要
#
# 用平常的方式編出來的 zip，掃過之後（tools/107）發現帳號名稱出現在：
#
#   build.prop           ro.build.user=<帳號>  ro.build.host=<電腦名稱>
#                        ro.build.version.incremental=eng.<帳號>.<日期>
#   kernel 版本字串       Linux version 4.4.78-perf+ (<帳號>@<電腦名稱>)
#   36 個 .oat / .odex   dex2oat 把自己的命令列記進檔頭，裡面全是
#                        /home/<帳號>/lineage-16.0/out/... 的絕對路徑
#   adbd、libart.so ...  同上
#
# 任何人裝了 ROM，在「關於手機」或 uname -a 就看得到。
#
# 對應的四件事：
#   帳號     USER / LOGNAME        -> build/make/tools/buildinfo.sh 的 ro.build.user
#            BUILD_NUMBER          -> 不然預設是 eng.${USER:0:6}.<日期>
#   電腦名稱  私有的 UTS namespace  -> buildinfo.sh 直接呼叫 `hostname`，沒有變數可改；
#                                    用 unshare --uts 只在這次建置裡改，不動 WSL 的設定
#   kernel   KBUILD_BUILD_USER / KBUILD_BUILD_HOST（scripts/mkcompile_h）
#   路徑     把原始碼樹 bind mount 到中性的 $SRC，從那裡編，
#            輸出放 $SRC/out-release（路徑一換就等於從頭編，快取大多用不上）
#
# 環境用 env -i 清空再只放必要的變數 —— WSL 的 PATH 會接上 Windows 的
# /mnt/c/Users/<帳號>/... ，不能沿用外面那一份。
set -e -o pipefail

SRC_REAL=${SRC_REAL:-$HOME/lineage-16.0}
SRC=${SRC:-/src/lineage-16.0}
OUTD=${OUTD:-$SRC/out-release}
B_USER=${B_USER:-android-build}
B_HOST=${B_HOST:-localhost}
CLEAN_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ "${1:-}" = "--inner" ]; then
    # ---- 這一段跑在私有 UTS namespace 裡、以一般使用者身分 ----
    echo "  hostname=$(hostname)  USER=$USER  pwd=$SRC"
    [ "$(hostname)" = "$B_HOST" ] || { echo "!!! hostname 沒改成功" >&2; exit 1; }
    cd "$SRC"
    export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR="$CCACHE_DIR" CCACHE_BASEDIR="$SRC"
    export OUT_DIR="$OUTD"
    export BUILD_NUMBER="eng.$(date -u +%Y%m%d.%H%M%S)"
    export KBUILD_BUILD_USER="$B_USER" KBUILD_BUILD_HOST="$B_HOST"
    set +e
    source build/envsetup.sh >/dev/null 2>&1
    lunch lineage_Z01G-userdebug >/dev/null 2>&1 || { echo "!!! lunch 失敗" >&2; exit 1; }
    set -e
    echo "  TARGET_PRODUCT=$TARGET_PRODUCT  OUT_DIR=$OUT_DIR  BUILD_NUMBER=$BUILD_NUMBER"
    date '+  開始 %F %T'
    mka bacon -j"$(nproc)" > "$OUTD.log" 2>&1 || {
        echo "!!! 編譯失敗，見 $OUTD.log" >&2
        grep -nE "^(FAILED|ninja: error|error:|make: \*\*\*)" "$OUTD.log" | head -20 >&2
        exit 1; }
    date '+  結束 %F %T'
    ls -lh "$OUTD"/target/product/Z01G/lineage-16.0-*-UNOFFICIAL-Z01G.zip
    exit 0
fi

echo "=== 1. bind mount $SRC_REAL -> $SRC ==="
[ -d "$SRC_REAL/build/make" ] || { echo "!!! $SRC_REAL 不像 AOSP 樹" >&2; exit 1; }
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
        SRC="$6" OUTD="$7" B_USER="$5" B_HOST="$1" \
        bash "$8" --inner
' _ "$B_HOST" "$(id -un)" "$CLEAN_PATH" "$HOME" "$B_USER" "$SRC" "$OUTD" "$SELF"

echo
echo "完成。接著："
echo "  bash tools/107_scan_rom_pii.sh <zip> <樣式檔>     確認沒有個資"
echo "  bash tools/105_diff_rom_zips.sh <舊.zip> <新.zip>  確認內容只差名稱與路徑"
