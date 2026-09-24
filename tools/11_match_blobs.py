#!/usr/bin/env python3
"""
拿參考機的 proprietary-files.txt 去比對我們的 system.img，
產出 Z01G 自己的 blob 清單草稿。

做法：
  1. 讀入各參考樹的 proprietary-files.txt，正規化成一組候選路徑
  2. 逐項檢查該路徑在掛載好的 system.img 裡是否存在
  3. 分成「有」「沒有」兩類輸出，並統計各參考樹的命中率
  4. 另外掃出 ASUS 特有、沒有任何參考樹提到的 blob（相機/指紋/觸控/雷射對焦等）

proprietary-files.txt 的格式（LineageOS）：
    # 註解
    vendor/lib/libfoo.so                 一般項目
    -vendor/lib/libbar.so                開頭的 '-' = 產生 BUILD_PREBUILT 模組（不是單純複製）
    vendor/lib/libbaz.so|abc123...       '|' 後面是 SHA1
    src/path:dest/path                   來源與目的地不同
路徑是相對於 /system。

用法（在 WSL 內，需先掛好 /mnt/zs_system）：
    python3 tools/11_match_blobs.py
"""
import os
import re
import sys
from collections import OrderedDict

DEVICE_PATH = os.environ.get(
    'DEVICE_PATH',
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

MNT = '/mnt/zs_system'
REF = os.path.expanduser('~/zs551kl/reference')
OUT = os.path.join(DEVICE_PATH, 'blobs')

# ASUS / 本機特有硬體的關鍵字 —— 參考機不會有，要自己補
ASUS_HINTS = [
    'asus', 'arcsoft', 'laser', 'goodix', 'gf_', 'fingerprint',
    'focal', 'ft5', 'ftsc', 'rm67198', 'tfa', 'nq_nci', 'nqnfc',
]


def parse_prop_files(path):
    """回傳 [(原始行, 來源路徑)]，已去掉註解與空行。"""
    out = []
    with open(path, encoding='utf-8', errors='replace') as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            entry = line.lstrip('-')            # 去掉 '-' 前綴（BUILD_PREBUILT 標記）
            entry = entry.split('|', 1)[0]      # 去掉 |SHA1
            src = entry.split(':', 1)[0]        # src:dest -> src
            src = src.strip()
            if src:
                out.append((line, src))
    return out


def main():
    if not os.path.ismount(MNT):
        sys.exit(f'!!! {MNT} 沒掛載，先跑 tools/07_mount_system.sh')
    if not os.path.isdir(REF):
        sys.exit(f'!!! 找不到參考樹 {REF}，先跑 tools/10_fetch_reference_trees.sh')
    os.makedirs(OUT, exist_ok=True)

    # --- 1. 收集參考清單 -------------------------------------------------
    lists = []
    for root, _dirs, files in os.walk(REF):
        for fn in files:
            if re.fullmatch(r'proprietary-files.*\.txt', fn):
                p = os.path.join(root, fn)
                rel = os.path.relpath(p, REF)
                lists.append((rel, parse_prop_files(p)))
    lists.sort()
    if not lists:
        sys.exit('!!! 參考樹裡找不到任何 proprietary-files.txt')

    print('=== 參考清單 ===')
    for rel, entries in lists:
        print(f'  {rel:<52} {len(entries):>5} 條')

    # --- 2. 比對 ---------------------------------------------------------
    have = OrderedDict()      # src -> 來自哪些清單
    miss = OrderedDict()
    for rel, entries in lists:
        for _line, src in entries:
            target = os.path.join(MNT, src)
            bucket = have if os.path.lexists(target) else miss
            bucket.setdefault(src, []).append(rel)

    print()
    print('=== 各參考樹命中率 ===')
    for rel, entries in lists:
        srcs = {s for _l, s in entries}
        hit = sum(1 for s in srcs if s in have)
        pct = hit / len(srcs) * 100 if srcs else 0
        print(f'  {rel:<52} {hit:>4}/{len(srcs):<4} ({pct:5.1f} %)')

    print()
    print(f'=== 合計：候選 {len(have) + len(miss)} 條，'
          f'本機有 {len(have)} 條，本機沒有 {len(miss)} 條 ===')

    with open(f'{OUT}/candidates_present.txt', 'w', encoding='utf-8') as fh:
        fh.write('# 參考機清單中、我們的 system.img 也有的檔案\n')
        fh.write('# 格式：路徑  <- 來自哪些參考清單\n')
        for src, refs in sorted(have.items()):
            fh.write(f'{src}  <- {", ".join(sorted(set(refs)))}\n')

    with open(f'{OUT}/candidates_missing.txt', 'w', encoding='utf-8') as fh:
        fh.write('# 參考機清單有、但我們的 system.img 沒有的檔案\n')
        fh.write('# 多半是對方機種特有的硬體，或 ASUS 用了不同供應商\n')
        for src, refs in sorted(miss.items()):
            fh.write(f'{src}  <- {", ".join(sorted(set(refs)))}\n')

    # --- 3. ASUS 特有、參考樹沒提到的 ------------------------------------
    print()
    print('=== 掃描 ASUS / 本機特有 blob（參考樹未涵蓋）===')
    extra = []
    for base in ('vendor/lib', 'vendor/lib64', 'vendor/bin', 'vendor/firmware',
                 'vendor/etc', 'lib', 'lib64', 'bin'):
        root = os.path.join(MNT, base)
        for dirpath, _dirs, files in os.walk(root):
            for fn in files:
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, MNT)
                if rel in have or rel in miss:
                    continue
                low = fn.lower()
                if any(h in low for h in ASUS_HINTS):
                    try:
                        size = os.path.getsize(full)
                    except OSError:
                        size = -1
                    extra.append((rel, size))
    extra.sort()
    print(f'  找到 {len(extra)} 個')
    for rel, size in extra[:40]:
        print(f'    {size:>10,}  {rel}')
    if len(extra) > 40:
        print(f'    ... 另外 {len(extra) - 40} 個，見 asus_specific.txt')

    with open(f'{OUT}/asus_specific.txt', 'w', encoding='utf-8') as fh:
        fh.write('# 檔名含 ASUS/本機硬體關鍵字，且沒有任何參考樹提到的檔案\n')
        fh.write(f'# 關鍵字：{", ".join(ASUS_HINTS)}\n')
        for rel, size in extra:
            fh.write(f'{rel}\n')

    # --- 4. 草稿 ---------------------------------------------------------
    draft = f'{OUT}/proprietary-files-draft.txt'
    with open(draft, 'w', encoding='utf-8') as fh:
        fh.write('# Z01G (ZS551KL) proprietary blobs —— 自動產生的草稿，尚未人工審核\n')
        fh.write('# 來源：參考機清單 ∩ 本機 system.img，加上 ASUS 特有項目\n')
        fh.write('#\n# 產生方式：tools/11_match_blobs.py\n\n')
        fh.write('# --- 參考機清單中本機也有的 ---\n')
        for src in sorted(have):
            fh.write(f'{src}\n')
        fh.write('\n# --- ASUS / 本機特有（需人工確認）---\n')
        for rel, _size in extra:
            fh.write(f'{rel}\n')
    total = len(have) + len(extra)
    print()
    print(f'=== 輸出到 {OUT} ===')
    for fn in sorted(os.listdir(OUT)):
        print(f'  {fn}')
    print(f'\n草稿共 {total} 條（{len(have)} 參考命中 + {len(extra)} ASUS 特有）')
    print('※ 這是草稿，還需要人工審核：參考機有而我們也有的檔案，不代表 LineageOS 一定需要它。')


if __name__ == '__main__':
    main()
