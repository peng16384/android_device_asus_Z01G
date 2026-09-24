#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把原廠 vendor/etc/audio_policy_configuration.xml 的 attachedDevices 補齊。

  python3 tools/104_patch_audio_policy.py

## 為什麼需要這支

VoLTE 通話接通之後**擴音關不掉**。Telecom 的紀錄是一開機就
    AUDIO_ROUTE (Leaving state QuiescentSpeakerRoute)
    AUDIO_ROUTE (Entering state ActiveSpeakerRoute)
也就是它從頭到尾都認為「這台沒有聽筒」。

CallAudioRouteStateMachine 判斷聽筒存不存在的方式是
    mAudioManager.getDevices(GET_DEVICES_OUTPUTS) 裡有沒有 TYPE_BUILTIN_EARPIECE
而那份清單來自 AudioPolicy 的「已連接裝置」，也就是設定檔的 <attachedDevices>。

我們用的那份（/vendor/etc/audio_policy_configuration.xml，203 行）只有：
    Speaker / Built-In Mic / Built-In Back Mic
—— 與 AOSP 的**通用範本一字不差**。Earpiece 與 Telephony Rx/Tx 在
<devicePorts> 裡都有宣告、primary output 的 route 也指得到，就是沒被列為已連接。

原因：ASUS 真正使用的是 /vendor/etc/audio/ 那份 413 行的（split-A2DP 版），
它的 attachedDevices 是
    Earpiece / Speaker / Telephony Tx / Built-In Mic / Built-In Back Mic
    / FM Tuner / Telephony Rx
而 /vendor/etc/ 這份只是 ASUS 留在樹裡、**從來沒被讀到過**的 AOSP 樣板
（Android 9 找設定檔的順序是 /odm/etc -> /vendor/etc/audio -> /vendor/etc，
  前面那個優先）。

我們為了修藍牙把 /vendor/etc/audio/ 那份排除掉（見 tools/31 的 EXCLUDE_EXACT），
於是退到這份樣板 —— 媒體、耳機、藍牙都正常，因為那些路徑樣板都有；
只有聽筒與電話路由沒有被「接上」。

所以照 ASUS 那份補齊（FM Tuner 這台沒有，略過）。
"""
import io
import os
import re
import sys

SRC = "/mnt/zs_system/vendor/etc/audio_policy_configuration.xml"
DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "configs/audio/"
                   "audio_policy_configuration.xml")

# 要補的（照 ASUS 實際使用的那份；Speaker 與兩個 mic 本來就有）
ADD = ["Earpiece", "Telephony Tx", "Telephony Rx"]

# ---- 第二件事：BT SCO 沒有任何輸出 route ------------------------------------
# 症狀：連著藍牙耳機講電話，聲音還是從手機出來。
#
# 這份樣板（以及 AOSP 的原版）**宣告了** BT SCO 的三個 devicePort，
# 但 <routes> 裡沒有任何 sink 指向它們 —— 只有把 "BT SCO Headset Mic"
# 當成 source 的輸入方向。也就是 primary output 根本路由不過去。
#
# ASUS 實際使用的那份是用一個合併的 sink：
#     <devicePort tagName="BT SCO All" type="AUDIO_DEVICE_OUT_ALL_SCO" .../>
#     <route type="mix" sink="BT SCO All" sources="primary output,raw,deep_buffer,
#            direct_pcm,compressed_offload,voip_rx,mmap_no_irq_out"/>
# 那幾個 mixPort 我們這份沒有全部，所以只列存在的三個。
SCO_PORT_AFTER = 'tagName="BT SCO Car Kit"'
SCO_PORT = """                <devicePort tagName="BT SCO All" type="AUDIO_DEVICE_OUT_ALL_SCO" role="sink">
                    <profile name="" format="AUDIO_FORMAT_PCM_16_BIT"
                             samplingRates="8000,16000" channelMasks="AUDIO_CHANNEL_OUT_MONO"/>
                </devicePort>
"""
SCO_ROUTE = """                <route type="mix" sink="BT SCO All"
                       sources="primary output,deep_buffer,compressed_offload"/>
"""
SCO_ROUTE_MIXPORTS = ["primary output", "deep_buffer", "compressed_offload"]


def main():
    if not os.path.exists(SRC):
        sys.exit("!!! 找不到 %s —— 先跑 sudo bash tools/07_mount_system.sh" % SRC)
    s = io.open(SRC, encoding="utf-8").read()

    m = re.search(r"([ \t]*)<attachedDevices>(.*?)</attachedDevices>", s, re.S)
    if not m:
        sys.exit("!!! 找不到 <attachedDevices>")
    if s.count("<attachedDevices>") != 1:
        sys.exit("!!! <attachedDevices> 出現 %d 次，不確定該改哪一個"
                 % s.count("<attachedDevices>"))

    indent, inner = m.group(1), m.group(2)
    have = re.findall(r"<item>([^<]+)</item>", inner)
    print("原本已連接的：%s" % ", ".join(have))

    missing = [d for d in ADD if d not in have]
    if not missing:
        sys.exit("!!! 這三個本來就都在了，與預期不符")
    print("要補的：      %s" % ", ".join(missing))

    # 每一個都要先在 devicePorts 裡宣告過，否則 AudioPolicy 會解析失敗
    for d in missing:
        if ('tagName="%s"' % d) not in s:
            sys.exit("!!! %s 沒有對應的 devicePort 宣告，不能列為已連接" % d)

    item_indent = indent + "    "
    new_inner = inner.rstrip() + "\n"
    for d in missing:
        new_inner += "%s<item>%s</item>\n" % (item_indent, d)
    new_inner += indent
    out = s[:m.start()] + "%s<attachedDevices>%s</attachedDevices>" % (indent, new_inner) + s[m.end():]

    # 驗證：只多了那幾行，其餘逐行相同
    added = [l for l in out.split("\n") if l not in s.split("\n")]
    if len(added) != len(missing):
        sys.exit("!!! 多出來的行數不對（%d，應為 %d）" % (len(added), len(missing)))
    import xml.etree.ElementTree as ET
    try:
        ET.fromstring(out)
    except Exception as e:
        sys.exit("!!! 改完不是合法的 XML：%s" % e)

    # ---- BT SCO 的輸出 route ----
    if 'sink="BT SCO' in out:
        sys.exit("!!! 已經有 BT SCO 的輸出 route 了，與預期不符")
    if 'tagName="BT SCO All"' in out:
        sys.exit("!!! 已經有 BT SCO All 的 devicePort 了")
    for mp in SCO_ROUTE_MIXPORTS:
        if ('mixPort name="%s"' % mp) not in out:
            sys.exit("!!! route 要引用的 mixPort %s 不存在" % mp)

    # devicePort：插在 BT SCO Car Kit 那一段之後
    m2 = re.search(r"[ \t]*<devicePort %s.*?</devicePort>\n"
                   % re.escape(SCO_PORT_AFTER), out, re.S)
    if not m2:
        sys.exit("!!! 找不到 BT SCO Car Kit 的 devicePort")
    out = out[:m2.end()] + SCO_PORT + out[m2.end():]

    # route：插在 </routes> 之前
    m3 = re.search(r"[ \t]*</routes>", out)
    if not m3:
        sys.exit("!!! 找不到 </routes>")
    out = out[:m3.start()] + SCO_ROUTE + out[m3.start():]
    print("補上 BT SCO All 的 devicePort 與一條輸出 route")

    try:
        ET.fromstring(out)
    except Exception as e:
        sys.exit("!!! 加完 BT SCO 之後不是合法的 XML：%s" % e)

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    io.open(DST, "w", encoding="utf-8", newline="\n").write(out)
    print("寫出：%s（%d -> %d 行）"
          % (os.path.normpath(DST), len(s.split("\n")), len(out.split("\n"))))


if __name__ == "__main__":
    main()
