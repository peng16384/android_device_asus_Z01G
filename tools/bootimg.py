#!/usr/bin/env python3
"""
Android boot image (header v0) 拆解／重打包工具 —— ZS551KL 專用。

設計原則：**重打包時把原始 header 逐 byte 沿用**，只更新 kernel/ramdisk/second 的
size 欄位與 id（SHA1）。offset、pagesize、os_version、cmdline 一律不重新推導，
因為推導就有猜錯的空間，而猜錯 = 刷進去開不了機。

ZS551KL 原廠 boot header 的特殊之處：base 是 0（kernel_addr=0x8000、tags_addr=0x100），
跟一般 qcom 的 0x80000000 不同 —— 正是不該自己重算的理由。

用法：
  bootimg.py info    <boot.img>
  bootimg.py unpack  <boot.img> <outdir>
  bootimg.py repack  --template <stock.img> --kernel <k> --ramdisk <r> --out <new.img>
  bootimg.py compare <a.img> <b.img>
"""
import argparse
import hashlib
import json
import os
import struct
import sys

MAGIC = b'ANDROID!'
HDR_FMT = '<8s10I16s512s8I1024s'
# magic, kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size,
# second_addr, tags_addr, page_size, header_version, os_version,
# name[16], cmdline[512], id[8*u32], extra_cmdline[1024]
HDR_LEN = struct.calcsize(HDR_FMT)   # 1632


class BootImage:
    def __init__(self, data):
        if data[:8] != MAGIC:
            raise ValueError('不是 Android boot image（magic 不符）')
        f = struct.unpack(HDR_FMT, data[:HDR_LEN])
        self.raw = data
        self.magic = f[0]
        (self.kernel_size, self.kernel_addr, self.ramdisk_size, self.ramdisk_addr,
         self.second_size, self.second_addr, self.tags_addr, self.page_size,
         self.header_version, self.os_version) = f[1:11]
        self.name = f[11]
        self.cmdline = f[12]
        self.id = f[13:21]
        self.extra_cmdline = f[21]

    def _pages(self, n):
        ps = self.page_size
        return (n + ps - 1) // ps

    @property
    def kernel_off(self):
        return self.page_size

    @property
    def ramdisk_off(self):
        return self.kernel_off + self._pages(self.kernel_size) * self.page_size

    @property
    def second_off(self):
        return self.ramdisk_off + self._pages(self.ramdisk_size) * self.page_size

    @property
    def content_len(self):
        return self.second_off + self._pages(self.second_size) * self.page_size

    def kernel(self):
        return self.raw[self.kernel_off:self.kernel_off + self.kernel_size]

    def ramdisk(self):
        return self.raw[self.ramdisk_off:self.ramdisk_off + self.ramdisk_size]

    def second(self):
        return self.raw[self.second_off:self.second_off + self.second_size]

    def describe(self):
        ov = self.os_version
        a, b, c = (ov >> 25) & 0x7f, (ov >> 18) & 0x7f, (ov >> 11) & 0x7f
        y, m = ((ov >> 4) & 0x7f) + 2000, ov & 0xf
        return {
            'file_size': len(self.raw),
            'content_len': self.content_len,
            'page_size': self.page_size,
            'header_version': self.header_version,
            'kernel_size': self.kernel_size,
            'kernel_addr': hex(self.kernel_addr),
            'ramdisk_size': self.ramdisk_size,
            'ramdisk_addr': hex(self.ramdisk_addr),
            'second_size': self.second_size,
            'second_addr': hex(self.second_addr),
            'tags_addr': hex(self.tags_addr),
            'os_version_raw': hex(self.os_version),
            'os_version': f'{a}.{b}.{c}',
            'os_patch_level': f'{y}-{m:02d}',
            'name': self.name.rstrip(b'\0').decode('latin1'),
            'cmdline': self.cmdline.rstrip(b'\0').decode('latin1'),
            'extra_cmdline': self.extra_cmdline.rstrip(b'\0').decode('latin1'),
            'id': ''.join(f'{x:08x}' for x in self.id),
            'tail_all_zero': self.raw[self.content_len:] == b'\0' * (len(self.raw) - self.content_len),
        }


def compute_id(kernel, ramdisk, second):
    """mkbootimg 的 id：對 (內容, 長度) 依序餵進 SHA1。"""
    h = hashlib.sha1()
    for blob in (kernel, ramdisk, second):
        h.update(blob)
        h.update(struct.pack('<I', len(blob)))
    digest = h.digest() + b'\0' * (32 - h.digest_size)
    return struct.unpack('<8I', digest)


def build(template: BootImage, kernel: bytes, ramdisk: bytes, second: bytes) -> bytes:
    ps = template.page_size
    pad = lambda b: b + b'\0' * ((-len(b)) % ps)

    new_id = compute_id(kernel, ramdisk, second)
    hdr = struct.pack(
        HDR_FMT, MAGIC,
        len(kernel), template.kernel_addr,
        len(ramdisk), template.ramdisk_addr,
        len(second), template.second_addr,
        template.tags_addr, ps,
        template.header_version, template.os_version,
        template.name, template.cmdline, *new_id, template.extra_cmdline,
    )
    assert len(hdr) == HDR_LEN
    return pad(hdr) + pad(kernel) + pad(ramdisk) + pad(second)


def load(path):
    with open(path, 'rb') as fh:
        return BootImage(fh.read())


def cmd_info(args):
    img = load(args.image)
    print(json.dumps(img.describe(), indent=2, ensure_ascii=False))


def cmd_unpack(args):
    img = load(args.image)
    os.makedirs(args.outdir, exist_ok=True)
    for name, blob in (('kernel', img.kernel()),
                       ('ramdisk', img.ramdisk()),
                       ('second', img.second())):
        p = os.path.join(args.outdir, name)
        with open(p, 'wb') as fh:
            fh.write(blob)
        print(f'{p:40s} {len(blob):>12,} bytes')
    with open(os.path.join(args.outdir, 'header.json'), 'w', encoding='utf-8') as fh:
        json.dump(img.describe(), fh, indent=2, ensure_ascii=False)
    print(f'{os.path.join(args.outdir, "header.json"):40s} (header 紀錄)')


def cmd_repack(args):
    tpl = load(args.template)
    with open(args.kernel, 'rb') as fh:
        kernel = fh.read()
    with open(args.ramdisk, 'rb') as fh:
        ramdisk = fh.read()
    second = b''
    if args.second and os.path.getsize(args.second) > 0:
        with open(args.second, 'rb') as fh:
            second = fh.read()

    out = build(tpl, kernel, ramdisk, second)
    with open(args.out, 'wb') as fh:
        fh.write(out)

    print(f'template : {args.template}')
    print(f'kernel   : {args.kernel} ({len(kernel):,} bytes)')
    print(f'ramdisk  : {args.ramdisk} ({len(ramdisk):,} bytes)')
    print(f'輸出     : {args.out} ({len(out):,} bytes)')
    limit = args.max_size
    if limit and len(out) > limit:
        print(f'!!! 超過分割區大小 {limit:,} bytes —— 不可刷入', file=sys.stderr)
        return 1
    if limit:
        print(f'分割區   : {limit:,} bytes，剩餘 {limit - len(out):,} bytes')
    return 0


def cmd_compare(args):
    a = open(args.a, 'rb').read()
    b = open(args.b, 'rb').read()
    n = min(len(a), len(b))
    same = a[:n] == b[:n]
    print(f'A: {args.a} ({len(a):,} bytes)')
    print(f'B: {args.b} ({len(b):,} bytes)')
    print(f'前 {n:,} bytes 相同: {same}')
    if not same:
        for i in range(n):
            if a[i] != b[i]:
                print(f'第一個差異 @ 0x{i:x} ({i:,}): A=0x{a[i]:02x} B=0x{b[i]:02x}')
                break
        return 1
    tail = a[n:] if len(a) > n else b[n:]
    if tail:
        all_zero = tail.count(0) == len(tail)
        print(f'較長的一方多出 {len(tail):,} bytes，全為 0x00: {all_zero}')
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)

    s = sub.add_parser('info');   s.add_argument('image');                    s.set_defaults(fn=cmd_info)
    s = sub.add_parser('unpack'); s.add_argument('image'); s.add_argument('outdir'); s.set_defaults(fn=cmd_unpack)

    s = sub.add_parser('repack')
    s.add_argument('--template', required=True, help='原廠 boot.img，header 從它沿用')
    s.add_argument('--kernel', required=True)
    s.add_argument('--ramdisk', required=True)
    s.add_argument('--second', default=None)
    s.add_argument('--out', required=True)
    s.add_argument('--max-size', type=int, default=33554432, help='boot 分割區大小（預設 32 MB）')
    s.set_defaults(fn=cmd_repack)

    s = sub.add_parser('compare'); s.add_argument('a'); s.add_argument('b'); s.set_defaults(fn=cmd_compare)

    args = p.parse_args()
    sys.exit(args.fn(args) or 0)


if __name__ == '__main__':
    main()
