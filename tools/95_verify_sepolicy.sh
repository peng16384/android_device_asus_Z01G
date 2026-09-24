#!/usr/bin/env bash
# 驗證自訂的 SELinux 政策真的編進映像了。
#
# 為什麼需要這支：sepolicy 的失敗方式很安靜 —— 少了一個 BOARD_SEPOLICY_DIRS、
# 檔案放錯 public/private/vendor、file_contexts 的正規表示式沒對上，
# **編譯全部會過**，只是規則沒進去，要等刷機開機才發現。
#
# 用法：bash tools/95_verify_sepolicy.sh
# 建置身分與 WSL distro：需要時用環境變數覆蓋
#   BUILD_USER=alice WSL_DISTRO=ubuntu2004 bash tools/xxx.sh
BUILD_USER="${BUILD_USER:-${SUDO_USER:-$(id -un)}}"
WSL_DISTRO="${WSL_DISTRO:-ubuntu2004}"

set -u
OUT=$HOME/lineage-16.0/out/target/product/Z01G
SRC=$HOME/lineage-16.0/device/asus/Z01G/sepolicy

cat > /tmp/_vs.sh <<'INNER'
set -u
OUT=$HOME/lineage-16.0/out/target/product/Z01G
SRC=$HOME/lineage-16.0/device/asus/Z01G/sepolicy
P=$OUT/root/sepolicy
fail=0

echo "=== 1. 自訂 type 是否存在於編好的 sepolicy ==="
TYPES=$(grep -rhoE '^type [a-z_0-9]+' $SRC/*/*.te | awk '{print $2}' | sort -u)
for t in $TYPES; do
  n=$(grep -c "$t" $P 2>/dev/null || echo 0)
  if [ "$n" -gt 0 ]; then printf '  \033[32mOK\033[0m   %-28s\n' "$t"
  else printf '  \033[31mMISS\033[0m %-28s\n' "$t"; fail=1; fi
done

echo
echo "=== 2. 執行檔標記：file_contexts 的每一條都要對得上真實檔案 ==="
python3 - "$SRC" "$OUT" <<'PYEOF'
import sys, os, glob, re
src, out = sys.argv[1], sys.argv[2]
for fc in glob.glob(os.path.join(src, '*', 'file_contexts')):
    for line in open(fc, errors='replace'):
        line = line.strip()
        if not line.startswith('/'): continue
        parts = line.split()
        if len(parts) < 2: continue
        pat, ctx = parts[0], parts[-1]
        if pat.startswith(('/dev/', '/proc/', '/sys/')):
            print('  --   %-58s (執行期節點，跳過)' % pat); continue
        # /(vendor|system/vendor)/... -> 實際安裝位置；去掉正規表示式的跳脫
        p = re.sub(r'^/\(vendor\|system/vendor\)', '/system/vendor', pat).replace(chr(92), '')
        ok = os.path.exists(out + p)
        print('  %s %-58s -> %s' % ('[32mOK[0m  ' if ok else '[31mMISS[0m',
                                    p, ctx.replace('u:object_r:', '')))
PYEOF

echo
echo "=== 3. 網域轉換（init 執行它時會不會換網域）==="
for d in gx_fpd fpseek sar_setting modem_country hal_drm_widevine; do
  if grep -q "type_transition init ${d}_exec" $P 2>/dev/null || grep -q "${d}_exec" $P 2>/dev/null; then
    printf '  \033[32mOK\033[0m   %-20s exec type 在 policy 裡\n' "$d"
  else
    printf '  \033[31mMISS\033[0m %-20s\n' "$d"; fail=1
  fi
done

echo
echo "=== 3b. 兩個重複犯過的錯（靜態檢查）==="
python3 - "$SRC" <<'PYEOF'
import sys, os, re, glob
src = sys.argv[1]
rules = []
for f in glob.glob(os.path.join(src, '*', '*.te')):
    for line in open(f, errors='replace'):
        line = line.split('#')[0].strip()
        m = re.match(r'allow\s+(\S+)\s+(\S+):(\w+)\s', line)
        if m:
            rules.append((m.group(1), m.group(2), m.group(3)))

# (1) 有 :file 卻沒有 :dir —— 開檔案要對路徑上每層目錄有 search。
#     漏了的話可能被 dontaudit 完全蓋住（Wi-Fi 就是這樣壞的，
#     AOSP 的 hal_wifi_supplicant_default.te:32 把那條目錄 denial 靜音了）。
#     proc_* / vendor_file 不算：AOSP 的 domain.te 已給全網域目錄存取。
SKIP = re.compile(r'^(proc|vendor_file|sysfs)$|^proc_')
files = {(d, t) for d, t, c in rules if c == 'file' and not SKIP.match(t)}
# 光有 :dir 規則不夠，必須含 search —— 沒有 search 就進不去那個目錄。
# （實測踩過：wpa_socket 給了 { write remove_name setattr add_name } 卻沒 search，
#   症狀換成 wpa_supplicant「Failed to initialize control interface」。）
SEARCHY = ('search', 'rw_dir_perms', 'r_dir_perms', 'create_dir_perms', 'w_dir_perms')
dirs = set()
for f2 in glob.glob(os.path.join(src, '*', '*.te')):
    for line in open(f2, errors='replace'):
        line = line.split('#')[0].strip()
        m = re.match(r'allow\s+(\S+)\s+(\S+):dir\s+(.*?);', line)
        if m and any(k in m.group(3) for k in SEARCHY):
            dirs.add((m.group(1), m.group(2)))
# (1b) 每一條 :dir 規則本身都必須含 search —— 沒有 search 就進不去目錄。
#      （實測踩過三次：wpa_socket 只給 write/add_name/remove_name、
#        vendor_init 對 nfc/dpm/connectivity 只給 setattr。）
nosearch = []
for f3 in glob.glob(os.path.join(src, '*', '*.te')):
    for line in open(f3, errors='replace'):
        line = line.split('#')[0].strip()
        m = re.match(r'allow\s+(\S+)\s+(\S+):dir\s+(.*?);', line)
        if m and not any(k in m.group(3) for k in SEARCHY):
            nosearch.append((m.group(1), m.group(2), m.group(3).strip()))
if nosearch:
    print('  [31m:dir 規則沒有 search[0m（進不去目錄，操作會失敗）：')
    for d, t, p in nosearch:
        print('     %-30s %-26s %s' % (d, t, p))
else:
    print('  [32mOK[0m   每條 :dir 規則都含 search')

miss = sorted(files - dirs)
if miss:
    print('  [31m有 :file 但沒有含 search 的 :dir[0m（開檔案會失敗，而且可能無聲）：')
    for d, t in miss:
        print('     %-34s %s' % (d, t))
else:
    print('  [32mOK[0m   每個 :file 授權都有對應的 :dir')

# (2) 自訂屬性型別忘了配 get_prop —— 搬走屬性等於拿掉所有人的讀取權。
ptypes, got = [], set()
for f in glob.glob(os.path.join(src, '*', '*.te')):
    body = open(f, errors='replace').read()
    ptypes += re.findall(r'^type\s+(\w+),\s*property_type', body, re.M)
    got |= set(re.findall(r'get_prop\(\s*\w+\s*,\s*(\w+)\s*\)', body))
# ⚠ 不能只看自己宣告的型別 —— 把某個屬性**改標成別人（qcom/AOSP）的型別**
#   一樣會拿掉原本讀得到的人的權限。實測：ro.alarm_boot 改標成
#   vendor_alarm_boot_prop 之後 system_server 與 time_daemon 都讀不到。
#   所以要掃 property_contexts 裡出現的每一個型別。
for f in glob.glob(os.path.join(src, '*', 'property_contexts')):
    for line in open(f, errors='replace'):
        line = line.split('#')[0].strip()
        m = re.match(r'\S+\s+u:object_r:(\w+):s0', line)
        if m:
            ptypes.append(m.group(1))
ptypes = sorted(set(ptypes))
# ctl.* 是唯寫的控制屬性（init 用 ctl.start$<服務名> 檢查誰能啟動服務），
# 沒有人會去讀它們，AOSP 自己的 ctl_*_prop 也都沒有 get_prop。
miss2 = [t for t in ptypes if t not in got and not t.startswith('ctl_')]
if miss2:
    print('  [31m屬性型別缺 get_prop[0m（讀的人會被擋）：')
    for t in miss2:
        print('     %s' % t)
else:
    print('  [32mOK[0m   %d 個屬性型別都有 get_prop' % len(ptypes))
PYEOF

echo
echo "=== 4. 實際裝進映像的 context 檔 ==="
# 註：本機非 Treble，沒有獨立的 vendor_sepolicy.cil —— 政策全部併進
#     root/sepolicy 這顆單體檔案。所以這裡不找它。
for f in vendor_file_contexts vendor_property_contexts plat_file_contexts vndservice_contexts; do
  p=$(find $OUT/root $OUT/system -maxdepth 3 -name "$f" 2>/dev/null | head -1)
  [ -n "$p" ] && printf '  %-26s %s\n' "$f" "$(wc -l < "$p") 行" || printf '  %-26s \033[31m找不到\033[0m\n' "$f"
done

echo
echo "=== 5. 我們新增的條目有沒有真的進去 ==="
check() { n=$(grep -c "$2" "$1" 2>/dev/null || echo 0); printf '  %-34s %s 筆\n' "$(basename $1)" "$n"; }
VFC=$(find $OUT/root -name vendor_file_contexts | head -1)
VPC=$(find $OUT/root -name vendor_property_contexts | head -1)
VSC=$(find $OUT/root -name vndservice_contexts | head -1)
PFC=$(find $OUT/root -name plat_file_contexts | head -1)
[ -n "$VFC" ] && check "$VFC" 'gxFpDaemon\|sar_setting\|asusRgbSensor\|widevine'
[ -n "$VPC" ] && check "$VPC" 'asus_\|legacy_'
[ -n "$VSC" ] && check "$VSC" 'goodix.fp'
[ -n "$PFC" ] && check "$PFC" 'modem_country'

exit $fail
INNER
MSYS_NO_PATHCONV=1 wsl -d "$WSL_DISTRO" -u "$BUILD_USER" -- bash /tmp/_vs.sh
