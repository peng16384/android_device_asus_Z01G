#!/usr/bin/env python3
"""
離線比對一個 .ko 的 __versions 區段與我們 kernel 的 Module.symvers。

為什麼需要：
    原廠的 qca_cld3_wlan.ko 是 Wi-Fi 驅動，kernel 原始碼裡沒有 qcacld，
    所以我們編不出來。想直接用原廠那顆的話有兩道關卡：
      1. CONFIG_MODULE_SIG_FORCE=y —— kernel 強制驗簽，原廠是 ASUS 的金鑰簽的。
         這個關掉 defconfig 就解決了。
      2. CONFIG_MODULE_VERSIONS（modversions）—— 模組用到的每個核心匯出符號
         都帶一個 CRC，載入時必須與 kernel 的完全相符。
         CRC 由結構佈局決定，而結構佈局受 config 影響 ——
         我們為了 adb 開了 CONFIG_AIO=y，那會在 mm_struct 加一個欄位
         （ioctx_table），凡是原型牽涉 mm_struct 的匯出符號 CRC 都會變。

    這支直接比對，不用刷機就知道答案。

用法（WSL）：
    python3 tools/71_ko_crc_check.py <ko 檔> [Module.symvers]
"""
import os
import re
import struct
import subprocess
import sys

DEFAULT_SYMVERS = (os.path.expanduser('~/lineage-16.0/out/target/product/Z01G/'
                   'obj/KERNEL_OBJ/Module.symvers'))


def ko_versions(path):
    """讀 .ko 的 __versions 區段：每筆 8 bytes CRC + 56 bytes 名稱（aarch64）。"""
    out = subprocess.run(['readelf', '-x', '__versions', path],
                         capture_output=True, text=True).stdout
    data = bytearray()
    for line in out.splitlines():
        m = re.match(r'\s*0x[0-9a-f]+\s+((?:[0-9a-f]{8}\s+){1,4})', line)
        if m:
            for word in m.group(1).split():
                # readelf -x 是按檔案順序輸出位元組，不要再反轉
                # （第一版做了 4-byte 反轉，結果符號名稱全是亂碼，
                #   369 個符號全部「找不到」—— 是解析錯不是真的不相容）
                data += bytes.fromhex(word)
    ent = 64          # 8 (crc, unsigned long) + 56 (name)
    res = {}
    for i in range(0, len(data) - ent + 1, ent):
        crc = struct.unpack('<Q', data[i:i + 8])[0]
        name = data[i + 8:i + ent].split(b'\0')[0].decode('ascii', 'replace')
        if name:
            res[name] = crc & 0xffffffff
    return res


def symvers(path):
    res = {}
    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            p = line.split()
            if len(p) >= 2:
                res[p[1]] = int(p[0], 16) & 0xffffffff
    return res


def main():
    ko = sys.argv[1]
    sv = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_SYMVERS
    mod = ko_versions(ko)
    ker = symvers(sv)
    print(f'模組需要 {len(mod)} 個匯出符號；kernel 的 Module.symvers 有 {len(ker)} 個')

    missing, mismatch, ok = [], [], 0
    for name, crc in sorted(mod.items()):
        if name not in ker:
            missing.append(name)
        elif ker[name] != crc:
            mismatch.append((name, crc, ker[name]))
        else:
            ok += 1
    print(f'  相符 {ok} / 缺 {len(missing)} / CRC 不合 {len(mismatch)}')
    if missing:
        print('  --- kernel 沒有匯出（模組一定載不進去）---')
        for n in missing[:15]:
            print(f'      {n}')
        if len(missing) > 15:
            print(f'      ... 另外 {len(missing) - 15} 個')
    if mismatch:
        print('  --- CRC 不合（會報 "disagrees about version of symbol"）---')
        for n, a, b in mismatch[:15]:
            print(f'      {n:<44} 模組 {a:#010x}  kernel {b:#010x}')
        if len(mismatch) > 15:
            print(f'      ... 另外 {len(mismatch) - 15} 個')
    print()
    print('結論：' + ('可以直接用原廠模組（只要關掉 MODULE_SIG_FORCE）'
                     if not missing and not mismatch else
                     '不能直接用，必須從原始碼編 qcacld'))


if __name__ == '__main__':
    main()
