#!/usr/bin/env python3
"""
遞迴檢查一個 ELF 能不能在我們建出來的 system 裡完整連結。

為什麼要遞迴：
    tools/61、65 那兩支只比對「這個檔案自己的 undefined 符號」對上
    「它直接 DT_NEEDED 的那些函式庫匯出的符號」—— 這會漏掉最要命的一種：
    相依函式庫**自己**缺符號。

    實例：gxFpDaemon 直接相依的 23 個函式庫全部找得到、它自己的 40 個符號
    也全部解得開，我因此判斷「連得起來」。但實際執行是：
        CANNOT LINK EXECUTABLE "/vendor/bin/gxFpDaemon": cannot locate symbol
          "keymaster::copy_size_and_data_from_buf(...UniquePtr<unsigned char[]>...)"
          referenced by "/system/lib64/libkeymaster1.so"
    —— 缺符號的是 libkeymaster1.so（Oreo 版 blob），而它要的
    libkeymaster_messages.so 是 Pie 版（UniquePtr 換成 std::unique_ptr，
    符號簽章不同）。Android 的 linker 是把整棵相依樹一起解析的，
    任何一層缺符號都會讓最上層的執行檔起不來。

限制：只看 DT_NEEDED。透過 BoardConfig 的 TARGET_LD_SHIM_LIBS 注入的
    shim 函式庫**不在** DT_NEEDED 裡（是 linker 在載入目標函式庫時才加進
    查找群組的），所以這支會照樣把被 shim 補上的符號報成「缺」。
    例：libshim_keymaster 補了 libkeymaster1.so 缺的那個 Oreo mangled name，
    但這支仍會對 gxFpDaemon 報錯 —— 那是誤報，要看實機 logcat 才算數。

    另外 __sanitizer_* 之類的弱符號也會被誤報（fpseek 被報過，但它實際跑得起來）。

用法：
    python3 tools/66_link_check.py <檔案> [<檔案> ...]
    python3 tools/66_link_check.py --all-services      # 掃所有 vendor/bin/hw
"""
import os
import subprocess
import sys

OUT = os.path.expanduser('~/lineage-16.0/out/target/product/Z01G/system')


def elf_bits(p):
    with open(p, 'rb') as fh:
        return 32 if fh.read(5)[4] == 1 else 64


def search_dirs(bits):
    sub = 'lib64' if bits == 64 else 'lib'
    return [f'{OUT}/{sub}', f'{OUT}/vendor/{sub}', f'{OUT}/vendor/{sub}/hw',
            f'{OUT}/{sub}/hw', f'{OUT}/vendor/{sub}/egl']


def readelf_needed(p):
    out = subprocess.run(['readelf', '-d', p], capture_output=True, text=True).stdout
    return [l.split('[')[1].rstrip(']') for l in out.splitlines() if '(NEEDED)' in l]


def syms(p, defined):
    flag = '--defined-only' if defined else '--undefined-only'
    out = subprocess.run(['nm', '-D', flag, p], capture_output=True, text=True).stdout
    return {l.split()[-1] for l in out.splitlines() if l.strip()}


def resolve(name, bits):
    for d in search_dirs(bits):
        p = os.path.join(d, name)
        if os.path.isfile(p):
            return p
    return None


def check(root):
    if not os.path.exists(root):
        print(f'  !!! {root} 不存在'); return False
    bits = elf_bits(root)
    # 把整棵相依樹收齊
    tree, queue, missing_libs = {}, [root], []
    while queue:
        p = queue.pop()
        if p in tree:
            continue
        tree[p] = readelf_needed(p)
        for n in tree[p]:
            if n in ('libc.so', 'libdl.so', 'libm.so', 'libstdc++.so',
                     'ld-android.so', 'libc++.so'):
                # 這幾個一定在，而且 nm 對 bionic 的結果不完整，跳過
                pass
            r = resolve(n, bits)
            if r is None:
                missing_libs.append((os.path.basename(p), n))
            elif r not in tree:
                queue.append(r)

    provided = set()
    for p in tree:
        provided |= syms(p, True)

    bad = []
    for p in tree:
        for s in syms(p, False) - provided:
            bad.append((os.path.relpath(p, OUT), s))

    ok = not bad and not missing_libs
    print(f'  {"OK " if ok else "!! "} {os.path.relpath(root, OUT)}  '
          f'（相依樹 {len(tree)} 個檔案）')
    for owner, lib in missing_libs[:5]:
        print(f'        找不到函式庫  {lib}   （{owner} 需要）')
    seen = set()
    for owner, s in bad[:8]:
        if owner in seen:
            continue
        seen.add(owner)
        dem = subprocess.run(['c++filt', s], capture_output=True, text=True).stdout.strip()
        print(f'        缺符號  {owner}')
        print(f'                {dem[:110]}')
    return ok


def main():
    args = sys.argv[1:]
    if args and args[0] == '--all-services':
        args = sorted(os.path.join(f'{OUT}/vendor/bin/hw', f)
                      for f in os.listdir(f'{OUT}/vendor/bin/hw'))
    if not args:
        sys.exit(__doc__)
    nbad = 0
    for a in args:
        p = a if a.startswith('/') else os.path.join(OUT, a)
        if not check(p):
            nbad += 1
    print(f'\n{len(args)} 個檢查完，{nbad} 個有問題')


if __name__ == '__main__':
    main()
