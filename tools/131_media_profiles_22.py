#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
22.2：用 ASUS 原廠的 media_profiles_vendor.xml 產生 device tree 的 configs/media_profiles_V1_0.xml
（在 lineage22 distro 內執行）

  python3 tools/131_media_profiles_22.py

16.0 的 tools/93 要剔掉 26 個 EncoderProfile（vga / 2k / 4kdci / qhd）—— AOSP 9 的 MediaProfiles.cpp
遇到不認得的名稱是 CHECK -> abort（zygote 一死整個系統起不來）。
Android 15 的名稱表已經有這四種；對 ASUS 原廠那份逐項比，只剩 <AudioEncoderCap name="lpcm"> 不認得。
15 對它是 ALOGE + return nullptr（不再 abort），但照樣剔掉，不賭呼叫端處理 null。

驗證（任一不過就不寫檔）：
  - 名稱表直接從 frameworks/av/media/libmedia/MediaProfiles.cpp 讀（換 LineageOS 版本時自動跟上）
  - 剔除後沒有殘留不認得的名稱、XML 合法
  - 每個 cameraId 都還有 low 與 high（MediaProfiles 必要）
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

SRC = os.path.expanduser('~/asus/dump/vendor/etc/media_profiles_vendor.xml')
CPP = os.path.expanduser('~/lineage-22.2/frameworks/av/media/libmedia/MediaProfiles.cpp')
PROJ = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))   # device tree 的根目錄
OUT = PROJ + '/configs/media_profiles_V1_0.xml'


def name_map(src, var):
    body = re.search(var + r'\[\]\s*=\s*\{(.*?)\};', src, re.S).group(1)
    return set(re.findall(r'"([^"]+)"', body))


def problems(root, maps):
    ve, ae, vd, ad, ff, q = maps
    bad = []
    for e in root.iter():
        a = e.attrib
        checks = {
            'EncoderProfile': [('quality', q), ('fileFormat', ff)],
            'VideoEncoderCap': [('name', ve)], 'AudioEncoderCap': [('name', ae)],
            'VideoDecoderCap': [('name', vd)], 'AudioDecoderCap': [('name', ad)],
        }.get(e.tag, [])
        if e.tag == 'Video' and 'codec' in a:
            checks = [('codec', ve)]
        if e.tag == 'Audio' and 'codec' in a:
            checks = [('codec', ae)]
        bad += ['%s %s=%s' % (e.tag, k, a.get(k)) for k, allowed in checks if a.get(k) not in allowed]
    return bad


def main():
    cpp = open(CPP, encoding='utf-8').read()
    maps = [name_map(cpp, v) for v in ('sVideoEncoderNameMap', 'sAudioEncoderNameMap', 'sVideoDecoderNameMap',
                                       'sAudioDecoderNameMap', 'sFileFormatMap', 'sCamcorderQualityNameMap')]
    text = open(SRC, encoding='utf-8').read()

    # 文字層級剔除（保留原檔的註解與 DTD；ElementTree 重寫會丟掉它們）
    out, n = re.subn(r'[ \t]*<AudioEncoderCap\s+name="lpcm".*?/>[ \t]*\n', '', text, flags=re.S)
    if n != 1:
        sys.exit('!!! 預期剔除 1 個 lpcm AudioEncoderCap，實際 %d' % n)

    root = ET.fromstring(out.encode('utf-8'))
    bad = problems(root, maps)
    if bad:
        sys.exit('!!! 剔除後仍有 Android 15 不認得的：%s' % bad)
    per_cam = {}
    for p in root.iter('CamcorderProfiles'):
        per_cam[p.get('cameraId')] = {e.get('quality') for e in p.iter('EncoderProfile')}
    if not per_cam:   # 沒抓到任何一組就不是「全部通過」，是檢查本身沒在做事
        sys.exit('!!! 找不到任何 CamcorderProfiles —— 檢查沒有對象')
    lack = {c: sorted({'low', 'high'} - qs) for c, qs in per_cam.items() if not {'low', 'high'} <= qs}
    if lack:
        sys.exit('!!! 有 cameraId 缺 low/high：%s' % lack)

    hdr = ('<!-- 由 tools/131_media_profiles_22.py 從 ASUS 原廠 1911.117 的 media_profiles_vendor.xml 產生，'
           '不要手改。\n     只剔掉 Android 15 不認得的 <AudioEncoderCap name="lpcm">。 -->\n')
    out = re.sub(r'(<\?xml[^>]*\?>\s*\n)', lambda m: m.group(1) + hdr, out, count=1)
    with open(OUT, 'w', encoding='utf-8', newline='') as f:
        f.write(out)
    n_prof = sum(1 for _ in root.iter('EncoderProfile'))
    print('寫出 %s' % OUT)
    print('  EncoderProfile %d 個，cameraId %s；剔除 lpcm AudioEncoderCap 1 個' % (n_prof, sorted(per_cam)))


if __name__ == '__main__':
    main()
