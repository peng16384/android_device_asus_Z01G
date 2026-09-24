#!/usr/bin/env python3
"""
把 device.mk 裡「與 blob 重複」的 AOSP 模組移除。

為什麼需要：
    blob 清單改成 vendor/ 全收之後，原廠的 HAL service / impl / 音效外掛
    都會被安裝。device.mk 若再從 AOSP 建一份同名的，會造成同一個輸出路徑
    有兩條規則：
        warning: overriding commands for target .../vendor/bin/hw/xxx-service
    實測有 204 個。而且對非 Treble 的舊機移植，原廠的 vendor HAL 才是跟
    這台硬體對得上的那份。

兩個實作上的教訓（都踩過）：
  1. 不要用 python 的文字模式寫檔 —— Windows 上會把 \\n 變成 \\r\\n，
     Makefile 變 CRLF 後，續行的 CR 會變成模組名稱的一部分，
     每個模組名後面多一個 \\r，比對不到任何真實模組而被靜默丟棄。
     一律 open(..., newline="\\n")。
  2. 不要把含 backslash 的正規表達式透過 shell heredoc 傳進 python ——
     backslash 會被吃掉。改成寫成檔案執行，並用逐行處理避開 backslash。
"""
import os
import sys

DEVICE_PATH = os.environ.get(
    'DEVICE_PATH',
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

MK = os.path.join(DEVICE_PATH, 'device.mk')
if os.name == 'nt' or not os.path.exists(MK):
    MK = os.path.join(DEVICE_PATH, 'device.mk')

DROP = {
    # Audio —— 原廠有 vendor/lib*/hw/audio.primary.msm8998.so 等
    'android.hardware.audio@2.0-impl', 'android.hardware.audio.effect@2.0-impl',
    'android.hardware.soundtrigger@2.0-impl', 'audio.a2dp.default',
    'audio.primary.msm8998', 'audio.r_submix.default', 'audio.usb.default',
    'libaudio-resampler', 'libqcompostprocbundle', 'libqcomvisualizer',
    'libqcomvoiceprocessing', 'libvolumelistener',
    # Bluetooth
    'android.hardware.bluetooth@1.0-impl', 'android.hardware.bluetooth@1.0-service',
    'libbt-vendor',
    # Camera
    'android.hardware.camera.provider@2.4-impl',
    'android.hardware.camera.provider@2.4-service',
    # Display
    'android.hardware.graphics.allocator@2.0-impl',
    'android.hardware.graphics.allocator@2.0-service',
    'android.hardware.graphics.composer@2.1-impl',
    'android.hardware.graphics.composer@2.1-service',
    'android.hardware.graphics.mapper@2.0-impl',
    'android.hardware.memtrack@1.0-impl', 'android.hardware.memtrack@1.0-service',
    # DRM / TEE
    'android.hardware.drm@1.0-impl', 'android.hardware.drm@1.0-service',
    'android.hardware.gatekeeper@1.0-impl', 'android.hardware.gatekeeper@1.0-service',
    'android.hardware.keymaster@3.0-impl', 'android.hardware.keymaster@3.0-service',
    # GPS
    'android.hardware.gnss@1.0-impl-qti', 'android.hardware.gnss@1.0-service-qti',
    # 其他 HAL
    'android.hardware.health@1.0-impl', 'android.hardware.health@1.0-service',
    'android.hardware.light@2.0-impl', 'android.hardware.light@2.0-service',
    'android.hardware.power@1.0-impl', 'android.hardware.power@1.0-service',
    'android.hardware.thermal@1.0-impl', 'android.hardware.thermal@1.0-service',
    'android.hardware.usb@1.0-impl', 'android.hardware.usb@1.0-service',
    'android.hardware.vibrator@1.0-impl', 'android.hardware.vibrator@1.0-service',
    'android.hardware.media.omx@1.0-service', 'libstagefrighthw',
    'android.hardware.sensors@1.0-impl', 'android.hardware.sensors@1.0-service',
    # Wifi
    'android.hardware.wifi@1.0-service', 'hostapd', 'wpa_supplicant',
}

CONT = '\\'


def main():
    with open(MK, encoding='utf-8', newline='') as fh:
        text = fh.read()
    text = text.replace('\r\n', '\n')          # 統一成 LF
    lines = text.split('\n')

    out, removed = [], []
    for line in lines:
        body = line.strip()
        if body.endswith(CONT):
            body = body[:-1].strip()
        if body in DROP:
            removed.append(body)
            continue
        out.append(line)

    # 修懸空續行：若某行以 \ 結尾，但下一行是空行或註解 -> 去掉那個 \
    for i in range(len(out) - 1):
        cur = out[i].rstrip()
        nxt = out[i + 1].strip()
        if cur.endswith(CONT) and (nxt == '' or nxt.startswith('#')):
            out[i] = cur[:-1].rstrip()

    # 清掉變成空的 PRODUCT_PACKAGES 區塊
    cleaned = []
    for i, line in enumerate(out):
        if line.strip() in ('PRODUCT_PACKAGES +=', 'PRODUCT_PACKAGES += \\'):
            nxt = out[i + 1].strip() if i + 1 < len(out) else ''
            if nxt == '' or nxt.startswith('#'):
                continue
        cleaned.append(line)

    with open(MK, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('\n'.join(cleaned))

    raw = open(MK, 'rb').read()
    print(f'移除 {len(removed)} 個與 blob 重複的 AOSP 模組')
    for m in sorted(set(removed)):
        print(f'    {m}')
    print()
    print(f'行尾：CRLF {raw.count(bytes([13,10]))} / 純 LF '
          f'{raw.count(bytes([10])) - raw.count(bytes([13,10]))}')
    missing = DROP - set(removed)
    if missing:
        print(f'沒找到（可能本來就不在）：{len(missing)} 個')
        for m in sorted(missing):
            print(f'    {m}')


if __name__ == '__main__':
    main()
