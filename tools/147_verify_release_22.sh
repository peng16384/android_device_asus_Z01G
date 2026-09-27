#!/usr/bin/env bash
#
# 22.2 發布前的最後一關：私鑰簽名到位、沒有個資
#
#   bash device/asus/Z01G/tools/147_verify_release_22.sh [zip]
#
# 預設 zip = ~/lineage-22.2/out-release/target/product/Z01G/ 最新的那個（tools/144 的產物）。
# 樣式檔在 ~/pii/（public.txt 會印前後文、secret.txt 只印檔名），**不在任何 repo 裡**。
#
# 檢查：
#   1. build.prop：ro.build.tags=release-keys、ro.build.user / host 是中性的
#   2. zip 本身以 releasekey 簽（AOSP 的 check_ota_package_signature.py）、META-INF/com/android/otacert 是它
#   3. system 的 otacerts.zip = releasekey（LineageOS Recovery 與 Updater 以它驗 OTA）
#   4. framework-res.apk 以 platform 金鑰簽
#   5. **每個 APEX 的 apex_pubkey 都是我們的**：build/soong/apex/key.go 在私鑰目錄找不到時會悄悄退回
#      模組自帶的公開測試金鑰，不報錯 —— 這裡是唯一抓得到的地方（PRESIGNED 的預先簽好，列出來但不算錯）
#   6. 個資掃描：system 映像每個檔、boot.img 與 recovery.img 的 kernel（含附加 DTB）與 ramdisk、zip 的 metadata
#
# 16.0 的 tools/107 用 unzip 解，22.2 的 zip unzip 讀不了（列出 0 個檔）-> 改用 Python zipfile。
set -e -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
K=${KEYDIR:-$HOME/.android-certs}
PII=${PII:-$HOME/pii}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄
ZIP=${1:-$(ls -t "$SRC"/out-release/target/product/Z01G/lineage-22.2-*-UNOFFICIAL-Z01G.zip 2>/dev/null | head -1)}
H=$SRC/out/host/linux-x86
# apksigner 是 java 程式，WSL 裡沒有系統的 java -> 用原始碼樹內附的 JDK
# （2026-09-27：沒這行時 apksigner 靜靜失敗，空輸出被判成「不是我們的金鑰」）
export PATH="$SRC/prebuilts/jdk/jdk21/linux-x86/bin:$PATH"
[ -f "$ZIP" ] || { echo "!!! 找不到 zip"; exit 1; }
[ -f "$PII/public.txt" ] && [ -f "$PII/secret.txt" ] || { echo "!!! 找不到 $PII 的樣式檔"; exit 1; }
ZIP=$(realpath "$ZIP")
echo "zip：$ZIP"
fail=0
ok()  { echo "  OK    $1"; }
bad() { echo "  !!!   $1"; fail=1; }

W=$(mktemp -d "$HOME/relcheck.XXXX")
trap 'mountpoint -q "$W/m" && sudo umount "$W/m"; rm -rf "$W"' EXIT
cd "$W"
python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall('z')" "$ZIP"
"$H/bin/brotli" -d z/system.new.dat.br -o system.new.dat
python3 "$PROJ/tools/105_sdat2img.py" z/system.transfer.list system.new.dat system.img >/dev/null
rm -f system.new.dat
mkdir m && sudo mount -o ro,loop system.img m
S=m; [ -d m/system/etc ] && S=m/system
# 映像裡的檔多是 root 0600（build.prop 就是）-> 需要的先以 sudo 複製出來
get() { sudo cat "$S/$1" > "$2"; }
get build.prop build.prop
python3 - <<'PY'
import gzip, struct, zlib, os
for img in ("boot", "recovery"):
    b = open("z/%s.img" % img, "rb").read()
    ks, _, rs = struct.unpack_from("<III", b, 8)
    ps = struct.unpack_from("<I", b, 36)[0]
    k = b[ps:ps + ks]
    ro = ps + (ks + ps - 1) // ps * ps
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)
    open(img + ".kernel", "wb").write(d.decompress(k) + d.unused_data)
    open(img + ".ramdisk", "wb").write(gzip.decompress(b[ro:ro + rs]) if b[ro:ro+2] == b"\x1f\x8b" else b[ro:ro + rs])
PY
for img in boot recovery; do
    mkdir "$img.rd"
    if file "$img.ramdisk" | grep -q cpio; then (cd "$img.rd" && cpio -idm --quiet < "../$img.ramdisk"); fi
done

echo "=== 1. build.prop ==="
BP=build.prop
prop() { grep -m1 "^$1=" "$BP" | cut -d= -f2-; }
[ "$(prop ro.build.tags)" = release-keys ] && ok "ro.build.tags=release-keys" || bad "ro.build.tags=$(prop ro.build.tags)"
[ "$(prop ro.build.user)" = android-build ] && ok "ro.build.user=android-build" || bad "ro.build.user 不是 android-build"
[ "$(prop ro.build.host)" = localhost ] && ok "ro.build.host=localhost" || bad "ro.build.host 不是 localhost"
echo "        display.id = $(prop ro.build.display.id)"
echo "        ro.build.date.utc = $(prop ro.build.date.utc)   ro.lineage.build.version = $(prop ro.lineage.build.version)   ro.lineage.releasetype = $(prop ro.lineage.releasetype)"
sudo grep -qs "^lineage.updater.uri=https://raw.githubusercontent.com/peng16384/" "$S"/*.prop "$S"/etc/*.prop \
    && ok "lineage.updater.uri 指向公開 repo" || bad "沒有 lineage.updater.uri"

echo "=== 2. zip 的簽名 ==="
if python3 "$SRC/build/make/tools/releasetools/check_ota_package_signature.py" "$K/releasekey.x509.pem" "$ZIP" >/dev/null 2>&1; then
    ok "zip 以 releasekey 簽（check_ota_package_signature.py）"
else bad "zip 不是 releasekey 簽的"; fi
cmp -s <(openssl x509 -in z/META-INF/com/android/otacert -outform DER) <(openssl x509 -in "$K/releasekey.x509.pem" -outform DER) \
    && ok "META-INF/com/android/otacert = releasekey" || bad "zip 內的 otacert 不是 releasekey"

echo "=== 3. otacerts.zip ==="
get etc/security/otacerts.zip otacerts.zip
mkdir oc && python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall('oc')" otacerts.zip
found=0; for c in oc/*; do cmp -s <(openssl x509 -in "$c" -outform DER) <(openssl x509 -in "$K/releasekey.x509.pem" -outform DER) && found=1; done
[ $found = 1 ] && ok "otacerts.zip 含 releasekey（共 $(ls oc | wc -l) 張）" || bad "otacerts.zip 沒有 releasekey"

echo "=== 4. APK ==="
digest() { openssl x509 -in "$1" -outform DER | sha256sum | cut -c1-64; }
get framework/framework-res.apk framework-res.apk
fw=$("$H/bin/apksigner" verify --print-certs framework-res.apk 2>/dev/null | grep -m1 "SHA-256 digest" | awk '{print $NF}' || true)
if [ -z "$fw" ]; then bad "apksigner 沒有輸出（工具執行失敗，不是金鑰的問題）：$("$H/bin/apksigner" verify framework-res.apk 2>&1 | head -1)"
elif [ "$fw" = "$(digest "$K/platform.x509.pem")" ]; then ok "framework-res.apk 以 platform 金鑰簽"
else bad "framework-res.apk 不是我們的 platform 金鑰（$fw）"; fi

echo "=== 5. APEX 的 payload 公鑰 ==="
ours=$(for f in "$K"/*.avbpubkey; do sha256sum < "$f" | cut -c1-64; done | sort -u)
n=0; foreign=""
for a in $(sudo find "$S/apex" -maxdepth 1 \( -name "*.apex" -o -name "*.capex" \) | sort); do
    n=$((n + 1))
    sudo cat "$a" > apex.tmp
    h=$(python3 - apex.tmp <<'PY'
import zipfile, sys, hashlib, io
z = zipfile.ZipFile(sys.argv[1])
if "original_apex" in z.namelist():            # .capex：裡面包一個 .apex
    z = zipfile.ZipFile(io.BytesIO(z.read("original_apex")))
print(hashlib.sha256(z.read("apex_pubkey")).hexdigest())
PY
)
    echo "$ours" | grep -qx "$h" || foreign="$foreign $(basename "$a")"
done
if [ -z "$foreign" ]; then ok "$n 個 APEX 全是我們的金鑰"
else
    echo "        不是我們金鑰的：$foreign"
    echo "        （PRESIGNED 的預先簽好、改不了；其餘的代表私鑰目錄缺檔，退回了測試金鑰）"
    grep -o 'name="[^"]*" public_key="PRESIGNED"' "$SRC"/out-release/target/product/Z01G/obj/PACKAGING/apexkeys_intermediates/apexkeys.txt 2>/dev/null | cut -d'"' -f2 > presigned.txt || true
    real=""; for a in $foreign; do grep -qx "$a" presigned.txt || real="$real $a"; done
    [ -z "$real" ] && ok "其餘都是 PRESIGNED" || bad "退回測試金鑰的 APEX：$real"
fi

echo "=== 6. 個資 ==="
EXTRA="boot.kernel recovery.kernel z/META-INF/com/android/metadata z/META-INF/com/google/android/updater-script"
hits() { { sudo grep -rlaF -f "$1" m boot.rd recovery.rd 2>/dev/null; grep -laF -f "$1" $EXTRA 2>/dev/null; } \
         | sed -e 's#^m/#/#' -e 's#^boot.rd/#boot-ramdisk:/#' -e 's#^recovery.rd/#recovery-ramdisk:/#' | sort -u || true; }
local_path() { echo "$1" | sed -e 's#^/#m/#' -e 's#^boot-ramdisk:/#boot.rd/#' -e 's#^recovery-ramdisk:/#recovery.rd/#'; }
# 命中的是壓縮檔時拆開看是哪些檔命中。只有鍵盤的字典檔命中 = 一般單字剛好含那幾個字母
# （2026-09-27：LatinIME 的 res/raw/main_pl.dict，幾個波蘭文單字剛好含有樣式字串），列出來但不算失敗。
# （單字本身別寫進這裡：這支會公開，tools/150 會把它當成個資擋下來）
# 輸出：DICT <檔> 或 REAL <檔>
classify() {   # $1 = 樣式檔，stdin = 命中的檔名
    while read -r f; do
        case "$f" in
        *.apk|*.jar|*.apex|*.capex|*.zip)
            sudo cat "$(local_path "$f")" > arc.tmp
            python3 - arc.tmp "$1" "$f" <<'PY'
import sys, zipfile, re
arc, pats, name = sys.argv[1], sys.argv[2], sys.argv[3]
pats = [p.strip().lower().encode() for p in open(pats, encoding='utf-8') if p.strip()]
try:
    z = zipfile.ZipFile(arc)
    hit = [e for e in z.namelist() if any(p in z.read(e).lower() for p in pats)]
except zipfile.BadZipFile:
    hit = ['(不是 zip)']
ok = hit and all(re.match(r'res/raw/main_[a-z_]+\.dict$', e) for e in hit)
print(('DICT ' if ok else 'REAL ') + name + '  ->  ' + ', '.join(hit or ['(拆開後找不到：可能在 zip 目錄或壓縮前的資料)']))
PY
            ;;
        *) echo "REAL $f" ;;
        esac
    done
}
for set in public secret; do
    C=$(hits "$PII/$set.txt" | classify "$PII/$set.txt")
    R=$(echo "$C" | grep '^REAL ' || true); D=$(echo "$C" | grep '^DICT ' || true)
    [ -z "$D" ] || { echo "        $set 樣式只命中字典檔（一般單字，不算）："; echo "$D" | sed 's/^DICT /          /'; }
    if [ -z "$R" ]; then ok "$set 樣式：沒有真正的命中"
    else
        bad "$set 樣式命中 $(echo "$R" | wc -l) 個檔："; echo "$R" | head -20 | sed 's/^REAL /          /'
        if [ $set = public ]; then   # public 才印內容；secret 只列檔名
            for f in $(echo "$R" | head -5 | awk '{print $2}'); do
                sudo grep -aoF -f "$PII/public.txt" "$(local_path "$f")" 2>/dev/null | head -2 | sed "s#^#          [$f] #"
            done
        fi
    fi
done

echo
[ $fail = 0 ] && echo "全部通過：可以發布" || { echo "!!! 有項目沒過，不要發布"; exit 1; }
