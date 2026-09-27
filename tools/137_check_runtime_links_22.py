#!/usr/bin/env python3
#
# 22.2：照「執行期」的搜尋順序檢查 vendor ELF 的符號解析（在 lineage22 distro 內）
#
#   python3 device/asus/Z01G/tools/137_check_runtime_links_22.py [> 報告]
#
# 為什麼要有這支：這台不是 Treble，linkerconfig 用 [legacy] 設定 —— 只有一個 default namespace，
# 搜尋順序是 /system -> /system/system_ext -> /system/product -> /vendor -> /odm（裝置上的
# /linkerconfig/ld.config.txt 實測）。vendor blob 需要的函式庫如果 /system 也有一份同名的，
# **載到的是 system 那份**。建置時的 check_elf 是對 vendor 變體的宣告依賴檢查，看不到這件事。
# 2026-09-25 已踩到的：
#   - libwvhidl.so 要 libprotobuf-cpp-lite.so 的舊符號，拿到 A15 的 system 版 -> Widevine HAL 每秒崩潰
#   - audio HAL 與 libbinder_ndk 共用 system 的 libbinder（那次是行為差異，不是符號，這支抓不到）
#
# 輸出兩類：
#   撞名   未解析的符號，其實在「被 system 同名庫遮住的 vendor 版」裡有定義 -> 幾乎一定是真的壞
#   缺符號 整個搜尋範圍都找不到（lib 的部分可能由載入它的行程提供，信心較低）
import os
import re
import subprocess
import sys
from collections import defaultdict

SRC = os.path.expanduser('~/lineage-22.2')
O = SRC + '/out/target/product/Z01G'
RE = SRC + '/prebuilts/clang/host/linux-x86/llvm-binutils-stable/llvm-readelf'

SEARCH = {  # 與 /linkerconfig/ld.config.txt 的 [legacy] 相同
    'lib64': ['system/lib64', 'system/system_ext/lib64', 'system/product/lib64', 'system/vendor/lib64'],
    'lib': ['system/lib', 'system/system_ext/lib', 'system/product/lib', 'system/vendor/lib'],
}
# APEX 提供的（libc / libm / libdl、libandroidicu…）：不在 search paths，經 namespace link 看得到。
# system/apex 裡是壓縮的 .capex，未壓縮的內容看 symbols/apex（未 strip，動態符號表相同）
import glob
APEX_DIRS = {
    b: sorted(glob.glob('%s/symbols/apex/*/%s' % (O, b)) + glob.glob('%s/symbols/apex/*/%s/bionic' % (O, b)))
    for b in ('lib64', 'lib')
}

_cache = {}


def elf_info(path):
    """回傳 (is_elf, bits, needed[], defined set, undefined set(非 weak))"""
    if path in _cache:
        return _cache[path]
    r = subprocess.run([RE, '-h', '-d', '--dyn-syms', '--wide', path], capture_output=True, text=True)
    if r.returncode != 0 or 'ELF Header' not in r.stdout:
        _cache[path] = None
        return None
    bits = 'lib64' if 'ELF64' in r.stdout else 'lib'
    needed = re.findall(r'\(NEEDED\)\s+Shared library: \[([^\]]+)\]', r.stdout)
    defined, undefined = set(), set()
    for line in r.stdout.splitlines():
        m = re.match(r'\s*\d+:\s+[0-9a-f]+\s+\d+\s+(\w+)\s+(\w+)\s+\w+\s+(\S+)\s+(\S+)', line)
        if not m:
            continue
        typ, bind, ndx, name = m.groups()
        name = name.split('@')[0]
        if not name:
            continue
        if ndx == 'UND':
            if bind == 'GLOBAL':
                undefined.add(name)
        elif bind in ('GLOBAL', 'WEAK'):
            defined.add(name)
    _cache[path] = (bits, needed, defined, undefined)
    return _cache[path]


def resolve(name, bits):
    for d in SEARCH[bits]:
        p = os.path.join(O, d, name)
        if os.path.isfile(p):
            return p
    for d in APEX_DIRS[bits]:
        p = os.path.join(d, name)
        if os.path.isfile(p):
            return p
    return None


def shadowed_vendor(name, bits):
    """被 system 同名庫遮住的 vendor 版"""
    v = os.path.join(O, SEARCH[bits][-1], name)
    r = resolve(name, bits)
    if os.path.isfile(v) and r and os.path.realpath(r) != os.path.realpath(v):
        return v
    return None


def closure(path, bits):
    order, seen, missing = [path], {path}, []
    i = 0
    while i < len(order):
        info = elf_info(order[i])
        i += 1
        if not info:
            continue
        for n in info[1]:
            p = resolve(n, bits)
            if p is None:
                missing.append(n)
            elif p not in seen:
                seen.add(p)
                order.append(p)
    return order, missing


def main():
    roots = []
    for sub in ('system/vendor/bin', 'system/vendor/lib', 'system/vendor/lib64'):
        for dp, _, fs in os.walk(os.path.join(O, sub)):
            for f in fs:
                p = os.path.join(dp, f)
                if not os.path.islink(p) and (sub.endswith('bin') or f.endswith('.so')):
                    roots.append(p)
    collide, missing_sym, missing_lib = [], [], defaultdict(set)
    for p in sorted(roots):
        info = elf_info(p)
        if not info:
            continue
        bits = info[0]
        libs, miss = closure(p, bits)
        for m in miss:
            missing_lib[m].add(os.path.relpath(p, O))
        defs = set()
        for l in libs:
            i = elf_info(l)
            if i:
                defs |= i[2]
        und = set()
        for l in libs:
            i = elf_info(l)
            if i:
                und |= i[3]
        unresolved = und - defs
        if not unresolved:
            continue
        # 哪些是被遮住的 vendor 同名庫能提供的
        fixable = defaultdict(set)
        for l in libs:
            v = shadowed_vendor(os.path.basename(l), bits)
            if v:
                vi = elf_info(v)
                if vi:
                    for s in unresolved & vi[2]:
                        fixable[os.path.basename(l)].add(s)
        rel = os.path.relpath(p, O)
        if fixable:
            collide.append((rel, {k: sorted(v) for k, v in fixable.items()}))
        rest = unresolved - set().union(*fixable.values()) if fixable else unresolved
        if rest:
            missing_sym.append((rel, sorted(rest)))

    print('=== 撞名：system 的同名庫遮住了 vendor 版，vendor 版才有需要的符號（%d）===' % len(collide))
    for rel, fx in collide:
        print(rel)
        for lib, syms in fx.items():
            print('    %-36s %d 個，例：%s' % (lib, len(syms), ', '.join(syms[:3])))
    print('\n=== 缺函式庫（搜尋範圍內找不到）===')
    for n, who in sorted(missing_lib.items()):
        print('  %-40s <- %s' % (n, ', '.join(sorted(who)[:4]) + (' ...' if len(who) > 4 else '')))
    print('\n=== 缺符號（整個範圍都沒有；lib 可能由宿主行程提供）（%d）===' % len(missing_sym))
    for rel, syms in missing_sym:
        kind = 'bin' if '/bin/' in rel else 'lib'
        print('  [%s] %s  %d 個，例：%s' % (kind, rel, len(syms), ', '.join(syms[:3])))


if __name__ == '__main__':
    main()
