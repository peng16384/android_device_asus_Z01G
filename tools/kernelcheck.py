#!/usr/bin/env python3
"""
檢查 Image.gz-dtb（或 boot.img）的內容：kernel 版本字串、附加的 DTB 清單、
每個 DTB 的 model / qcom,msm-id / qcom,board-id。

用途：在「刷進手機」之前，先在 PC 上確認自編 kernel 真的長得像原廠的那顆。

ZS551KL 應該看到：
  - Linux version 4.4.78-perf+
  - 3 個附加 DTB：MSM 8998 v1 MTP / v2.1 MTP / HAMSTER RUMI
  - 手機是 soc_id 292、revision 2.1 → 會挑到 msm-id = (292, 0x00020001) 那顆

用法：kernelcheck.py <Image.gz-dtb 或 boot.img> [更多檔案...]
"""
import struct
import sys
import zlib

FDT_MAGIC = b'\xd0\x0d\xfe\xed'
FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


def be32(b, o):
    return struct.unpack_from('>I', b, o)[0]


def fdt_root_props(blob):
    """只解析 root node 的 properties，回傳 {name: bytes}。"""
    if blob[:4] != FDT_MAGIC:
        return {}
    off_struct = be32(blob, 8)
    off_strings = be32(blob, 12)
    p = off_struct
    props = {}
    depth = 0
    while p < len(blob) - 4:
        tok = be32(blob, p)
        p += 4
        if tok == FDT_BEGIN_NODE:
            depth += 1
            end = blob.index(b'\0', p)
            p = (end + 4) & ~3
            if depth > 1:          # 只要 root
                break
        elif tok == FDT_END_NODE:
            depth -= 1
            if depth <= 0:
                break
        elif tok == FDT_PROP:
            plen, noff = be32(blob, p), be32(blob, p + 4)
            p += 8
            name_end = blob.index(b'\0', off_strings + noff)
            name = blob[off_strings + noff:name_end].decode('latin1')
            if depth == 1:
                props[name] = blob[p:p + plen]
            p = (p + plen + 3) & ~3
        elif tok == FDT_NOP:
            continue
        else:                       # FDT_END 或壞資料
            break
    return props


def fmt_u32_pairs(data):
    if len(data) % 4:
        return data.hex()
    vals = struct.unpack('>%dI' % (len(data) // 4), data)
    return ', '.join(f'({vals[i]}, 0x{vals[i+1]:08x})' for i in range(0, len(vals) - 1, 2))


def split_gzip(blob):
    """解開第一段 gzip，回傳 (解壓內容, 尾巴剩下的 bytes)。"""
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)
    out = d.decompress(blob)
    return out, d.unused_data


def get_kernel_blob(data):
    """輸入可能是 boot.img 或裸的 Image.gz-dtb。"""
    if data[:8] == b'ANDROID!':
        ks, _, _, _, _, _, _, ps = struct.unpack_from('<8I', data, 8)
        return data[ps:ps + ks], 'boot.img 內的 kernel'
    return data, '裸 Image.gz-dtb'


def analyse(path):
    print('=' * 72)
    print(path)
    data = open(path, 'rb').read()
    blob, kind = get_kernel_blob(data)
    print(f'  類型          : {kind}')
    print(f'  kernel blob   : {len(blob):,} bytes')
    if blob[:2] != b'\x1f\x8b':
        print('  !!! 不是 gzip，無法分析')
        return

    img, tail = split_gzip(blob)
    print(f'  解壓後        : {len(img):,} bytes')
    print(f'  gzip 後尾巴   : {len(tail):,} bytes（附加 DTB 區）')

    i = img.find(b'Linux version')
    print('  版本字串      : ' + (img[i:i + 140].split(b'\0')[0].decode('latin1', 'replace')
                                  if i >= 0 else '!!! 找不到'))

    print(f'  附加 DTB:')
    off, n = 0, 0
    while True:
        j = tail.find(FDT_MAGIC, off)
        if j < 0:
            break
        size = be32(tail, j + 4)
        if size <= 0 or j + size > len(tail):
            break
        props = fdt_root_props(tail[j:j + size])
        model = props.get('model', b'').rstrip(b'\0').decode('latin1', 'replace')
        n += 1
        print(f'    [{n}] @0x{j:06x}  {size:>7,} bytes  {model}')
        for key in ('qcom,msm-id', 'qcom,board-id', 'qcom,pmic-id'):
            if key in props:
                print(f'          {key:14s} = {fmt_u32_pairs(props[key])}')
        off = j + size
    print(f'  DTB 總數      : {n}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    for p in sys.argv[1:]:
        try:
            analyse(p)
        except Exception as exc:                      # noqa: BLE001
            print(f'{p}: 分析失敗 {exc!r}')
