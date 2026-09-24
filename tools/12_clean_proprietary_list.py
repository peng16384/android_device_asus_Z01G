#!/usr/bin/env python3
"""
把自動產生的 blob 草稿清乾淨，輸出成 device tree 用的
proprietary-files.txt。

做四件事：
  1. 剔除 AOSP 自己會編出來的項目（上一步用檔名關鍵字抓 blob 時的誤判）
  2. 剔除本機用不到的相機 sensor —— ASUS 的 vendor 映像是多機種共用，
     塞了十幾顆 sensor，ZS551KL 實際只用 IMX362 / IMX351 / IMX319
  3. 給 .apk / .jar 加上 '-' 前綴
  4. 依用途分段排序，方便人工複審

關於 '-' 前綴（extract_utils.sh:765）：
    if [[ "$SPEC" =~ ^- ]]; then PRODUCT_PACKAGES_LIST+=(...)   # BUILD_PREBUILT 模組
    else                         PRODUCT_COPY_FILES_LIST+=(...) # 單純複製
'-' 的意思是「要產生 BUILD_PREBUILT 模組」。APK **必須**加，否則
build/make/core/Makefile:28 會擋下來：
    error: Prebuilt apk found in PRODUCT_COPY_FILES: ..., use BUILD_PREBUILT instead!
JAR 雖然不會被擋，但一併加比較正確（framework jar 需要正確的 module class）。

輸出：$DEVICE_PATH/proprietary-files.txt
"""
import os
import re
import sys

DEVICE_PATH = os.environ.get(
    'DEVICE_PATH',
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SRC = os.path.join(DEVICE_PATH, 'blobs/proprietary-files-draft.txt')
GAP = os.path.join(DEVICE_PATH, 'blobs/gap_report.txt')
DST = os.path.join(DEVICE_PATH, 'proprietary-files.txt')
MNT = '/mnt/zs_system'

# --- 1. AOSP / LineageOS 自己會編的，不是 blob ---------------------------
AOSP_BUILT = {
    # 用檔名關鍵字抓 blob 時的誤判（ASUS_HINTS 裡的 'fingerprint' 過度匹配）
    'lib/android.hardware.biometrics.fingerprint@2.1.so',
    'lib64/android.hardware.biometrics.fingerprint@2.1.so',
    'vendor/etc/permissions/android.hardware.fingerprint.xml',
    'vendor/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc',

    # 模組名稱與 LineageOS 原始碼衝突（tools/19_find_module_conflicts.sh 找出來的）
    # m nothing 會報：
    #   error: MODULE.TARGET.JAVA_LIBRARIES.qti-telephony-common
    #          already defined by hardware/lineage/telephony
    'framework/qti-telephony-common.jar',

    # 檔案路徑與 LineageOS 原始碼衝突。m nothing 會警告：
    #   warning: overriding commands for target .../<path>
    #   warning: ignoring old commands for target .../<path>
    # 意思是同一個輸出檔同時由 blob 與原始碼模組提供，blob 會蓋掉原始碼。
    # 這些都是 LineageOS 自己會編、而且 Pie 版本比 Oreo blob 新的元件，
    # 應該用原始碼版本。
    'lib64/libldacBT_abr.so',                 # external/libldac（AOSP 9 自帶）
    'lib64/libldacBT_enc.so',                 # 同上
    'lib64/libnqnfc-nci.so',                  # vendor/nxp/opensource 會編
    'vendor/etc/init/android.hardware.thermal@1.0-service.rc',  # AOSP 的 thermal service 自帶
    'vendor/lib/libwifi-hal-qcom.so',         # hardware/qcom/wlan 會編
    'vendor/lib64/libwifi-hal-qcom.so',       # 同上
    'vendor/lib64/libwifi-hal.so',            # frameworks/opt/net/wifi 會編
}

# 以下兩個也會衝突，但處理方式相反 —— 保留 blob、改從 device.mk 拿掉：
#   vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-service
#       ASUS 版直接載入 gx5206/gx5216，AOSP 版找的是 fingerprint.<hw>.so，
#       名字對不上。先用 ASUS 的，之後若指紋不動再換 AOSP 版試。
#   vendor/etc/wifi/wpa_supplicant.conf
#       原廠的設定檔比較貼近這台的硬體，留 blob。

# --- 2. 相機 sensor -----------------------------------------------------
# 本機實際使用的（來自 /proc/device-tree 與 ASUS 規格）
KEEP_SENSORS = {'imx362', 'imx351', 'imx319', 'csidtg'}
# vendor 映像裡出現過的所有 sensor token
ALL_SENSORS = {
    'imx214', 'imx230', 'imx258', 'imx298', 'imx318', 'imx319', 'imx351',
    'imx362', 'imx376', 'imx378', 'ov12a10', 'ov13850', 'ov13855', 'ov13880',
    'ov2281', 'ov4688', 'ov5670', 'ov7251', 'ov8856', 'csidtg',
}
DROP_SENSORS = ALL_SENSORS - KEEP_SENSORS

# --- 3. 分段 ------------------------------------------------------------
SECTIONS = [
    ('Audio',        [r'audio', r'acdb', r'adsp', r'tinycompress', r'sound', r'tfa', r'listen']),
    ('Bluetooth',    [r'\bbt', r'bluetooth', r'btnv', r'/bdt']),
    ('Camera',       [r'camera', r'chromatix', r'mmcamera', r'arcsoft', r'^lib/libjpeg',
                      r'imglib', r'mm-qcamera', r'depth', r'bokeh']),
    ('Display',      [r'display', r'gralloc', r'hwcomposer', r'qdcm', r'splendid',
                      r'memtrack', r'sdm', r'\bqd', r'adreno', r'\begl', r'vulkan',
                      r'libGLES', r'libRS', r'libOpenCL', r'libC2D', r'libgsl', r'libllvm-glnext']),
    ('DRM',          [r'drm', r'widevine', r'playready', r'qseecom', r'securemsm']),
    ('Fingerprint',  [r'fingerprint', r'goodix', r'gx52', r'gxfp']),
    ('GPS',          [r'gnss', r'gps', r'izat', r'loc_', r'liblocation', r'xtra', r'garden']),
    ('Laser focus',  [r'laser', r'xbspk']),
    ('Media',        [r'omx', r'stagefright', r'codec', r'mm-parser', r'mm-color', r'venc', r'vdec']),
    ('NFC',          [r'nfc', r'nq_', r'nqnfc', r'ese']),
    ('Perf',         [r'perf', r'qti-perfd', r'boost']),
    ('RIL / Telephony', [r'ril', r'radio', r'qcril', r'ims', r'telephony', r'dpm',
                         r'diag', r'rmnet', r'dsi_netctrl', r'qmi', r'cnd', r'netmgr']),
    ('Sensors',      [r'sensor', r'nanohub', r'ssc']),
    ('Thermal',      [r'thermal']),
    ('Wifi',         [r'wifi', r'wlan', r'wcnss', r'hostapd', r'wpa', r'cnss']),
    ('Keystore / TEE', [r'keymaster', r'gatekeeper', r'\btz', r'teec', r'tui', r'qtee']),
    ('IPA / Data',   [r'ipa', r'data-ipa']),
]


def section_of(path):
    low = path.lower()
    for name, pats in SECTIONS:
        for p in pats:
            if re.search(p, low):
                return name
    return 'Misc'


def sensor_drop(path):
    low = path.lower()
    for s in DROP_SENSORS:
        # 只在檔名帶 sensor 名稱時才丟，避免誤傷共用檔
        if re.search(r'(^|[/_])' + re.escape(s) + r'([._/]|$)', low):
            return s
    return None


def main():
    if not os.path.exists(SRC):
        sys.exit(f'!!! 找不到 {SRC}，先跑 tools/11_match_blobs.py')

    entries = []
    with open(SRC, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith('#'):
                entries.append(line)
    n_draft = len(entries)

    # tools/13_gap_check.sh 找出來的缺漏 —— 本機特有、但參考機清單沒有、
    # 檔名也不含 ASUS 關鍵字的檔案（相機 chromatix、mixer_paths/acdb、WLAN 等）
    n_gap = 0
    if os.path.exists(GAP):
        seen = set(entries)
        with open(GAP, encoding='utf-8') as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith('#') and line not in seen:
                    entries.append(line)
                    seen.add(line)
                    n_gap += 1
        print(f'併入 gap_report.txt：新增 {n_gap} 條')
    else:
        print(f'（沒有 {GAP}，跳過缺漏合併 —— 建議先跑 tools/13_gap_check.sh）')

    kept, dropped_aosp, dropped_sensor = [], [], []
    for e in entries:
        if e in AOSP_BUILT:
            dropped_aosp.append(e)
            continue
        s = sensor_drop(e)
        if s:
            dropped_sensor.append((e, s))
            continue
        kept.append(e)

    buckets = {}
    for e in kept:
        buckets.setdefault(section_of(e), []).append(e)

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    with open(DST, 'w', encoding='utf-8') as fh:
        fh.write('# Proprietary files for ASUS ZenFone 4 Pro (ZS551KL / Z01G)\n')
        fh.write('#\n')
        fh.write('# 來源：原廠 15.0410.1911.117 的 /system 分割 dd 映像\n')
        fh.write('# 產生：tools/11_match_blobs.py -> tools/12_clean_proprietary_list.py\n')
        fh.write('#\n')
        fh.write('# 這份清單尚未經過完整人工複審，也還沒編譯驗證過。\n')
        fh.write('# 「參考機有、我們也有」不等於 LineageOS 一定需要它。\n')
        fh.write('#\n')
        fh.write(f'# 草稿 {n_draft} 條 + 缺漏補回 {n_gap} 條。已剔除 {len(dropped_aosp)} 條 AOSP 自己會編的項目、'
                 f'{len(dropped_sensor)} 條本機用不到的相機 sensor。\n')
        fh.write(f'# 本機 sensor：{", ".join(sorted(KEEP_SENSORS))}\n')
        fh.write('\n')
        order = [n for n, _ in SECTIONS] + ['Misc']
        n_pkg = 0
        for name in order:
            items = buckets.get(name)
            if not items:
                continue
            fh.write(f'# {name} ({len(items)})\n')
            for e in sorted(items):
                # .apk / .jar 需要 BUILD_PREBUILT 模組 -> 加 '-' 前綴
                if e.endswith('.apk') or e.endswith('.jar'):
                    fh.write(f'-{e}\n')
                    n_pkg += 1
                else:
                    fh.write(f'{e}\n')
            fh.write('\n')

    # 報告
    print(f"草稿 {n_draft} 條 + 缺漏 {n_gap} 條 = {len(entries)} 條")
    print(f'  剔除 AOSP 誤判      {len(dropped_aosp)} 條')
    for e in dropped_aosp:
        print(f'      - {e}')
    print(f'  剔除用不到的 sensor {len(dropped_sensor)} 條')
    bys = {}
    for _e, s in dropped_sensor:
        bys[s] = bys.get(s, 0) + 1
    for s, n in sorted(bys.items(), key=lambda x: -x[1]):
        print(f'      - {s:<10} {n} 條')
    print(f'保留     {len(kept)} 條（其中 {n_pkg} 條 .apk/.jar 加了 - 前綴走 BUILD_PREBUILT）')
    print()
    print('分段統計：')
    for name in order:
        if name in buckets:
            print(f'  {name:<20} {len(buckets[name]):>4}')
    print()
    print(f'輸出：{DST}')


if __name__ == '__main__':
    main()
