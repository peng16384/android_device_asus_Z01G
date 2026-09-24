#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
從 Oreo 的 .vdex 取出裡面的 dex，並檢查有沒有被 quicken 過。

  python3 tools/98_vdex_extract.py <in.vdex> <輸出目錄>

vdex 是 Android 8.0 引進的格式，裡面直接存著**原始的 dex**
（不像 odex 只有編譯後的機器碼），所以 odex 過的 apk 要救回 dex，
從 vdex 挖比 baksmali 反編譯 odex 乾淨得多。

Header（version "006" = Android 8.0）：
    magic_[4]                 "vdex"
    version_[4]               "006\0"
    number_of_dex_files_      uint32
    dex_size_                 uint32
    verifier_deps_size_       uint32
    quickening_info_size_     uint32
    checksums_[n]             uint32 * number_of_dex_files_
    然後是 dex_size_ bytes 的 dex（可能多個，逐個讀 header 的 file_size_）

⚠ quickening：vdex 裡的 dex 可能被換成 quickened 指令
（iget-quick 0xE3 ~ invoke-virtual-quick-range 0xEA 那一段），
那是跟當初那顆 boot image 的 vtable 綁死的偏移量，換一個 Android 版本就是垃圾。
quickening_info_size_ > 0 就代表有，必須還原（unquicken）才能用。
這支只負責取出與判斷，不做還原 —— 真的需要還原時要用 vdexExtractor -f
或 baksmali，並且要拿當初那顆 boot image 當 bootclasspath。
"""
import os
import struct
import sys

QUICK_OPS = set(range(0xE3, 0xF3))   # iget-quick .. invoke-virtual-quick-range 等


def read_dex_sizes(blob):
    """依序讀每個 dex header 的 file_size_（offset 0x20），切出各個 dex。"""
    out, off = [], 0
    while off + 0x70 <= len(blob):
        if blob[off:off + 4] not in (b"dex\n", b"cdex"):
            break
        size = struct.unpack_from("<I", blob, off + 0x20)[0]
        if size <= 0 or off + size > len(blob):
            break
        out.append((off, size))
        off += (size + 3) & ~3          # 4-byte 對齊
    return out


def scan_quickened(dex):
    """粗掃 code item 裡有沒有 quickened opcode。
    不做完整的 dex 解析 —— 只看 map_list 指向的 code items。"""
    try:
        map_off = struct.unpack_from("<I", dex, 0x34)[0]
        n = struct.unpack_from("<I", dex, map_off)[0]
    except Exception:
        return None
    hits = 0
    for i in range(n):
        base = map_off + 4 + i * 12
        type_, _, size, off = struct.unpack_from("<HHII", dex, base)
        if type_ != 0x2001:             # TYPE_CODE_ITEM
            continue
        # code item 是變長的，逐個走太麻煩；這裡只掃那一段 bytes 的 opcode 低位元組
        end = len(dex)
        for j in range(off, min(off + size * 16, end), 2):
            if dex[j] in QUICK_OPS:
                hits += 1
    return hits


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    blob = open(src, "rb").read()

    if blob[:4] != b"vdex":
        sys.exit("!!! 不是 vdex（magic = %r）" % blob[:4])
    ver = blob[4:8].rstrip(b"\0").decode()
    n, dex_size, vdeps, quick = struct.unpack_from("<IIII", blob, 8)
    print("vdex version   %s" % ver)
    print("dex 檔數       %d" % n)
    print("dex 總大小     %d" % dex_size)
    print("verifier_deps  %d" % vdeps)
    print("quickening_info %d %s" % (quick, "  <-- 非 0，dex 被 quicken 過" if quick else ""))

    start = 24 + 4 * n
    body = blob[start:start + dex_size]
    parts = read_dex_sizes(body)
    if len(parts) != n:
        print("⚠ 切出 %d 個 dex，header 說有 %d 個" % (len(parts), n))

    os.makedirs(dst, exist_ok=True)
    for i, (off, size) in enumerate(parts):
        dex = body[off:off + size]
        name = "classes.dex" if i == 0 else "classes%d.dex" % (i + 1)
        path = os.path.join(dst, name)
        open(path, "wb").write(dex)
        hits = scan_quickened(dex)
        print("  %-14s %8d bytes   quickened opcode 疑似出現 %s 次"
              % (name, size, hits if hits is not None else "?"))

    if quick:
        print()
        print("⚠ quickening_info_size_ 非 0 —— 直接拿去用，執行期會在第一個")
        print("   quickened 指令上爆掉。要先 unquicken。")


if __name__ == "__main__":
    main()
