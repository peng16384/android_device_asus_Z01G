#!/usr/bin/env python3
"""
從原廠映像產生 device/asus/Z01G/keylayout/ 的 .kl，並濾掉 AOSP 不認得的 keycode 標籤。

為什麼需要：
    導航鍵在第一次成功開機後的實測：返回正常，Home 與多工沒反應。
    原因是 /system/usr/keylayout/{focal-touchscreen,goodixfp,gpio-keys}.kl
    整組沒被收進來 —— 它們在 system 側，而 31_build_blob_list.py 對 system 側
    只沿用早期人工挑過的清單（跟 SmartcardService 少 jar 是同一類漏法）。

    沒有專屬 .kl 時 Android 退回 Generic.kl：
      返回  focal-touchscreen key 158 -> Generic 有 BACK          => 正常
      多工  focal-touchscreen key 139 -> Generic 映射成 MENU      => 沒反應
      Home  goodixfp key 187~193（KEY_F17~）-> Generic 沒有       => 沒反應
            （這台的指紋辨識器就是 Home 鍵）

為什麼不能直接抄原廠的：
    原廠 .kl 用了 ASUS 自己加在 framework 裡的 keycode 標籤
    （GESTURE_DOUBLE_CLICK / GESTURE_W / FINGERPRINT_EARLYWAKEUP ...）。
    KeyLayoutMap.cpp 的 parseKey() 遇到不認得的標籤是直接
        ALOGE("Expected key code label, got '%s'"); return BAD_VALUE;
    —— **整個檔案作廢**，又退回 Generic.kl。所以要先濾掉。

    被濾掉的手勢鍵之後要支援的話，正規做法是寫一個 device key handler
    （lineage 的 KeyHandler），在那裡接原始 scancode，而不是塞進 .kl。
"""
import os
import re

DEVICE_PATH = os.environ.get(
    'DEVICE_PATH',
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SRC = '/mnt/zs_system/usr/keylayout'
DST = os.path.join(DEVICE_PATH, 'keylayout')
LABELS = os.path.expanduser('~/lineage-16.0/frameworks/native/include/input/InputEventLabels.h')

known = set(re.findall(r'DEFINE_KEYCODE\((\w+)\)', open(LABELS, encoding='utf-8').read()))
print(f'AOSP 認得 {len(known)} 個 keycode 標籤')

os.makedirs(DST, exist_ok=True)
# 濾掉不認得的標籤之後，有些鍵會變成「完全沒有映射」——那不一定沒關係。
# 實測：goodixfp 的 key 192（KEY_F22）原廠是 FINGERPRINT_EARLYWAKEUP，
# 被濾掉之後 Home 鍵就徹底沒反應了，因為驅動每次只送這一個鍵
#（真正的 KEY_HOME 要 gxFpDaemon 走 device_send_key 送，而它在沒有
#  註冊指紋時停在 GF_SLEEP_MODE）。
# 所以產生之後**一定要用 getevent 實測一次**，看實際送出的 scancode
# 是不是都有落在保留下來的行裡。被濾掉的行會列在產生檔的檔頭註解。
#
# 這類需要人工判斷的改動，直接改 device tree 裡產生好的檔案即可 ——
# 重跑這支會覆蓋掉，所以改完別再無腦重跑。
OVERRIDDEN = {
    # 檔名: 已經人工調整過，重跑前先確認不會蓋掉調整
    'goodixfp.kl': 'key 192 已手動改成 HOME（見該檔註解）',
}

for name in ['focal-touchscreen', 'goodixfp', 'gpio-keys']:
    src = os.path.join(SRC, name + '.kl')
    kept, dropped = [], []
    for line in open(src, encoding='utf-8', errors='replace'):
        m = re.match(r'\s*key\s+(\d+)\s+(\w+)', line)
        if m and m.group(2) not in known:
            dropped.append((m.group(1), m.group(2)))
            continue
        kept.append(line.rstrip('\n'))

    hdr = [
        f'# {name}.kl —— 來源是原廠 /system/usr/keylayout/{name}.kl，',
        '# 由 tools/58_gen_keylayout.py 濾掉 AOSP 不認得的 keycode 標籤後產生。',
        '#',
        '# KeyLayoutMap.cpp 的 parseKey() 遇到不認得的標籤會 return BAD_VALUE，',
        '# **整個檔案作廢**並退回 Generic.kl —— 所以不能直接抄原廠的。',
    ]
    if dropped:
        hdr.append('#')
        hdr.append('# 這個檔案被濾掉的行（ASUS 自己加在 framework 裡的 keycode）：')
        for sc, lb in dropped:
            hdr.append(f'#   key {sc:<5} {lb}')
        hdr.append('# 要支援這些手勢的話，正規做法是寫 device key handler 接原始 scancode。')
    hdr.append('')

    out = os.path.join(DST, name + '.kl')
    if name + '.kl' in OVERRIDDEN and os.path.exists(out):
        print(f'  {name}.kl: 跳過 —— {OVERRIDDEN[name + ".kl"]}')
        continue
    with open(out, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('\n'.join(hdr + kept) + '\n')
    print(f'  {name}.kl: 保留 {len([l for l in kept if l.strip().startswith("key")])} 條，'
          f'濾掉 {len(dropped)} 條 {[d[1] for d in dropped]}')
