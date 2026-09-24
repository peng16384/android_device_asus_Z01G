#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 OTA zip 裡的 system.new.dat（已用 brotli 解開）還原成 ext4 映像。

  python3 tools/105_sdat2img.py system.transfer.list system.new.dat system.img

只支援 transfer list 第 4 版的全量包（只有 new / erase / zero），
也就是 LineageOS 16.0 的 `mka bacon` 產物。給 tools/105_diff_rom_zips.sh 用。
"""
import sys

BS = 4096


def ranges(s):
    a = [int(x) for x in s.split(",")]
    if a[0] != len(a) - 1:
        sys.exit("!!! range 格式不對：%s" % s[:60])
    return [(a[i], a[i + 1]) for i in range(1, len(a), 2)]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    tl, dat, out = sys.argv[1:]
    lines = open(tl).read().split("\n")
    if lines[0].strip() != "4":
        sys.exit("!!! 只支援 transfer list 第 4 版，這份是 %s" % lines[0])
    total = int(lines[1])
    last = 0
    with open(dat, "rb") as d, open(out, "wb") as o:
        for line in lines[4:]:
            if not line.strip():
                continue
            cmd, arg = line.split(" ", 1)
            if cmd not in ("new", "erase", "zero"):
                sys.exit("!!! 不支援的指令 %s（這不是全量包？）" % cmd)
            for s, e in ranges(arg):
                if cmd == "new":
                    o.seek(s * BS)
                    o.write(d.read((e - s) * BS))
                last = max(last, e)
        o.truncate(last * BS)
    print("%s：%d 個區塊（transfer list 宣告 %d 個有資料）" % (out, last, total))


if __name__ == "__main__":
    main()
