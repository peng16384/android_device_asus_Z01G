#!/usr/bin/env python3
"""
檢查所有 blob 的動態連結相依性，找出「缺的函式庫」。

為什麼要這支：
    第一次開到 zygote 之後，發現所有 vendor HAL 都 exit(1)。logcat 顯示：
        F linker: CANNOT LINK EXECUTABLE "...": library "android.hidl.base@1.0.so" not found
    Android 9 把 android.hidl.base@1.0 從預設安裝拿掉了，但 Oreo 編的
    vendor 二進位檔全部連結它。除此之外還有 libkeymaster1.so、
    libmediacodecservice.so、libskia.so 等。

    一項一項從 logcat 撿太慢（每輪要重編+刷+開機約 15 分鐘），
    改成直接讀每個 blob 的 DT_NEEDED，一次把缺的全部列出來。

做法：
    1. 掃 vendor/asus/Z01G/proprietary 底下所有 ELF，取出 DT_NEEDED
    2. 組出「可用函式庫」集合 = 已編好的 system.img 內容 + 我們自己的 blob
    3. 兩者相減 = 缺的
    4. 再標示每個缺的函式庫在原廠映像裡有沒有（有 -> 可以補進 blob 清單）

用法（WSL，需先掛好 /mnt/zs_system）：
    python3 tools/36_check_blob_deps.py
"""
import os
import re
import struct
import subprocess
import sys

DEVICE_PATH = os.environ.get(
    'DEVICE_PATH',
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SRC = os.path.expanduser('~/lineage-16.0')
PROP = f'{SRC}/vendor/asus/Z01G/proprietary'
BUILT = f'{SRC}/out/target/product/Z01G/system'
MNT = '/mnt/zs_system'
OUT = os.path.join(DEVICE_PATH, 'blobs/missing_libs.txt')


def is_elf(path):
    try:
        with open(path, 'rb') as fh:
            return fh.read(4) == b'\x7fELF'
    except OSError:
        return False


def needed_of(path):
    """用 readelf -d 取 DT_NEEDED。"""
    try:
        out = subprocess.run(['readelf', '-d', path], capture_output=True,
                             text=True, timeout=30).stdout
    except (subprocess.SubprocessError, OSError):
        return []
    return re.findall(r'\(NEEDED\).*?\[([^\]]+)\]', out)


def elf_bits(path):
    try:
        with open(path, 'rb') as fh:
            return 64 if fh.read(5)[4] == 2 else 32
    except OSError:
        return 0


def collect_libs(root):
    """回傳 {(檔名, 位元數)} 集合。"""
    out = set()
    for dirpath, _d, files in os.walk(root):
        for fn in files:
            if not fn.endswith('.so'):
                continue
            p = os.path.join(dirpath, fn)
            if os.path.islink(p) or not is_elf(p):
                continue
            out.add((fn, elf_bits(p)))
    return out


def main():
    for p in (PROP, BUILT):
        if not os.path.isdir(p):
            sys.exit(f'!!! 找不到 {p}')

    print('=== 收集可用的函式庫 ===')
    avail = collect_libs(BUILT)
    print(f'  已編好的 system.img          {len(avail)}')
    prop_libs = collect_libs(PROP)
    print(f'  我們的 blob                  {len(prop_libs)}')
    avail |= prop_libs
    print(f'  合計可用                     {len(avail)}')

    print()
    print('=== 掃描 blob 的 DT_NEEDED ===')
    missing = {}          # (lib, bits) -> [誰需要它]
    n_elf = 0
    for dirpath, _d, files in os.walk(PROP):
        for fn in files:
            p = os.path.join(dirpath, fn)
            if os.path.islink(p) or not is_elf(p):
                continue
            n_elf += 1
            bits = elf_bits(p)
            rel = os.path.relpath(p, PROP)
            for lib in needed_of(p):
                if (lib, bits) not in avail:
                    missing.setdefault((lib, bits), []).append(rel)
    print(f'  檢查了 {n_elf} 個 ELF')
    print(f'  缺 {len(missing)} 個函式庫')

    # 原廠映像裡有沒有
    print()
    print('=== 缺的函式庫（依影響範圍排序）===')
    lines = []
    for (lib, bits), users in sorted(missing.items(), key=lambda x: -len(x[1])):
        sub = 'lib64' if bits == 64 else 'lib'
        cands = [f'{sub}/{lib}', f'vendor/{sub}/{lib}',
                 f'{sub}/hw/{lib}', f'vendor/{sub}/hw/{lib}']
        found = next((c for c in cands if os.path.exists(os.path.join(MNT, c))), None)
        mark = f'原廠有 -> {found}' if found else '原廠也沒有'
        print(f'  {lib:<46} {bits}bit  被 {len(users):>3} 個檔案需要   {mark}')
        for u in users[:3]:
            print(f'        {u}')
        if len(users) > 3:
            print(f'        ... 另外 {len(users)-3} 個')
        if found:
            lines.append(found)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8') as fh:
        fh.write('# blob 相依但目前缺少、而原廠映像裡有的函式庫\n')
        fh.write('# 產生：tools/36_check_blob_deps.py\n')
        fh.write('# 這些路徑可以直接加進 proprietary-files.txt\n')
        for l in sorted(set(lines)):
            fh.write(l + '\n')
    print()
    print(f'可從原廠補的 {len(set(lines))} 條已寫到 {OUT}')


if __name__ == '__main__':
    main()
