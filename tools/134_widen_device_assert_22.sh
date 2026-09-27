#!/usr/bin/env bash
#
# 22.2：放寬 zip 的裝置檢查，讓這台的 TWRP 也認得（在 WSL 內執行）
#
#   bash tools/134_widen_device_assert_22.sh <原本的.zip> <輸出的.zip>
#
# 16.0 的 tools/28 同一件事，但它把整行寫死（16.0 只比 Z01G 一個名稱、單行）。22.2 的檢查比
# TARGET_OTA_ASSERT_DEVICE 的 4 個名稱、跨好幾行 -> 改成在 abort("E3004 前面插兩個條件：
#   getprop("ro.omni.device") == "Z01G" || getprop("ro.product.name") == "omni_Z01G" ||
# 原因：這台 TWRP（3.7.0_9-0）的 ro.product.device / ro.build.product 都是空的，只有 ro.omni.device、
# ro.product.name（tools/28 的說明與實測）。原本的檢查必定 E3004 / ERROR: 7。
# 放寬不是拿掉：別的機型（ro.omni.device 不是 Z01G）仍然擋得住。
#
# 修改過的 zip 簽章會失效：TWRP 的「Zip signature verification」保持不勾（預設就不勾）。
set -e -o pipefail

SRCZIP=$1; OUTZIP=$2
[ -f "$SRCZIP" ] && [ -n "$OUTZIP" ] || { echo "用法：$0 <原本的.zip> <輸出的.zip>" >&2; exit 1; }
[ "$(realpath "$SRCZIP")" != "$(realpath -m "$OUTZIP")" ] || { echo "!!! 輸出不能蓋掉來源" >&2; exit 1; }
# 一定要轉成絕對路徑：下面 zip 是在 cd "$WORK" 之後執行的，相對路徑會更新到暫存目錄裡的另一個檔案，
# 真正的輸出只是來源的複本（2026-09-25 實測；最後的 CRC 比對有擋下來）
SRCZIP=$(realpath "$SRCZIP"); OUTZIP=$(realpath -m "$OUTZIP")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
US=META-INF/com/google/android/updater-script

mkdir -p "$WORK/$(dirname $US)"
unzip -p "$SRCZIP" "$US" > "$WORK/$US"
python3 - "$WORK/$US" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
ADD = 'getprop("ro.omni.device") == "Z01G" || getprop("ro.product.name") == "omni_Z01G" || '
if ADD in t:
    sys.exit("!!! 已經放寬過了")
if t.count('abort("E3004:') != 1:
    sys.exit("!!! E3004 的裝置檢查不是剛好一個，格式可能變了，請人工檢查")
head = t[:t.index('abort("E3004:')]
if not head.lstrip().startswith('assert(getprop("ro.product.device") == "Z01G"'):
    sys.exit("!!! 裝置檢查不在開頭，或第一個名稱不是 Z01G，請人工檢查")
t = t.replace('abort("E3004:', ADD + 'abort("E3004:', 1)
open(p, "w", encoding="utf-8", newline="").write(t)
print("  已插入：" + ADD)
PY

cp -f "$SRCZIP" "$OUTZIP"
( cd "$WORK" && zip -q "$OUTZIP" "$US" )

python3 - "$SRCZIP" "$OUTZIP" "$US" <<'PY'
import sys, zipfile
a, b, us = zipfile.ZipFile(sys.argv[1]), zipfile.ZipFile(sys.argv[2]), sys.argv[3]
ia = {i.filename: i for i in a.infolist()}
ib = {i.filename: i for i in b.infolist()}
if set(ia) != set(ib):
    sys.exit("!!! 檔案清單不同：%s" % (set(ia) ^ set(ib)))
diff = [n for n in ia if ia[n].CRC != ib[n].CRC]
if diff != [us]:
    sys.exit("!!! 有變的應該只有 updater-script，實際是：%s" % diff)
ta, tb = a.read(us).decode(), b.read(us).decode()
ADD = 'getprop("ro.omni.device") == "Z01G" || getprop("ro.product.name") == "omni_Z01G" || '
if tb.replace(ADD, '', 1) != ta:
    sys.exit("!!! updater-script 除了插入的兩個條件之外還有別的變動")
bad = b.testzip()
if bad:
    sys.exit("!!! zip 損毀：%s" % bad)
print("  其餘 %d 個檔案 CRC 完全相同；updater-script 只多了那兩個條件；zip 完整" % (len(ia) - 1))
PY
ls -lh "$OUTZIP" | sed 's/^/  /'
sha256sum "$OUTZIP" | sed 's/^/  /'
