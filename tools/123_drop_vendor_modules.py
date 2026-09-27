#!/usr/bin/env python3
"""
從 TheMuppets 產生的 vendor tree 剔除指定的模組（Android.bp 的整個區塊 + makefile 的 PRODUCT_PACKAGES 行）。

  python3 tools/123_drop_vendor_modules.py <vendor 目錄> <模組名>...

只給 tools/123 的**暫時轉接**用：借 OnePlus 的 vendor tree 做 build graph 煙霧測試時，
它的 OnePlus 專屬模組依賴 hardware/oneplus 的介面（我們沒有、也不要）。
正式的 vendor/asus/Z01G 由我們自己的 blob 清單產生，不需要這支。
"""
import os
import re
import sys

vdir, names = sys.argv[1], sys.argv[2:]
bp = os.path.join(vdir, 'Android.bp')
s = open(bp, encoding='utf-8').read()
for n in names:
    # 區塊：從行首的「xxx {」到對應的行首「}」，裡面有 name: "<n>",
    # 縮排是 4 個空白（TheMuppets 的 setup-makefiles 產生的格式）
    pat = re.compile(r'(?ms)^\w+ \{\n {4}name: "' + re.escape(n) + r'",\n.*?^\}\n\n?')
    m = pat.findall(s)
    if len(m) != 1:
        sys.exit('!!! Android.bp 裡 %s 命中 %d 次' % (n, len(m)))
    s = pat.sub('', s)
    print('  Android.bp 刪 %s' % n)
open(bp, 'w', encoding='utf-8', newline='').write(s)

for f in os.listdir(vdir):
    if not f.endswith('.mk'):
        continue
    p = os.path.join(vdir, f)
    lines = open(p, encoding='utf-8').read().split('\n')
    out, BS = [], chr(92)
    for l in lines:
        if l.strip().rstrip(BS).strip() in names:
            if not l.rstrip().endswith(BS) and out and out[-1].rstrip().endswith(BS):
                out[-1] = out[-1].rstrip()[:-1].rstrip()
            print('  %s 刪 %s' % (f, l.strip()))
            continue
        out.append(l)
    open(p, 'w', encoding='utf-8', newline='').write('\n'.join(out))
