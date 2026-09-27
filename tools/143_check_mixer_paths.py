#!/usr/bin/env python3
"""檢查裝進去的 mixer_paths_tasha.xml = ASUS 原檔 + extract-files.py 的修改，一處不多、一處不少。

    python3 143_check_mixer_paths.py <成品的 mixer_paths_tasha.xml> <ASUS 的 system/etc/mixer_paths_ZS551KL.xml>

做法：把成品裡我們加的修改「反向還原」，結果必須與 ASUS 原檔逐 byte 相同；每一處修改都必須剛好套上一次。
  1. 最上層預設值：Stereo Program 0 後面的「Stereo Configuration 21」「Stereo LDAC Playback Volume 15」
  2. 擴音 / VoIP 通話路徑：「Stereo Configuration 24/25 + DSPChl MonoMix」原本是「DSPChl Mute」
"""
import re
import sys

CALL_PATHS = (('voicemmode1-call speaker', 24), ('voicemmode2-call speaker', 24),
              ('compress-voip-call speaker', 24), ('compress-voip-call handset-for-voip', 25))


def main():
    built = open(sys.argv[1], encoding='utf-8', newline='').read()
    asus = open(sys.argv[2], encoding='utf-8', newline='').read()
    s, errs = built, []

    top = re.compile(r'(<ctl name="Stereo Program" value="0" />\r?\n)'
                     r'    <ctl name="Stereo Configuration" value="21" />\r?\n'
                     r'    <ctl name="Stereo LDAC Playback Volume" value="15" />\r?\n')
    s, n = top.subn(r'\1', s)
    if n != 1:
        errs.append('最上層預設值的兩行：%d 處（應為 1）' % n)

    for path, conf in CALL_PATHS:
        pat = re.compile(r'(<path name="%s">\r?\n)(\s*)<ctl name="Stereo Configuration" value="%d" />(\r?\n)'
                         r'\s*<ctl name="Stereo DSPChl Setup" value="DevA-MonoMix-DevB-MonoMix" />\r?\n'
                         % (re.escape(path), conf))
        s, n = pat.subn(r'\1\2<ctl name="Stereo DSPChl Setup" value="DevA-Mute-DevB-Mute" />\3', s)
        if n != 1:
            errs.append('%s 的組態 %d + MonoMix：%d 處（應為 1）' % (path, conf, n))

    if s != asus:
        errs.append('還原修改後與 ASUS 原檔不同（有預期外的差異）')
    for e in errs:
        print('  ' + e)
    sys.exit(1 if errs else 0)


if __name__ == '__main__':
    main()
