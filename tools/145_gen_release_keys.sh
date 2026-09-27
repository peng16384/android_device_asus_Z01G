#!/usr/bin/env bash
#
# 22.2：產生發布用的私鑰（取代 AOSP 公開的 test-keys）
#
#   bash device/asus/Z01G/tools/145_gen_release_keys.sh
#
# 產物：~/.android-certs/（權限 700，**只在 WSL 裡，不進任何 repo**），並放一份到原始碼樹的
#       vendor/lineage-priv/keys/（不是 repo 管的專案，vendor/lineage/config/common.mk 會 -include 它的 keys.mk）。
#
# ⚠ 已經有金鑰就拒絕執行 —— 換了金鑰，已安裝的手機要清資料才能再更新（OTA 也會驗證失敗）。
# ⚠ 私鑰不設密碼（編譯要自動跑）：保護靠「只在 WSL、權限 700」與加密備份（見最後的提示）。
#
# 要哪些金鑰：
#   主要的（2048 位元，make_key 預設）：releasekey platform shared media networkstack nfc bluetooth sdk_sandbox
#     testkey testcert —— 名字叫 test 的也要有：有些模組以 "testkey" / "testcert" 當憑證名稱，
#     改用私鑰目錄後會到這裡找
#   APEX（4096 位元）：清單取自實際建置的 apexkeys.txt（PRESIGNED 的預先簽好、不用）。每個要四個檔：
#     <名>.pk8 / <名>.x509.pem（容器）、<名>.pem（payload 私鑰）、<名>.avbpubkey（payload 公鑰）
#   ⚠ build/soong/apex/key.go：私鑰目錄裡**找不到就悄悄退回模組自帶的公開測試金鑰**，不報錯。
#     漏一個 = 那個 APEX 仍是 test-keys；只產 .pem 不產 .avbpubkey = 公私鑰對不上、apexd 開機驗證失敗
set -e -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
K=${KEYDIR:-$HOME/.android-certs}
PRIV=$SRC/vendor/lineage-priv/keys
APEXKEYS=$SRC/out/target/product/Z01G/obj/PACKAGING/apexkeys_intermediates/apexkeys.txt
AVBTOOL=$SRC/out/host/linux-x86/bin/avbtool
SUBJECT='/C=TW/O=android_device_asus_Z01G/CN=Z01G release'

[ ! -e "$K" ] || { echo "!!! $K 已經存在，不覆蓋（換金鑰 = 已安裝的手機要清資料）"; exit 1; }
[ -f "$APEXKEYS" ] || { echo "!!! 找不到 $APEXKEYS（先完整編譯一次）"; exit 1; }
[ -x "$AVBTOOL" ] || { echo "!!! 找不到 avbtool"; exit 1; }

mkdir -m 700 "$K"
MK=$SRC/development/tools/make_key

echo "=== 主要金鑰 ==="
for c in releasekey platform shared media networkstack nfc bluetooth sdk_sandbox testkey testcert; do
    echo "" | "$MK" "$K/$c" "$SUBJECT" >/dev/null 2>&1 || true
    [ -f "$K/$c.pk8" ] && [ -f "$K/$c.x509.pem" ] || { echo "!!! $c 沒產生"; exit 1; }
    echo "  $c"
done

echo "=== APEX ==="
cp "$MK" "$K/.make_key_4096"   # 複製一份改成 4096 位元
sed -i 's/openssl genrsa -f4 2048/openssl genrsa -f4 4096/' "$K/.make_key_4096"
grep -q 'genrsa -f4 4096' "$K/.make_key_4096" || { echo "!!! make_key 改 4096 失敗"; exit 1; }
APEXES=$(grep -oE 'private_key="[^"]+\.pem"' "$APEXKEYS" | sed -E 's/.*\/([^/"]+)\.pem"/\1/' | sort -u)
n=0
for a in $APEXES; do
    echo "" | bash "$K/.make_key_4096" "$K/$a" "$SUBJECT" >/dev/null 2>&1 || true
    [ -f "$K/$a.pk8" ] || { echo "!!! $a 沒產生"; exit 1; }
    openssl pkcs8 -in "$K/$a.pk8" -inform DER -nocrypt -out "$K/$a.pem"
    "$AVBTOOL" extract_public_key --key "$K/$a.pem" --output "$K/$a.avbpubkey"
    n=$((n + 1))
done
rm -f "$K/.make_key_4096"
echo "  $n 個"

echo "=== 驗證：每個 APEX 的 .avbpubkey 都是從同一把私鑰推出來的 ==="
T=$(mktemp); bad=0
for a in $APEXES; do
    "$AVBTOOL" extract_public_key --key "$K/$a.pem" --output "$T"
    cmp -s "$T" "$K/$a.avbpubkey" || { echo "!!! $a 公私鑰不一致"; bad=1; }
    for f in pk8 x509.pem pem avbpubkey; do [ -s "$K/$a.$f" ] || { echo "!!! 缺 $a.$f"; bad=1; }; done
done
rm -f "$T"; [ $bad = 0 ] && echo "  OK"

chmod 600 "$K"/*
echo "=== 放進原始碼樹 $PRIV ==="
mkdir -p "$PRIV"; chmod 700 "$SRC/vendor/lineage-priv" "$PRIV"
cp -p "$K"/* "$PRIV/"
echo 'PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey' > "$PRIV/keys.mk"
cat > "$PRIV/BUILD.bazel" <<'EOB'
filegroup(
    name = "android_certificate_directory",
    srcs = glob([
        "*.pk8",
        "*.pem",
    ]),
    visibility = ["//visibility:public"],
)
EOB
echo "  $(ls "$PRIV" | wc -l) 個檔"
echo
echo "完成。releasekey 的憑證指紋（之後比對用）："
openssl x509 -in "$K/releasekey.x509.pem" -noout -fingerprint -sha256
echo
echo "⚠ 接著做加密備份（會問兩次密碼，密碼自己保管）："
echo "  bash device/asus/Z01G/tools/146_backup_release_keys.sh"
