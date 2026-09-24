#!/usr/bin/env bash
# 從執行中的機器收集 SELinux AVC denial，整理成去重、排序、可讀的報告。
#
# 用法：bash tools/94_collect_denials.sh [輸出目錄]
# 預設輸出到 work/selinux/<timestamp>/
#
# 為什麼不直接用 audit2allow：
#   它會把 sysfs / proc / device 這類通用 type 整個放行，範圍太大。
#   這支只負責「把事實整理清楚」，規則還是人工判斷要標成哪個 type。
#
# ⚠ kernel 的 audit 限速是 5 筆/秒（logd 的 LogAudit.cpp 寫死），
#   開機那幾秒會丟掉大量訊息。腳本會把 "audit: ... lost" 的統計印出來，
#   看到非零就代表這一輪的結果是低估值，要多跑幾輪。

set -u
ADB="${ADB:-adb}"
OUT="${1:-work/selinux/$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"

run() { MSYS_NO_PATHCONV=1 "$ADB" shell "$@" 2>/dev/null | tr -d '\r'; }

echo "=== 裝置狀態 ==="
run getprop ro.build.display.id
run getprop sys.boot_completed
echo -n "enforce = "; run getenforce
echo -n "uptime  = "; run cut -d' ' -f1 /proc/uptime
echo

# --- 原始來源：dmesg（kernel audit）與 logcat 的 events buffer ----------
run dmesg                       > "$OUT/dmesg.txt"
MSYS_NO_PATHCONV=1 "$ADB" logcat -b all -d 2>/dev/null | tr -d '\r' > "$OUT/logcat.txt"

cat "$OUT/dmesg.txt" "$OUT/logcat.txt" \
  | grep -a 'avc: *denied' > "$OUT/avc_raw.txt"

echo "=== audit 丟失統計（非零代表這輪是低估值）==="
grep -aoE 'audit_lost=[0-9]+|lost=[0-9]+|audit: [0-9]+ callbacks suppressed' \
     "$OUT/dmesg.txt" | sort -u | tail -5
grep -ac 'rate limit' "$OUT/dmesg.txt" | sed 's/^/  rate limit 訊息: /'
echo

# --- 正規化：抽出 scontext / tcontext / tclass / perm / path ------------
python3 - "$OUT" <<'PY'
import re, sys, os, collections
out = sys.argv[1]
pat_perm = re.compile(r'denied\s+\{([^}]*)\}')
pat_kv   = re.compile(r'\b(scontext|tcontext|tclass|path|name|comm)=("[^"]*"|\S+)')
rows = collections.defaultdict(set)   # key -> set(perms)
paths = collections.defaultdict(set)  # key -> set(path)
for line in open(os.path.join(out, 'avc_raw.txt'), errors='replace'):
    m = pat_perm.search(line)
    if not m: continue
    perms = set(m.group(1).split())
    kv = {k: v.strip('"') for k, v in pat_kv.findall(line)}
    s = kv.get('scontext', '?').split(':')[2] if kv.get('scontext','').count(':')>=2 else kv.get('scontext','?')
    t = kv.get('tcontext', '?').split(':')[2] if kv.get('tcontext','').count(':')>=2 else kv.get('tcontext','?')
    c = kv.get('tclass', '?')
    key = (s, t, c)
    rows[key] |= perms
    p = kv.get('path') or kv.get('name')
    if p: paths[key].add(p)

# shell / su 網域的 denial 幾乎都是「我們自己下 adb 指令」造成的，不是裝置行為。
# 混在一起看會虛胖，也會誘使人為了讓 log 乾淨而加一堆 dontaudit shell ...。
#
# ⚠ su 也要分出來：enforcing 下查 denial 一定要先 adb root（否則讀不到 dmesg），
#   而 adb root 之後我們就在 u:r:su:s0 —— 每一句 mount / ls -Z / cat 都會
#   留下 permissive=1 的紀錄。2026-09-24 就這樣被自己的 `mount | grep` 騙過一次。
# 分開列。
def dump(keys, fh):
    for (s, t, c) in sorted(keys, key=lambda k: (k[0], k[1], k[2])):
        perms = ' '.join(sorted(rows[(s, t, c)]))
        fh.write('allow %s %s:%s { %s };\n' % (s, t, c, perms))
        for pp in sorted(paths[(s, t, c)])[:8]:
            fh.write('    # %s\n' % pp)

SELF = ('shell', 'su')
dev  = [k for k in rows if k[0] not in SELF]
mine = [k for k in rows if k[0] in SELF]
with open(os.path.join(out, 'denials.txt'), 'w') as f:
    dump(dev, f)
    if mine:
        f.write('\n' + '#' * 70 + '\n')
        f.write('# 以下是 shell 網域 —— 我們自己下的 adb 指令造成的，不是裝置行為。\n')
        f.write('# 通常不需要為它們寫政策。\n')
        f.write('#' * 70 + '\n')
        dump(mine, f)

print('=== 去重後 %d 條（另有 %d 條是我們自己的 adb 指令造成的）===' % (len(dev), len(mine)))
by_s = collections.Counter(k[0] for k in dev)
for s, c in by_s.most_common():
    print('  %-34s %s' % (s, c))
PY

echo
echo "報告：$OUT/denials.txt"
