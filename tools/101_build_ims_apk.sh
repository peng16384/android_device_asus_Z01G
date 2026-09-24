#!/usr/bin/env bash
#
# 從原廠映像做出一顆能在 Android 9 上跑的 org.codeaurora.ims。
#
#   bash tools/101_build_ims_apk.sh
#
# 產物（.gitignore 排除，所以換機器要重跑這支）：
#   $DEVICE_PATH/prebuilt/ims/ims.apk
#   $DEVICE_PATH/prebuilt/ims/qti-vzw-ims-internal.jar
#
# ############ 為什麼要這一整套 ############
# 撥號顯示「撥號中」然後自己掛斷，log 是
#     E ImsManager: Connector: Retrying getting ImsService...
#     Telecom: setCallState DIALING -> DISCONNECTED
# 台灣 3G 已關台，CS 掛在 LTE 上 -> 只剩 VoLTE，而 Android 側沒有 ImsService。
#
# 原廠有 /system/app/ims/ims.apk，但：
#   1. 它是 odex 過的（apk 內沒有 classes.dex，dex 在 oat/arm64/ims.vdex）
#   2. vdex 裡的 dex 被 quicken 過，那些偏移量跟當初那顆 Oreo boot image 綁死
#   3. 它是對 Oreo 的 IMS API 編的，而 Pie 把那套整組搬到了
#      android.telephony.ims.compat.*
#
# 對應的三步：vdexExtractor -f 還原 -> baksmali -> tools/99 改類別參照 -> smali。
# 再把 manifest 的 intent action 換成 compat 版（Pie 的 ImsResolver 是按 action
# 搜尋的），最後用 platform key 重簽 —— 它的 sharedUserId 是 android.uid.phone，
# 簽名不相符就裝不起來。
#
# 完整分析見 $DEVICE_PATH/docs/volte.md。
# #########################################
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

set -e -o pipefail

ROOT=${ROOT:-$DEVICE_PATH}
AOSP=${AOSP:-$HOME/lineage-16.0}
W=${W:-$HOME/imswork}
SRC=${SRC:-/mnt/zs_system}
VDEX=${VDEX:-$HOME/vdexExtractor/bin/vdexExtractor}
OUT="$DEVICE_PATH/prebuilt/ims"

say() { echo; echo "############ $* ############"; }

say "0. 前置檢查"
mountpoint -q "$SRC" || { echo "!!! $SRC 沒掛載 —— 先跑 sudo bash tools/07_mount_system.sh" >&2; exit 1; }
for f in "$VDEX" "$W/tools/baksmali-2.5.2.jar" "$W/tools/smali-2.5.2.jar" \
         "$AOSP/out/host/linux-x86/framework/signapk.jar" \
         "$AOSP/build/target/product/security/platform.pk8"; do
    [ -f "$f" ] || { echo "!!! 缺 $f" >&2; exit 1; }
done
echo "  OK"

say "1. 取出 dex 並 unquicken"
mkdir -p "$W"
cp -f "$SRC/app/ims/ims.apk" "$W/ims.apk"
cp -f "$SRC/app/ims/oat/arm64/ims.vdex" "$W/ims.vdex"
python3 "$ROOT/tools/98_vdex_extract.py" "$W/ims.vdex" "$W/raw"
rm -rf "$W/out"; mkdir -p "$W/out"
"$VDEX" -i "$W/ims.vdex" -o "$W/out" -f >/dev/null
DEX="$W/out/ims_classes.dex"
[ -s "$DEX" ] || { echo "!!! unquicken 沒有產物" >&2; exit 1; }
# -f 真的有作用嗎（沒作用的話兩份會一模一樣）
if cmp -s "$W/raw/classes.dex" "$DEX"; then
    echo "!!! unquicken 前後完全相同，-f 沒有生效" >&2; exit 1
fi
echo "  unquicken 改了 $(cmp -l "$W/raw/classes.dex" "$DEX" | wc -l) 個 byte"

say "2. baksmali -> 改類別參照 -> smali"
rm -rf "$W/smali"
java -jar "$W/tools/baksmali-2.5.2.jar" disassemble "$DEX" -o "$W/smali" >/dev/null
python3 "$ROOT/tools/99_patch_ims_smali.py" "$W/smali"
rm -f "$W/classes.dex"
java -jar "$W/tools/smali-2.5.2.jar" assemble "$W/smali" -o "$W/classes.dex" --api 28
ls -l "$W/classes.dex"

say "3. manifest 的 intent action 換成 compat 版"
rm -rf "$W/mf"; mkdir -p "$W/mf"
unzip -o -q "$W/ims.apk" AndroidManifest.xml -d "$W/mf"
python3 "$ROOT/tools/100_patch_axml_string.py" \
    "$W/mf/AndroidManifest.xml" "$W/mf/AndroidManifest.new.xml" \
    android.telephony.ims.ImsService android.telephony.ims.compat.ImsService

say "4. 打包並用 platform key 重簽"
rm -rf "$W/build"; mkdir -p "$W/build"
cp -f "$W/ims.apk" "$W/build/ims-unsigned.apk"
cp -f "$W/mf/AndroidManifest.new.xml" "$W/build/AndroidManifest.xml"
cp -f "$W/classes.dex" "$W/build/classes.dex"
( cd "$W/build" && zip -q ims-unsigned.apk AndroidManifest.xml classes.dex )
java -Djava.library.path="$AOSP/out/host/linux-x86/lib64" \
     -jar "$AOSP/out/host/linux-x86/framework/signapk.jar" \
     "$AOSP/build/target/product/security/platform.x509.pem" \
     "$AOSP/build/target/product/security/platform.pk8" \
     "$W/build/ims-unsigned.apk" "$W/build/ims.apk"

say "5. uses-library 的 qti-vzw-ims-internal.jar（也是 odex 的）"
rm -rf "$W/vzw"; mkdir -p "$W/vzw"
cp -f "$SRC/vendor/framework/qti-vzw-ims-internal.jar" "$W/vzw/built.jar"
cp -f "$SRC/vendor/framework/oat/arm64/qti-vzw-ims-internal.vdex" "$W/vzw/"
rm -rf "$W/vzw/out"; mkdir -p "$W/vzw/out"
"$VDEX" -i "$W/vzw/qti-vzw-ims-internal.vdex" -o "$W/vzw/out" -f >/dev/null
cp -f "$W/vzw/out/qti-vzw-ims-internal_classes.dex" "$W/vzw/classes.dex"
( cd "$W/vzw" && zip -q built.jar classes.dex )

say "6. 驗證"
AAPT="$AOSP/out/host/linux-x86/bin/aapt"
"$AAPT" dump badging "$W/build/ims.apk" | head -1
echo "  -- service 的 action --"
"$AAPT" dump xmltree "$W/build/ims.apk" AndroidManifest.xml | grep -A2 "E: action" | grep "android:name" | sed 's/^/    /'
echo "  -- classes.dex 在不在 --"
unzip -l "$W/build/ims.apk" | grep -c classes.dex | sed 's/^/    /'
echo "  -- jar --"
unzip -l "$W/vzw/built.jar" | grep classes.dex | sed 's/^/    /'

say "6b. 對著實際編出來的 framework 檢查每一個外部參照"
# 這一步是補課：第一次刷進去才看到
#     NoClassDefFoundError: Lcom/android/ims/ImsReasonInfo;
# —— Pie 把資料類別搬到 android.telephony.ims 了，而我當時是「看到哪個對不上
# 才查哪個」，漏掉一整類。對著產物全面掃就不會漏。
CP=""
for j in core-oj core-libart conscrypt okhttp bouncycastle apache-xml ext framework          telephony-common voip-common ims-common android.hidl.base-V1.0-java          android.hidl.manager-V1.0-java framework-oahl-backward-compatibility          android.test.base org.apache.http.legacy.boot; do
    CP="$CP $AOSP/out/target/product/Z01G/system/framework/$j.jar"
done
if [ -e "$AOSP/out/target/product/Z01G/system/framework/framework.jar" ]; then
    python3 "$ROOT/tools/102_check_dex_refs.py" "$W/build/ims.apk" $CP "$W/vzw/built.jar"
    # 方法與欄位層：類別在、方法不在的那一類（NoSuchMethodError / NoSuchFieldError）
    # 已知且刻意不處理的 3 個：只在 QtiImsExtManager（給 QTI/ASUS 自家 App 的
    # 擴充 API）裡用到。除此之外任何一個都算失敗。
    KNOWN='com\.android\.ims\.ImsManager\.(getImsServiceStatus|isConnected|isOpened)\('
    R103=$(python3 "$ROOT/tools/103_check_dex_methods.py" "$W/build/ims.apk" $CP "$W/vzw/built.jar" || true)
    echo "$R103"
    NEW=$(echo "$R103" | grep -E '^    [a-zA-Z]' | grep -vE "$KNOWN" || true)
    if [ -n "$NEW" ]; then
        echo "!!! tools/103 找到已知清單以外的缺漏：" >&2; echo "$NEW" >&2; exit 1
    fi
    echo "  （只有已知的 3 個 QtiImsExtManager 方法）"
else
    echo "  ⚠ 還沒編過，跳過（編完之後可以自己跑 tools/102_check_dex_refs.py）"
fi

say "7. 放進 device tree"
mkdir -p "$OUT"
cp -f "$W/build/ims.apk" "$OUT/ims.apk"
cp -f "$W/vzw/built.jar" "$OUT/qti-vzw-ims-internal.jar"
cp -f "$SRC/etc/permissions/qti-vzw-ims-internal.xml" "$OUT/qti-vzw-ims-internal.xml"
ls -l "$OUT"
( cd "$OUT" && sha256sum ims.apk qti-vzw-ims-internal.jar )

echo
echo "完成。接著跑完整編譯（device.mk 會把這三個檔 PRODUCT_COPY_FILES 進去）。"
