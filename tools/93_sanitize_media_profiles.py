#!/usr/bin/env python3
"""從原廠 media_profiles_vendor.xml 剔除 AOSP 9 的 MediaProfiles 不接受的內容。

############ 為什麼需要 ############
原廠 build.prop 有 media.settings.xml=/vendor/etc/media_profiles_vendor.xml，
那份 42 KB 的檔案含有這顆相機正確的錄影解析度與位元率。但直接指過去會讓
**整個系統開不了機**：

    F MediaProfiles: frameworks/av/media/libmedia/MediaProfiles.cpp:329
                     CHECK(quality != -1) failed.
    F libc    : Fatal signal 6 (SIGABRT), code -6 (SI_TKILL) in tid (main)
    init: Service 'zygote' (pid ...) received signal 6

MediaProfiles 的解析跑在 **zygote 的 preload 階段**，而且遇到不認識的名稱
是直接 abort（CHECK 不是警告），zygote 一死就什麼都起不來。
症狀很有迷惑性：OOM 0、白名單錯誤 0、system_server 重啟 0、dex2oat 0，
CPU 779% idle，logcat 裡連一行 SystemServer: 都沒有。

⚠ 這跟 audio_policy_volumes.xml 的 DEVICE_CATEGORY_HEADSET_nonEU 是
  **完全一樣的模式**：ASUS 擴充了列舉值，AOSP 的解析器不認識。
###################################

############ 第一版的教訓：只驗一個維度不夠 ############
第一版只檢查 EncoderProfile 的 quality（剔掉 vga/2k/4kdci/qhd 與 timelapse
版共 26 個區塊），刷進去之後還是開不了機，只是換了一個 CHECK：

    MediaProfiles.cpp:289 CHECK(codec != -1) failed.   <- createAudioEncoderCap

真兇是 <AudioEncoderCap name="lpcm">，而 AOSP 9 的 sAudioEncoderNameMap
只有 amrnb/amrwb/aac/heaac/aaceld。

MediaProfiles.cpp 裡有 9 個 CHECK(... != -1)，分別對應不同的名稱對應表。
這一版把**全部**都驗過，不再只看 quality。
#######################################################

用法（在 WSL 內，先 tools/07_mount_system.sh 掛好映像）：
    python3 tools/93_sanitize_media_profiles.py
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

DEVICE_PATH = os.environ.get(
    'DEVICE_PATH',
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

MNT = '/mnt/zs_system'
SRC = os.path.join(MNT, 'vendor/etc/media_profiles_vendor.xml')
DST = os.path.join(DEVICE_PATH, 'configs/media/media_profiles_vendor.xml')

# 以下全部抄自 frameworks/av/media/libmedia/MediaProfiles.cpp 的名稱對應表。
# 換 LineageOS 版本時要重新確認（sed -n '/sXxxNameMap\[\] *=/,/};/p'）。
VIDEO_ENC = {'h263', 'h264', 'm4v', 'hevc'}
AUDIO_ENC = {'amrnb', 'amrwb', 'aac', 'heaac', 'aaceld'}
VIDEO_DEC = {'wmv'}
AUDIO_DEC = {'wma'}
FILE_FMT = {'3gp', 'mp4'}
QUALITY = {
    'low', 'high', 'qcif', 'cif', '480p', '720p', '1080p', '2160p', 'qvga',
    'timelapselow', 'timelapsehigh', 'timelapseqcif', 'timelapsecif',
    'timelapse480p', 'timelapse720p', 'timelapse1080p', 'timelapse2160p',
    'timelapseqvga',
    'highspeedlow', 'highspeedhigh', 'highspeed480p', 'highspeed720p',
    'highspeed1080p', 'highspeed2160p',
}

# 元素 -> (屬性名, 允許值)。對應 MediaProfiles.cpp 的各個 CHECK(... != -1)。
RULES = {
    'VideoEncoderCap':       ('name', VIDEO_ENC),
    'AudioEncoderCap':       ('name', AUDIO_ENC),
    'VideoDecoderCap':       ('name', VIDEO_DEC),
    'AudioDecoderCap':       ('name', AUDIO_DEC),
    'ExportVideoProfile':    ('name', VIDEO_ENC),
    'EncoderOutputFileFormat': ('name', FILE_FMT),
}
# EncoderProfile 要整塊拿掉的條件：quality 或 fileFormat 不合法，
# 或其子元素 <Video codec>/<Audio codec> 不合法。

HEADER = """<!--
    media_profiles_vendor.xml —— 從原廠 /vendor/etc/media_profiles_vendor.xml
    剔除 AOSP 9 的 MediaProfiles 不接受的內容之後的版本。
    詳見 tools/93_sanitize_media_profiles.py 的說明。
    直接用原廠那份會讓 zygote 在 preload 階段 SIGABRT，整個系統起不來。
-->
"""


def find_offenders(data):
    """回傳 (要整塊刪的 EncoderProfile quality 集合, 要刪的單一元素 (tag, name) 集合)"""
    root = ET.fromstring(data)
    bad_profiles, bad_elems = set(), set()

    for tag, (attr, allowed) in RULES.items():
        for e in root.iter(tag):
            v = e.get(attr)
            if v is not None and v not in allowed:
                bad_elems.add((tag, v))

    for ep in root.iter('EncoderProfile'):
        q, ff = ep.get('quality'), ep.get('fileFormat')
        why = []
        if q is not None and q not in QUALITY:
            why.append(f'quality={q}')
        if ff is not None and ff not in FILE_FMT:
            why.append(f'fileFormat={ff}')
        for child, allowed in (('Video', VIDEO_ENC), ('Audio', AUDIO_ENC)):
            for c in ep.iter(child):
                cv = c.get('codec')
                if cv is not None and cv not in allowed:
                    why.append(f'{child}.codec={cv}')
        if why:
            bad_profiles.add((q, tuple(sorted(set(why)))))
    return bad_profiles, bad_elems


def main():
    if not os.path.isfile(SRC):
        sys.exit(f'!!! 找不到 {SRC}（先跑 tools/07_mount_system.sh）')
    data = open(SRC, encoding='utf-8').read()

    bad_profiles, bad_elems = find_offenders(data)
    print(f'=== AOSP 9 不接受的內容 ===')
    for q, why in sorted(bad_profiles):
        print(f'  EncoderProfile quality={q:<16} {", ".join(why)}')
    for tag, v in sorted(bad_elems):
        print(f'  <{tag} name="{v}">')
    if not bad_profiles and not bad_elems:
        print('  沒有需要剔除的')

    out = data
    n_prof = n_elem = 0

    # 整塊移除有問題的 EncoderProfile（用 quality 當索引，逐塊比對子元素）
    def drop_profile(m):
        nonlocal n_prof
        blk = m.group(0)
        q = re.search(r'quality="([^"]+)"', blk)
        ff = re.search(r'fileFormat="([^"]+)"', blk)
        bad = (q and q.group(1) not in QUALITY) or (ff and ff.group(1) not in FILE_FMT)
        if not bad:
            for child, allowed in (('Video', VIDEO_ENC), ('Audio', AUDIO_ENC)):
                for cv in re.findall(r'<' + child + r'\b[^>]*codec="([^"]+)"', blk):
                    if cv not in allowed:
                        bad = True
        if bad:
            n_prof += 1
            return ''
        return blk

    out = re.sub(r'[ \t]*<EncoderProfile\b.*?</EncoderProfile>\s*\n',
                 drop_profile, out, flags=re.S)

    # 移除單一元素（自閉合或有內容）
    for tag, v in bad_elems:
        for pat in (r'[ \t]*<' + tag + r'\b[^>]*?name="' + re.escape(v) + r'"[^>]*?/>\s*\n',
                    r'[ \t]*<' + tag + r'\b[^>]*?name="' + re.escape(v) + r'"[^>]*?>.*?</' + tag + r'>\s*\n'):
            out, n = re.subn(pat, '', out, flags=re.S)
            n_elem += n
    print(f'移除 EncoderProfile {n_prof} 個 / 單一元素 {n_elem} 個')

    # --- 驗證，任一項不過就不寫檔 ---
    m = re.match(r'^\s*<\?xml[^>]*\?>\s*\n', out)
    out = (out[:m.end()] + HEADER + out[m.end():]) if m else HEADER + out

    try:
        root = ET.fromstring(out)
    except ET.ParseError as e:
        sys.exit(f'!!! 剔除後 XML 不合法：{e}')

    still_p, still_e = find_offenders(out)
    if still_p or still_e:
        sys.exit(f'!!! 還有殘留：profiles={still_p} elems={still_e}')

    ok = True
    for cp in root.iter('CamcorderProfiles'):
        cam = cp.get('cameraId')
        qs = {e.get('quality') for e in cp.iter('EncoderProfile')}
        missing = {'low', 'high'} - qs
        print(f'  cameraId={cam}  剩 {len(qs)} 種 quality  '
              f'{"!!! 缺 " + ",".join(sorted(missing)) if missing else "OK"}')
        if missing:
            ok = False
    if not ok:
        sys.exit('!!! 必要的 low/high 被移除了，中止')

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    with open(DST, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(out)
    print(f'{len(data)} -> {len(out)} bytes')
    print(f'輸出：{DST}')


if __name__ == '__main__':
    main()
