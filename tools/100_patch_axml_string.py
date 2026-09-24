#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 binary AndroidManifest.xml 字串池裡的某一條字串換掉（長度可以不同）。

  python3 tools/100_patch_axml_string.py <in.xml> <out.xml> <舊字串> <新字串>

## 為什麼不用 apktool

只要改一個 intent action，用 apktool 就得把整包資源 decode 再 build 一次
（aapt 重新編碼 resources.arsc），變動面遠大於需求。
binary XML 的字串池是自成一塊的：元素與屬性都是用**索引**參照字串，
所以只要重建那一塊並修好偏移量，其餘位元組完全不用動。

## 格式

    檔頭        u16 type=0x0003  u16 headerSize=8  u32 fileSize
    字串池      u16 type=0x0001  u16 headerSize=0x1C  u32 chunkSize
                u32 stringCount  u32 styleCount  u32 flags
                u32 stringsStart u32 stylesStart
                u32 stringOffsets[stringCount]
                u32 styleOffsets[styleCount]
                字串資料（UTF-16LE：u16 長度 + 字元 + 0x0000）
                樣式資料
    其餘塊      ResourceMap / StartNamespace / StartElement …（只存索引）

flags bit 8 (0x100) = UTF8_FLAG。aapt 產生的 AndroidManifest.xml 是 UTF-16，
這支只處理 UTF-16；遇到 UTF-8 的會直接中止，不會默默做錯。
"""
import struct
import sys


def parse_pool(data, off):
    (typ, hdr_size, chunk_size, n_str, n_sty, flags,
     str_start, sty_start) = struct.unpack_from("<HHIIIIII", data, off)
    if typ != 0x0001:
        sys.exit("!!! offset %d 不是字串池（type=0x%04x）" % (off, typ))
    if flags & 0x100:
        sys.exit("!!! 這份是 UTF-8 字串池，本工具只處理 UTF-16")
    str_offs = list(struct.unpack_from("<%dI" % n_str, data, off + hdr_size))
    sty_offs = list(struct.unpack_from("<%dI" % n_sty, data, off + hdr_size + 4 * n_str))
    base = off + str_start
    strings = []
    for o in str_offs:
        p = base + o
        ln = struct.unpack_from("<H", data, p)[0]
        if ln & 0x8000:                       # 超過 32767 的擴充長度
            ln = ((ln & 0x7FFF) << 16) | struct.unpack_from("<H", data, p + 2)[0]
            p += 4
        else:
            p += 2
        strings.append(data[p:p + ln * 2].decode("utf-16-le"))
    sty_data = b""
    if n_sty:
        end = off + chunk_size
        sty_data = data[off + sty_start:end]
    return dict(off=off, hdr_size=hdr_size, chunk_size=chunk_size, n_sty=n_sty,
                flags=flags, strings=strings, sty_offs=sty_offs, sty_data=sty_data)


def encode_string(s):
    b = s.encode("utf-16-le")
    n = len(s)
    if n > 0x7FFF:
        sys.exit("!!! 字串太長，本工具沒處理擴充長度的寫入")
    return struct.pack("<H", n) + b + b"\x00\x00"


def build_pool(pool, strings):
    blobs, offs, cur = [], [], 0
    for s in strings:
        offs.append(cur)
        b = encode_string(s)
        blobs.append(b)
        cur += len(b)
    str_data = b"".join(blobs)
    pad = (-len(str_data)) % 4
    str_data += b"\x00" * pad

    n_str, n_sty = len(strings), pool["n_sty"]
    hdr = 0x1C
    str_start = hdr + 4 * n_str + 4 * n_sty
    sty_start = (str_start + len(str_data)) if n_sty else 0
    chunk_size = str_start + len(str_data) + len(pool["sty_data"])

    out = struct.pack("<HHIIIIII", 0x0001, hdr, chunk_size, n_str, n_sty,
                      pool["flags"], str_start, sty_start)
    out += struct.pack("<%dI" % n_str, *offs)
    if n_sty:
        out += struct.pack("<%dI" % n_sty, *pool["sty_offs"])
    out += str_data + pool["sty_data"]
    return out


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    src, dst, old, new = sys.argv[1:5]
    data = open(src, "rb").read()

    typ, hdr_size, file_size = struct.unpack_from("<HHI", data, 0)
    if typ != 0x0003:
        sys.exit("!!! 不是 binary XML（type=0x%04x）" % typ)
    if file_size != len(data):
        sys.exit("!!! 檔頭的 fileSize=%d 與實際長度 %d 不符" % (file_size, len(data)))

    pool = parse_pool(data, hdr_size)
    strings = pool["strings"]
    hits = [i for i, s in enumerate(strings) if s == old]
    if not hits:
        sys.exit("!!! 字串池裡找不到 %r" % old)
    if len(hits) > 1:
        sys.exit("!!! %r 出現 %d 次，不確定該換哪一個" % (old, len(hits)))
    if new in strings:
        sys.exit("!!! %r 已經在字串池裡了" % new)
    idx = hits[0]
    print("字串池 %d 條，第 %d 條：" % (len(strings), idx))
    print("    %r" % old)
    print(" -> %r" % new)

    strings[idx] = new
    new_pool = build_pool(pool, strings)

    tail = data[hdr_size + pool["chunk_size"]:]
    out = bytearray(data[:hdr_size] + new_pool + tail)
    struct.pack_into("<I", out, 4, len(out))      # 檔頭的 fileSize
    open(dst, "wb").write(bytes(out))
    print("寫出 %s（%d -> %d bytes）" % (dst, len(data), len(out)))

    # 讀回來驗一次
    chk = parse_pool(open(dst, "rb").read(), hdr_size)
    if chk["strings"][idx] != new:
        sys.exit("!!! 寫回去之後讀不到新字串")
    if chk["strings"][:idx] != strings[:idx] or chk["strings"][idx + 1:] != strings[idx + 1:]:
        sys.exit("!!! 其餘字串有變動")
    print("驗證：第 %d 條已換，其餘 %d 條不變" % (idx, len(strings) - 1))


if __name__ == "__main__":
    main()
