#!/usr/bin/env python3
"""從原廠 audio_policy_volumes.xml 剔除 DEVICE_CATEGORY_HEADSET_nonEU 曲線。

ASUS 在 AOSP 的 deviceCategory 列舉之外自己加了第 5 種
DEVICE_CATEGORY_HEADSET_nonEU（搭配 use.audio.eu.parameters 這個屬性切換）。
他們的 framework 有對應修改，AOSP 9 的 AudioPolicy 解析器沒有：

    E APM::Serializer: deserialize: Invalid deviceCategory=DEVICE_CATEGORY_HEADSET_nonEU
    E APM::VolumeCurve: Invalid device category 1 for Volume Curve   (×N)

一條解析不了就讓「整組」音量曲線註冊失敗，結果是
    - STREAM_MUSIC: Muted: true, Current: 2 (speaker): 0
    - 音量鍵沒反應、設定裡的鈴聲/鬧鐘/通知滑桿拖不動

AOSP 合法的只有 SPEAKER / HEADSET / EARPIECE / EXT_MEDIA 四種。

用法（在 WSL 內，先 tools/07_mount_system.sh 掛好映像）：
    python3 tools/91_strip_noneu_volumes.py
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

DEVICE_PATH = os.environ.get(
    'DEVICE_PATH',
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

MNT = '/mnt/zs_system'
SRC = os.path.join(MNT, 'vendor/etc/audio_policy_volumes.xml')
DST = os.path.join(DEVICE_PATH, 'configs/audio/audio_policy_volumes.xml')

HEADER = """<!--
    audio_policy_volumes.xml —— 從原廠 /vendor/etc/audio_policy_volumes.xml
    剔除 13 條 DEVICE_CATEGORY_HEADSET_nonEU 曲線後的版本。
    詳見 tools/91_strip_noneu_volumes.py 的說明。
-->
"""


def main():
    if not os.path.isfile(SRC):
        sys.exit(f'!!! 找不到 {SRC}（先跑 tools/07_mount_system.sh）')

    data = open(SRC, encoding='utf-8').read()

    # <volume ... HEADSET_nonEU ...>…</volume> 與自閉合的 <volume …/>
    pat_self = re.compile(r'[ \t]*<volume\b[^>]*?HEADSET_nonEU[^>]*?/>\s*\n', re.S)
    pat_body = re.compile(r'[ \t]*<volume\b[^>]*?HEADSET_nonEU[^>]*?>.*?</volume>\s*\n', re.S)
    out, n_self = pat_self.subn('', data)
    out, n_body = pat_body.subn('', out)
    print(f'移除 自閉合 {n_self} 條 / 有內容 {n_body} 條，共 {n_self + n_body} 條')

    if 'nonEU' in out:
        sys.exit('!!! 還有 nonEU 殘留，正則沒涵蓋到，請檢查')

    m = re.match(r'^\s*<\?xml[^>]*\?>\s*\n', out)
    out = (out[:m.end()] + HEADER + out[m.end():]) if m else HEADER + out

    # 寫出前先確認 XML 仍然合法，免得把壞檔案塞進 build
    ET.fromstring(out)

    cats = {}
    for c in re.findall(r'deviceCategory="([^"]+)"', out):
        cats[c] = cats.get(c, 0) + 1
    for c in sorted(cats):
        print(f'  {c:<32} {cats[c]} 條')
    if set(cats) - {'DEVICE_CATEGORY_SPEAKER', 'DEVICE_CATEGORY_HEADSET',
                    'DEVICE_CATEGORY_EARPIECE', 'DEVICE_CATEGORY_EXT_MEDIA'}:
        sys.exit('!!! 仍有 AOSP 不認識的 deviceCategory')

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    with open(DST, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(out)
    print(f'{len(data)} -> {len(out)} bytes')
    print(f'輸出：{DST}')


if __name__ == '__main__':
    main()
