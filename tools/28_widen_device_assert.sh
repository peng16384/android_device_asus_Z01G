#!/usr/bin/env bash
#
# 放寬 ROM zip 開頭的裝置檢查，讓它也認得這台 TWRP 實際有設的屬性。
#
#   bash tools/28_widen_device_assert.sh <原本的.zip> <輸出的.zip>
#
# 在 WSL 內執行（Git Bash 沒有 zip 指令）。
#
# ## 為什麼需要
#
# LineageOS 的 updater-script 第一行是：
#   assert(getprop("ro.product.device") == "Z01G" ||
#          getprop("ro.build.product")  == "Z01G" || abort("E3004: ..."));
# 但這台的 TWRP（3.7.0_9-0，更早的 3.2.1 也一樣）兩個屬性都**沒有設**，
# 只有 ro.omni.device=Z01G 與 ro.product.name=omni_Z01G。
# 兩個條件都是空字串 -> 必定 abort -> TWRP 顯示 "updater process ended with ERROR: 7"。
#
# 這裡把那一行換成多認兩個屬性的版本：
#   ... || getprop("ro.omni.device") == "Z01G"
#       || getprop("ro.product.name") == "omni_Z01G" || abort("E3004: ...")
#
# ## 為什麼不是拿掉
#
# 這支原本叫 28_strip_device_assert.sh，做法是直接刪掉那一行 ——
# 自己刷自己的手機時無所謂，但公開發布的 zip 就會讓別的機型也刷得下去。
# 放寬之後三種情況都實測過（2026-09-25，只含這一行 + ui_print 的測試 zip，
# 用同一個 update-binary，在實機 TWRP 3.7.0_9-0 上執行）：
#   原本的檢查                  E3004 / ERROR: 7   （證實原本的問題）
#   放寬後的檢查                通過
#   放寬後、但裝置名稱寫錯       E3004 / ERROR: 7   （仍然擋得住別的機型）
#
# ## 為什麼不從 BoardConfig 解決
#
# TARGET_OTA_ASSERT_DEVICE 只能改「比對的名稱」，改不了「比對哪些屬性」；
# 屬性是空的，換什麼名稱都一樣失敗。
#
# 修改過的 zip 簽章會失效：TWRP 的「Zip signature verification」要保持不勾（預設就不勾）。
set -e -o pipefail

SRCZIP=$1; OUTZIP=$2
[ -f "$SRCZIP" ] && [ -n "$OUTZIP" ] || { echo "用法：$0 <原本的.zip> <輸出的.zip>" >&2; exit 1; }
[ "$(realpath "$SRCZIP")" != "$(realpath -m "$OUTZIP")" ] || { echo "!!! 輸出不能蓋掉來源" >&2; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
US=META-INF/com/google/android/updater-script

echo "=== 改寫第一行 ==="
mkdir -p "$WORK/$(dirname $US)"
unzip -p "$SRCZIP" "$US" > "$WORK/$US"
python3 - "$WORK/$US" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
OLD = ('assert(getprop("ro.product.device") == "Z01G" || '
       'getprop("ro.build.product") == "Z01G" || '
       'abort("E3004: This package is for device: Z01G; this device is " '
       '+ getprop("ro.product.device") + "."););')
NEW = ('assert(getprop("ro.product.device") == "Z01G" || '
       'getprop("ro.build.product") == "Z01G" || '
       'getprop("ro.omni.device") == "Z01G" || '
       'getprop("ro.product.name") == "omni_Z01G" || '
       'abort("E3004: This package is for device: Z01G; this device is " '
       '+ getprop("ro.product.device") + "."););')
if lines[0] == NEW:
    sys.exit("!!! 已經放寬過了")
if lines[0] != OLD:
    sys.exit("!!! 第一行與預期不同，格式可能變了，請人工檢查：\n    " + lines[0][:200])
if sum(l.startswith("assert(getprop(\"ro.product.device\")") for l in lines) != 1:
    sys.exit("!!! 裝置檢查不只一行")
lines[0] = NEW
open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("  " + NEW[:110] + " ...")
PY

cp -f "$SRCZIP" "$OUTZIP"
( cd "$WORK" && zip -q "$OUTZIP" "$US" )

echo "=== 驗證 ==="
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
la = a.read(us).decode().split("\n"); lb = b.read(us).decode().split("\n")
changed = [i for i in range(max(len(la), len(lb))) if la[i:i+1] != lb[i:i+1]]
if changed != [0]:
    sys.exit("!!! updater-script 有變的應該只有第 1 行，實際是：%s" % changed)
bad = b.testzip()
if bad:
    sys.exit("!!! zip 損毀：%s" % bad)
print("  其餘 %d 個檔案 CRC 完全相同；updater-script 只改了第 1 行；zip 完整" % (len(ia) - 1))
PY
ls -lh "$OUTZIP" | sed 's/^/  /'
sha256sum "$OUTZIP" | sed 's/^/  /'
