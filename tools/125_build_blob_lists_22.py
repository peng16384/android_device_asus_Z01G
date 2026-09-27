#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
產生 22.2 的兩份 blob 清單（在 WSL 內執行）：

  python3 tools/125_build_blob_lists_22.py [--report 報告檔]

輸出（device tree 根目錄）：
  proprietary-files-oneplus.txt   從 TheMuppets 的 OnePlus msm8998-common 借的（SoC 共通）
  proprietary-files.txt           ASUS 原廠 1911.117（ASUS 專屬 + 必須配合 ASUS 韌體/TZ 的）

## 策略（docs/bringup.md「blob 清單」）

**以 OnePlus 5 的清單為底**：那是已知能在 Android 15 + msm8998 上跑的組合
（OOS 10 + Fairphone 3 的 RIL/IMS）。按區段決定：借 OnePlus / 改用 ASUS / 不要。

**ASUS 這一側是「整個 vendor 目錄 − 排除規則」**，不是白名單：
16.0 的教訓 —— 白名單一定會漏（ADSP 韌體、TAS2557 韌體、audbg 腳本…都是這樣漏的），
而漏掉的東西編譯期完全無聲。排除規則：
  1. OnePlus 已提供同檔名的 -> OnePlus 優先（同一個 QTI 堆疊不混新舊版本）
  2. 22.2 從原始碼編的 HAL 與 AOSP 的介面程式庫
  3. NFC / ANT+ / FM / eSE / OnePlus 沒有、我們也不要的
  4. vendor/etc/init 全部不收 —— 需要的服務在 device tree 的 init rc 明確寫
  5. ASUS 的 App（需要 ASUS framework）
**經 PIL 載入的韌體一律 ASUS**（TZ 驗 OEM 簽章，別家的 -60）。

每條規則排除了什麼都寫進報告，人工複核。
"""
import os
import re
import subprocess
import sys
from collections import OrderedDict, defaultdict

PROJ = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))   # device tree 的根目錄
OP_LIST = os.path.expanduser('~/ref/android_device_oneplus_msm8998-common/proprietary-files.txt')
INV = os.environ.get('INVENTORY', os.path.expanduser('~/asus/inventory'))   # lineage-16.0 分支的 tools/08 產生
INV_VENDOR = INV + '/vendor_files.txt'   # 大小 + 相對 /system/vendor
INV_SYSTEM = INV + '/system_files.txt'   # 大小 + 相對 /system
OUT = PROJ
DUMP = os.path.expanduser('~/asus/dump')   # tools/126；vendor/ 在最上層（不在 system/ 底下）

# ---------------------------------------------------------------- OnePlus 的區段決定
OP = 'oneplus'
ASUS = 'asus'
DROP = 'drop'
SECTIONS = {
    'ADSP / CDSP / MDSP / SDSP': OP,        # fastrpc 的 userspace；dirac 那兩個在 OP_DROP_FILES
    'ADSP modules': ASUS,                   # 載入 ADSP 內執行 -> 要配 ASUS 的 ADSP 韌體
    'Alipay': DROP,
    'ANT+': DROP,
    'Audio': ASUS,                          # ACDB 系列要配 ASUS 的校正檔格式
    'Bluetooth': OP,
    # CACertService：它的 JNI（ModemInterface.nInitializeAuthClient）沒有跟著進來 -> 每次啟動
    # UnsatisfiedLinkError、系統又一直拉起來，一次開機當 24,005 次（2026-09-25，卡頓的主因）。
    # 原廠 ASUS 沒有這個服務，用不到
    'CACert': DROP,
    'Camera': ASUS, 'Camera actuators': ASUS, 'Camera chromatix': ASUS, 'Camera etc': ASUS,
    'Camera firmware': ASUS, 'Camera hidl': DROP, 'Camera postprocessing': ASUS,
    'Camera sensors': ASUS, 'Camera Dummy Libs': DROP,
    'CNE': OP,
    'Dash': DROP,                           # OnePlus 快充
    'DPM': OP,
    # Widevine：OnePlus 的 libwvhidl 要 VNDK v29 的 libprotobuf-cpp-lite。Lineage 的 vendorcompat 裝成同名的
    # vendor/lib64/libprotobuf-cpp-lite.so，非 Treble 單一 namespace 會先找到 system 的 A15 版 -> 缺符號、
    # HAL 每秒崩潰（2026-09-25）。patches/hardware/lineage/compat/0001 另裝一份 libprotobuf-cpp-lite-v29.so，
    # extract-files.py 把 libwvhidl 的 NEEDED 改過去（2026-09-26）
    'DRM': OP, 'DRM (Widevine)': OP,
    'ESE Powermanager': DROP,
    'Fingerprint sensor': ASUS,             # Goodix gx5206（OnePlus 是別家）
    'Gatekeeper': ASUS, 'Keymaster': ASUS,  # 要配 ASUS 的 TZ app
    # GPS 用 ASUS 的（16.0 驗證過）。OnePlus 的定位堆疊（A10、gnss@2.0-service-qti）講的 QMI LOC 比這台
    # ASUS 2019 年的 modem 新：registerMasterClient / setBlacklistSv 回 INVALID_MESSAGE_ID，setGpsLock /
    # setSUPLVersion / setLPPConfig 回 INVALID_PARAMETER -> 引擎鎖定解不開、session 起不來、一顆衛星都沒有
    # （2026-09-26，GPSTest 實測）。ASUS 的 impl 由 AOSP 的 android.hardware.gnss@1.0-service 載入
    'GPS': ASUS,
    'Graphics': OP,                         # Adreno userspace（配新 kgsl）
    'Graphics firmware': ASUS,              # a540_zap 是 PIL；a530_pfp 另外換 linux-firmware
    'Graphics - HDR': OP, 'Graphics - SDM': OP,
    'IPA': ASUS,                            # ipa_fws 是 PIL
    'Listen': ASUS,                         # 要配 ADSP 的 LSM 模組
    'Media': OP,
    'NFC': DROP,
    'PD mapper': OP,
    'Perf': OP,
    'Peripheral manager': OP,
    'Postprocessing': OP,
    'Power-off alarm': OP,
    'QMI': OP,
    'RIL': OP,
    'Radio - IMS': OP,
    'Radio - MBN': DROP,                    # FP3 的電信商設定清單
    'Sensors': ASUS,
    'Soter': DROP,
    'Thermal': ASUS,
    'Time services': OP,
    'Trusted Execution Environment connector': OP,
    'Trusted User Interface': OP,
    'Wi-Fi': OP,
}
OP_DROP_FILES = {
    'vendor/etc/dirac/interfacedb', 'vendor/etc/diracvdd.bin',   # OnePlus 的 Dirac 音效
    # OnePlus 自家的 drmkey HAL：介面在 hardware/oneplus（沒帶進來），這台也用不到
    'vendor/bin/hw/vendor.oneplus.hardware.drmkey@1.0-service',
    'vendor/etc/init/vendor.oneplus.hardware.drmkey@1.0-service.rc',
    # libQSEEComAPI 兩個架構都用 ASUS 的：它是對 TZ app 的 ioctl 包裝，而 keymaster / 指紋 / HDCP /
    # PlayReady 用的都是 ASUS 的 TZ app，且需要 32 位元版（OnePlus 只有 lib64）
    'vendor/lib64/libQSEEComAPI.so',
    # CACert 那一段拿掉之後，放在別段的 client 庫依賴的 vendor.qti.hardware.cacert@1.0 就不存在了
    'vendor/lib64/libcacertclient.so',
    # 藍牙位址的 NV 讀取庫（API 相同）：OnePlus 版讀 /mnt/vendor/persist/bluetooth/，這台沒有 -> HAL 產生
    # 隨機的 22:22:xx 位址；ASUS 版讀 /factory/bt_nv.bin（出廠寫入的位址）
    'vendor/lib64/libbtnv.so',
}

# OnePlus 清單裡釘了 hash（|原檔|fixup 後）、但我們又加了自己 fixup 的檔。不拿掉釘選的話，extract_utils 看到
# 備份檔與 fixup 後的 hash 相符就直接沿用、不會重跑 fixup —— 新加的 fixup 靜靜地沒生效（2026-09-26 實測）
OP_UNPIN = {
    'vendor/lib64/libwvhidl.so',   # replace_needed libprotobuf-cpp-lite -> libprotobuf-cpp-lite-v29（extract-files.py）
}

# ---------------------------------------------------------------- ASUS 的排除規則
# 規則 2：22.2 從原始碼編的 HAL、AOSP 介面程式庫（device.mk / hardware/qcom-caf/msm8998）
FROM_SOURCE = [
    r'^bin/hw/android\.hardware\.',            # 所有 AOSP HAL service（22.2 自己編）
    # AOSP HAL 的 -impl。例外：ASUS 的 gnss@1.0-impl-qti（GPS 用 ASUS 的，由 AOSP 的 gnss@1.0-service 載入）
    r'^lib(64)?/hw/android\.hardware\.(?!gnss@1\.0-impl-qti\.so$)',
    r'^lib(64)?/android\.hardware\.',          # AOSP 的 HIDL 介面程式庫（.vendor 變體由原始碼編）
    r'^lib(64)?/android\.hidl\.',
    r'^lib(64)?/lib(hidl|hwbinder)',
    r'^lib(64)?/hw/(gralloc|hwcomposer|memtrack|lights|power|audio\.primary|audio\.usb|audio\.r_submix|vulkan)\.',
    r'^lib(64)?/(libqdutils|libqdMetaData|libqservice|libgralloc|libsdmcore|libsdmutils|libdisplayconfig|libhdmiedid|libhfp|libsndmonitor|libspkrprot|libssrec|libvolumelistener|libaudio-resampler|libqcompostprocbundle|libqcomvisualizer|libqcomvoiceprocessing)\.so$',
    r'^lib(64)?/(libOmx(Core|Vdec|Venc|AacEnc|AmrEnc|EvrcEnc|QcelpEnc|G711Enc|Swvdec|Swvenc)|libstagefrighthw|libc2dcolorconvert|libmm-omxcore)\.so$',
    r'^lib(64)?/soundfx/lib(qcompostprocbundle|qcomvisualizer|qcomvoiceprocessing|volumelistener)\.so$',
    # 22.2 的 soong namespace 裡有原始碼的（tools/128 抓出來的同名模組）：
    #   hardware/qcom-caf/msm8998（display）、data-ipa-cfg-mgr-legacy-um、dataservices、wlan、perfd-client
    r'^lib(64)?/(libdrmutils|libgpu_tonemapper|libgrallocutils|libipanat|liboffloadhal|librmnetctl|libcld80211|libqti-perfd-client)\.so$',
    r'^bin/ipacm$',
    # tools/129 對 22.2 原始碼樹的 soong 模組名比出來的：Oreo 時代 ASUS 一起放進 vendor 的 AOSP / CAF 元件
    r'^bin/(sh|toybox_vendor|toolbox_vendor|vndservice|vndservicemanager|hostapd|hostapd_cli)$',
    r'^bin/hw/(wpa_supplicant|rild)$',
    r'^lib(64)?/(libril|librilutils|libdrm|libtinyxml|libeffects|libalsautils|libhwc2on1adapter|libwpa_client'
    r'|libwifi-hal|libwifi-hal-qcom|libkeystore-wifi-hidl|libkeystore-engine-wifi-hidl|libnfnetlink'
    # （libloc_pla / libloc_stub 不在這裡了：GPS 改用 ASUS 的堆疊，ASUS 的 libloc_core 要配它自己的那兩個）
    r'|libnetfilter_conntrack|libbt-vendor|camera\.device@\d\.\d-impl)\.so$',
    r'^lib(64)?/soundfx/lib(downmix|ldnhncr|visualizer|effectproxy|bundlewrapper|reverbwrapper|audiopreprocessing)\.so$',
    r'^lib(64)?/hw/(vr|thermal|vibrator|local_time)\.default\.so$',
    r'^lib(64)?/mediadrm/libdrmclearkeyplugin\.so$',
    r'^etc/(audio_policy_configuration|audio_policy_volumes|audio_effects|audio_output_policy)',  # device tree 提供
    r'^etc/media_codecs', r'^etc/media_profiles',                                               # device tree 提供
    r'^etc/(vintf|compatibility_matrix|manifest)',
    # vendor 根目錄的三個：VINTF 由 DEVICE_MANIFEST_FILE / DEVICE_MATRIX_FILE 給（放 PRODUCT_COPY_FILES
    # 會被 build/make/core/Makefile:161 擋）；ueventd.rc 由 device tree 的 rootdir 給
    # ASUS 那份需要的節點已挑進 rootdir/etc/ueventd.qcom.rc（多半是別的平台的範本行，真正要的十幾條）；
    # ASUS 自己的節點（goodix_fp、LaserSensor…）是 init.asus.rc 用 chown 設的，在 init.target.rc
    r'^(compatibility_matrix|manifest)\.xml$', r'^ueventd\.rc$',
    # tools/130 抓到的：soong 自己會裝到同一路徑（Kati：overriding commands for target）
    #   IPACM_cfg.xml  ipacm 由原始碼編（data-ipa-cfg-mgr-legacy-um），設定檔配它自己的版本
    #   fstab.qcom     device tree 提供（沒有 vendor 分割區的版本）
    #   mkshrc         AOSP
    #   WCNSS_qcom_cfg.ini  device tree 的（配新 kernel 的 qcacld）；⚠ ASUS 的值要在設定檔那一輪逐項比對
    r'^etc/(IPACM_cfg\.xml|fstab\.qcom|mkshrc)$', r'^firmware/wlan/qca_cld/WCNSS_qcom_cfg\.ini$',
    r'^etc/wifi/wpa_supplicant\.conf$',        # hardware/qcom-caf/wlan/qcwcn/config 產生（Android.mk，tools/130 看不到）
    r'^etc/mixer_paths_tasha\.xml$',           # 通用版；改裝 ASUS 調過的 mixer_paths_ZS551KL.xml（見 RENAMED）
    # ASUS 的 split-A2DP 版 audio policy（16.0 同一條：tools/31 的 EXCLUDE_EXACT）。
    # /vendor/etc/audio/ 的優先順序比 /vendor/etc/ 高，它會搶走 device tree 那份；而它用了 A15 不認得的
    # AUDIO_DEVICE_OUT_ALL_SCO -> 整份解析失敗（"deserialize: bad type"）-> AudioPolicy 退回 setDefault，
    # 只剩喇叭：藍牙配對得上但聲音從喇叭出、聽筒 / 耳機路由全不存在（2026-09-25）
    r'^etc/audio/audio_policy_configuration(_24bit)?\.xml$',
    # 原廠 4.4.78 kernel 的模組：新 kernel 是 4.4.302（vermagic 不同），qcacld 也已 built-in。
    # 而且原廠的 .ko 本來就因 CONFIG_MODULE_SIG_FORCE 載不起來（16.0 的「已知但不阻塞」）
    r'^lib/modules/',
]
# 規則 3：不要的功能
UNWANTED = [
    # ASUS 的 slim_daemon（GNSS 的感測器輔助）：引用 Oreo HIDL 才會匯出的
    # android::frameworks::sensorservice::V1_0::toString(Result)（A15 改成標頭裡的 inline），執行期載不起來。
    # 基本衛星定位不需要它（2026-09-26）
    r'^bin/slim_daemon$',
    r'nfc', r'nqnfc', r'(^|/)ese', r'esepower', r'(^|/)ant[_.-]', r'AntHal', r'(^|/)fm[_.-]', r'libfm',
    r'\.ant@', r'\.fm@',                       # com.qualcomm.qti.ant@1.0-impl、vendor.qti.hardware.fm@1.0-impl
    r'wigig',                                  # 802.11ad：msm_11ad_proxy.ko 載不起來（kernel 模組簽章）
    r'(^|/)(lib)?mmi(\.|_|$|/)',               # QTI MMI 工廠測試（bin/mmi*、libmmi、mmi_*.so）；libmmi 還連 libskia
                                               # （16.0 tools/31 同一結論）。不會吃到相機的 libmmipl
    r'^lib/libjni\.so$',                       # ASUS 相機 App 的縮時錄影 JNI（Java_com_thundy_…，App 以
                                               # loadLibrary 載入；App 不收）。還連 libskia / libcamera_client
    # 測試 / 除錯工具（沒有 rc 會啟動它們；22.2 上又各缺符號，check_elf 報錯）
    r'^bin/(mm-[a-z0-9-]+-test|qmi_test_[a-z0-9_]+|diag_mdlog|hal_proxy_daemon|ditbsp)$',
    r'^bin/qmi-framework-tests/',              # QMI 框架的測試程式（整個目錄）
    r'^lib(64)?/librecovery_updater_msm\.so$', # ASUS 的 recovery 更新擴充（22.2 的 recovery 不用）
    r'^lib(64)?/libdirac',
    # Oreo 的 legacy DRM 外掛（mediadrmserver 從 /vendor/lib*/mediadrm 載入）：A15 不再載入 legacy 外掛，
    # Widevine 走 OnePlus 的 drm@1.2 HAL。留著只會在 tools/137 報 protobuf 撞名
    r'^lib(64)?/mediadrm/libwvdrmengine\.so$',
]
# 規則 6 的補充：檔名與 OnePlus 對不上、但確定屬於 OnePlus 接手的堆疊
OP_STACK = [
    r'^vendor/lib(64)?/(hw/)?vendor\.qti\.hardware\.iop@',   # Perf（IOP）：OnePlus 的 perf 堆疊；ASUS 的 impl
                                                           # NEEDED 無後綴的介面庫，與 _vendor 檔名對不上
    r'^vendor/lib(64)?/libqti-perfd\.so$',                   # Perf daemon 的本體（client 由原始碼編）
    r'^vendor/lib(64)?/lib(bt-hidlclient|bthost_if)\.so$',   # Bluetooth：OnePlus 的堆疊（hidlclient 還連 ANT）
    # GNSS 改用 ASUS 的堆疊（'GPS': ASUS）之後，只剩這兩類不要：
    #   vendor.qti.gnss@1.0（Izat 的 HIDL 擴充，Oreo 產生 -> 規則 8 本來就會擋；16.0 也停用，
    #   Oreo/Pie 的 toString<GnssNiNotifyFlags> 不相容）、garden_app / mmi_gps（測試工具）
    r'^vendor/bin/(hw/vendor\.qti\.gnss@|garden_app$)',
    r'^vendor/lib(64)?/(hw/)?vendor\.qti\.gnss@',
    r'^vendor/lib(64)?/mmi_gps\.so$',
]
# 建置期 check_elf 的誤報：符號在執行期找得到，只是 check_elf 用的 stub 沒有。每條寫理由
CHECKELF_OFF = {
    # __page_size：32 位元 libc 為相容舊 NDK 程式仍匯出（bionic/libc/bionic/ndk_cruft.cpp，libc.map.txt
    # 標 arm x86），vendor 的 libc stub 不含這類舊相容符號
    'vendor/lib/libxditk_arch.so',
    # DT_SONAME 是 libgxfingerprint.default.so、檔名是 gxfingerprint.default.so —— HAL 以路徑 dlopen，不看 SONAME
    'vendor/lib64/hw/gxfingerprint.default.so',
    # glFenceSync / glProgramBinary 等 GLES 3 函式：執行期的 libGLESv2.so 有匯出，檢查用的 stub 只到 GLES 2
    'vendor/lib/libmmcamera_ppeiscore.so',
    # DT_SONAME 是 libfingerprint.default.so —— fingerprint HAL 以 ro.hardware.fingerprint 組路徑 dlopen，不看 SONAME
    'vendor/lib64/hw/fingerprint.gx5206.so', 'vendor/lib64/hw/fingerprint.gx5216.so',
    # android::checkCallingPermission(String16)：system 版 libbinder 才有（vendor 版沒有權限 API）。非 Treble 的
    # legacy linkerconfig 搜尋順序是 /system 先，執行期拿到的是 system 那份
    'vendor/lib64/libfpservice.so',
}
# check_elf 的第二輪（2026-09-25）：同一類問題一顆一顆列不完 -> 從 blob 的符號表自動算，寫給 extract-files.py
# - COMPILER_RT：Oreo 的 liblog / libm 意外匯出、22.2 不再匯出的 compiler-rt 輔助函式（arm 32 位元）
#   -> 用到的 blob add_needed libcompiler_rt.so
COMPILER_RT = {'__aeabi_d2lz', '__aeabi_d2ulz', '__aeabi_f2lz', '__aeabi_f2ulz', '__aeabi_ldivmod',
               '__aeabi_uldivmod', '__aeabi_l2d', '__aeabi_l2f', '__aeabi_ul2d', '__aeabi_ul2f'}
# - 要清掉的符號版本：OnePlus 的 fastrpc 庫沒有版本定義；LIBC_PRIVATE 新 bionic 不給 vendor
CLEAR_VERSIONS = {'ADSPRPC', 'SDSPRPC', 'LIBC_PRIVATE'}
# 規則 8：引用 Oreo 的 libhidlbase 全域變數 android::hardware::details::g{Bn,Bs}ConstructorMap 的 HIDL 庫
# —— 22.2 的 libhidlbase 早就沒有這兩個符號，執行期一定載不起來（不是 check_elf 的誤報）。
OREO_HIDL_SYMS = {'_ZN7android8hardware7details17gBnConstructorMapE',
                  '_ZN7android8hardware7details17gBsConstructorMapE'}
# 規則 4 / 5
INIT_AND_APPS = [r'^etc/init/', r'^app/', r'^priv-app/', r'^framework/', r'^overlay/']

# 經 PIL 載入的韌體（vendor/firmware 底下）：一律 ASUS（報告裡列出來核對）
PIL_HINT = re.compile(r'\.(mdt|b\d\d)$')


def load_op():
    """回傳 OrderedDict: 區段 -> [(原始行, 安裝路徑)]"""
    secs = OrderedDict()
    cur = None
    for line in open(OP_LIST, encoding='utf-8'):
        s = line.rstrip('\n')
        if s.startswith('# '):
            name = s[2:].strip()
            m = re.match(r'(.*?)\s+-\s+from\s', name)
            name = m.group(1) if m else name
            cur = name
            secs.setdefault(cur, [])
            continue
        if not s or s.startswith('#') or cur is None:
            continue
        entry = s.split('|')[0].split(';')[0]
        entry = entry[1:] if entry.startswith('-') else entry
        dest = entry.split(':')[1] if ':' in entry else entry
        secs[cur].append((s, dest))
    return secs


def load_inv(path):
    return [l.split(None, 1)[1].strip() for l in open(path, encoding='utf-8') if l.strip()]


def elf_needed(path):
    """(架構 'lib'/'lib64', [NEEDED...])；不是 ELF 回 None"""
    try:
        with open(path, 'rb') as f:
            h = f.read(5)
    except OSError:
        return None
    if h[:4] != b'\x7fELF':
        return None
    out = subprocess.run(['readelf', '-d', path], capture_output=True, text=True).stdout
    return ('lib64' if h[4] == 2 else 'lib', re.findall(r'\(NEEDED\).*\[(.*?)\]', out))


def main():
    report = sys.argv[sys.argv.index('--report') + 1] if '--report' in sys.argv else None
    rep = []
    secs = load_op()

    unknown = [s for s in secs if s not in SECTIONS and secs[s]]
    if unknown:
        sys.exit('!!! OnePlus 清單有沒決定的區段：%s' % unknown)

    op_out, op_basenames, asus_from_op = [], set(), []
    for sec, entries in secs.items():
        if not entries:
            continue
        d = SECTIONS[sec]
        rep.append('OnePlus 區段 %-40s %-7s %d' % (sec, d, len(entries)))
        if d == OP:
            kept = [(l, p) for l, p in entries if p not in OP_DROP_FILES]
            op_out.append('\n# %s' % sec)
            op_out += [(l.split('|')[0] if p in OP_UNPIN else l) for l, p in kept]
            op_basenames |= {os.path.basename(p) for _, p in kept}
            # soong 的模組名 = 檔名去副檔名 + MODULE_SUFFIX。ASUS 有檔名本身就叫
            # com.qualcomm.qti.dpm.api@1.0_vendor.so 的（Oreo 的 QTI 命名），與 OnePlus 那條
            # `...dpm.api@1.0.so;MODULE_SUFFIX=_vendor` 同一個模組名 —— 光比檔名抓不到
            for l, p in kept:
                m = re.search(r';MODULE_SUFFIX=([^;|]+)', l)
                if m and p.endswith('.so'):
                    op_basenames.add(os.path.basename(p)[:-3] + m.group(1) + '.so')
        elif d == ASUS:
            asus_from_op += [(sec, p) for _, p in entries]

    # ---------------- ASUS：整個 vendor − 排除規則
    vendor = load_inv(INV_VENDOR)
    # device.mk 的 PRODUCT_COPY_FILES 裝到 vendor 的路徑（例：configs/gps/*.conf 配 OnePlus 的 GNSS）
    dt_copy = set(re.findall(r':\$\(TARGET_COPY_OUT_VENDOR\)/(\S+)', open(os.path.join(OUT, 'device.mk'), encoding='utf-8').read()))
    kept, excluded = [], defaultdict(list)
    for rel in vendor:
        base = os.path.basename(rel)
        if base in op_basenames and not rel.startswith('firmware/'):
            excluded['1 OnePlus 已提供（同檔名）'].append(rel); continue
        if rel in dt_copy or any(re.search(p, rel) for p in FROM_SOURCE):
            excluded['2 22.2 從原始碼編 / device tree 提供'].append(rel); continue
        if any(re.search(p, rel, re.I) for p in UNWANTED):
            excluded['3 不要的功能'].append(rel); continue
        if any(re.search(p, rel) for p in INIT_AND_APPS):
            excluded['4/5 init rc、App、framework、overlay'].append(rel); continue
        kept.append('vendor/' + rel)

    # 規則 6：依賴封閉。規則 1 只比檔名，抓不到「同一個 QTI 堆疊裡、OnePlus 沒有那個架構版本」
    # 的東西 —— 例如 ASUS 的 32 位元 libril-qc-qmi-1 需要的 32 位元 libdsi_netctrl 被讓給了 OnePlus，
    # 但 OnePlus 只有 lib64。那個 ASUS blob 屬於 OnePlus 接手的堆疊（RIL / GNSS / CNE / IMS / BT /
    # Adreno），留著就是新舊兩版混用、而且 build graph 會報 missing variant。
    # 做法：它 NEEDED 的庫若是「規則 1 排除、OnePlus 又沒有同架構」的，就一起排除；遞迴到穩定。
    op_arch = defaultdict(set)
    for sec, entries in secs.items():
        if SECTIONS.get(sec) == OP:
            for _, p in entries:
                m = re.match(r'(?:vendor|system_ext|system)/(lib|lib64)/(.+\.so)$', p)
                if m and p not in OP_DROP_FILES:
                    op_arch[os.path.basename(m.group(2))].add(m.group(1))
    gap = set()
    for rel in excluded['1 OnePlus 已提供（同檔名）']:
        m = re.match(r'(lib|lib64)/(.+\.so)$', rel)
        if m and m.group(1) not in op_arch.get(os.path.basename(rel), ()):
            gap.add((m.group(1), os.path.basename(rel)))
    # 規則 3 排掉的庫（NFC、ANT、FM、wigig…）沒有任何人提供 —— 依賴它們的也跟著走
    for rel in excluded['3 不要的功能']:
        e = elf_needed(os.path.join(DUMP, 'vendor', rel))
        if e and rel.endswith('.so'):
            gap.add((e[0], os.path.basename(rel)))
    # 檔名對不上、但確定屬於 OnePlus 接手堆疊的（同樣歸在規則 6）
    for p in [p for p in kept if any(re.search(r, p) for r in OP_STACK)]:
        kept.remove(p)
        excluded['6 屬於 OnePlus 接手的堆疊（依賴封閉）'].append(p[len('vendor/'):] + '  <- OP_STACK')
        e = elf_needed(os.path.join(DUMP, p))
        if e and p.endswith('.so'):
            gap.add((e[0], os.path.basename(p)))   # 依賴它的（如 libqti-iopd-client）也一起走
    # rfsa/ 底下是跑在 aDSP（Hexagon）上的程式：NEEDED 由 DSP 端的 loader 解析（libgcc.so、同目錄的 skel），
    # 不經過 Android 的 linker —— 規則 6 / 7 不看它們（16.0 tools/31 也是同樣的結論）
    needed = {p: (None if '/rfsa/' in p else elf_needed(os.path.join(DUMP, p))) for p in kept}
    while True:
        drop = [p for p in kept if needed[p] and any((needed[p][0], n) in gap for n in needed[p][1])]
        if not drop:
            break
        for p in drop:
            kept.remove(p)
            why = sorted(n for n in needed[p][1] if (needed[p][0], n) in gap)
            excluded['6 屬於 OnePlus 接手的堆疊（依賴封閉）'].append('%s  <- %s' % (p[len('vendor/'):], ' '.join(why)))
            if p.endswith('.so'):
                gap.add((needed[p][0], os.path.basename(p)))

    # 規則 7：原廠就載不起來的 —— NEEDED 的庫在原廠映像的 lib 目錄（system 與 vendor 的
    # lib/、lib64/ 頂層）根本不存在。例：libmmcamera_llvd 要 libllvd_smore、libmm-qdcm 要
    # libmm-qdcm-diag，原廠都沒有。這種通常是被別人以可選模組 dlopen、失敗就跳過；
    # 不收等於原廠行為，收了 build graph 會報 undefined module。遞迴到穩定。
    stock = set()
    for pre, inv in (('', load_inv(INV_SYSTEM)), ('vendor/', ['vendor/' + r for r in vendor])):
        for r in inv:
            m = re.match(r'(?:vendor/)?(lib|lib64)/([^/]+\.so)$', r)
            if m:
                stock.add((m.group(1), m.group(2)))
    while True:
        drop = [p for p in kept if needed.get(p) and any((needed[p][0], n) not in stock for n in needed[p][1])]
        if not drop:
            break
        for p in drop:
            kept.remove(p)
            why = sorted(n for n in needed[p][1] if (needed[p][0], n) not in stock)
            excluded['7 原廠就載不起來（NEEDED 不存在）'].append('%s  <- %s' % (p[len('vendor/'):], ' '.join(why)))
            if p.endswith('.so'):
                stock.discard((needed[p][0], os.path.basename(p)))

    # 規則 8：Oreo HIDL（見 OREO_HIDL_SYMS）。本身載不起來 -> 依賴它的也載不起來，遞迴。
    # 2026-09-25 第一次完整編譯抓到 30 個，依賴者多是漏網的 OnePlus 接手堆疊（ASUS 的 64 位元
    # libril-qc-qmi-1、CNE 的 libwqe、perf / qdutils_disp 服務、ATFWD、wifidisplay、qfp 指紋…）
    broken = set()
    for p in kept:
        if needed.get(p) and p.endswith('.so'):
            und = subprocess.run(['nm', '-D', '--undefined-only', os.path.join(DUMP, p)],
                                 capture_output=True, text=True).stdout
            hit = OREO_HIDL_SYMS & set(x.split()[-1] for x in und.splitlines() if x.strip())
            if hit:
                broken.add((needed[p][0], os.path.basename(p)))
                excluded['8 Oreo HIDL（22.2 載不起來）'].append(p[len('vendor/'):] + '  <- gBn/gBsConstructorMap')
    kept[:] = [p for p in kept if not (needed.get(p) and (needed[p][0], os.path.basename(p)) in broken
                                        and p.endswith('.so'))]
    while True:
        drop = [p for p in kept if needed.get(p) and any((needed[p][0], n) in broken for n in needed[p][1])]
        if not drop:
            break
        for p in drop:
            kept.remove(p)
            why = sorted(n for n in needed[p][1] if (needed[p][0], n) in broken)
            excluded['8 Oreo HIDL（22.2 載不起來）'].append('%s  <- %s' % (p[len('vendor/'):], ' '.join(why)))
            if p.endswith('.so'):
                broken.add((needed[p][0], os.path.basename(p)))

    # libstdc++：ASUS 的 Oreo blob NEEDED libstdc++.so，但 vendor 能連的是 libstdc++_vendor（裝成
    # libstdc++_vendor.so）-> extract-files.py 對這些檔 replace_needed。清單在這裡算，寫給它讀
    stdcxx = {p for p in kept if needed.get(p) and 'libstdc++.so' in needed[p][1]}

    # 從符號表自動算的 fixup（見 COMPILER_RT / CLEAR_VERSIONS）
    fix = {}
    for p in kept:
        if not needed.get(p):
            continue
        out = subprocess.run(['readelf', '--dyn-syms', '-W', os.path.join(DUMP, p)],
                             capture_output=True, text=True).stdout
        und = [l.split()[7] for l in out.splitlines() if len(l.split()) >= 8 and l.split()[6] == 'UND']
        names = {s.split('@')[0] for s in und}
        clear = sorted({s.split('@')[0] for s in und if '@' in s and s.split('@')[-1].split()[0] in CLEAR_VERSIONS})
        crt = needed[p][0] == 'lib' and bool(names & COMPILER_RT) and 'libcompiler_rt.so' not in needed[p][1]
        if p in stdcxx or crt or clear:
            fix[p] = {'libstdcxx': p in stdcxx, 'compiler_rt': crt, 'clear_versions': clear}

    # OnePlus 決定用 ASUS 的區段：ASUS 有沒有同一路徑（報告用；沒有的話要人工看是不是改名了）
    asus_set = set(kept)
    miss = [(s, p) for s, p in asus_from_op if p not in asus_set and p.startswith('vendor/')]

    # ---------------- system 側（16.0 的 tools/31 SYSTEM_SCAN_DIRS 的精神）：韌體
    system = load_inv(INV_SYSTEM)
    sys_fw = ['system/' + r for r in system if r.startswith('etc/firmware/')]
    # system 側的 ASUS 硬體必需品（照原路徑放 /system —— blob 以絕對路徑引用）。
    # 取自 16.0 清單的 system 側，拿掉已換成 OnePlus/FP3 的 QTI 堆疊（IMS、CNE、DPM、WFD、
    # ANT、NFC、eSE、perf）與 DTS。
    SYSTEM_EXTRA = [
        'bin/LaserFocus_CalStart', 'bin/LaserFocus_on', 'bin/LaserFocus_value',
        'etc/audio_codec_status.sh', 'etc/headset_status.sh', 'etc/select_mic.sh', 'etc/select_output.sh',
        'etc/init.asus.asus_amp_cal.sh', 'etc/init.asus.asus_nonmp_amp_cal.sh',
        'etc/init.asus.slpi_ssr.sh',
        'etc/rcvampcal.sh', 'etc/readRCVCal.sh', 'etc/readSPKCal.sh', 'etc/spkampcal.sh',
        'etc/speaker_l.ftcfg', 'etc/speaker_r.ftcfg', 'etc/silence.wav',
        'etc/mixer_paths_ZS551KL.xml', 'etc/mixer_paths_ZS551KL_EU.xml', 'etc/mixer_paths_ZS551KL_leak.xml',
        'etc/rgb_sensor_init.sh', 'etc/sensors_init.sh',
        'etc/scve/facereco/gModel.dat',
        # vendor 的 blob NEEDED 的 system 側程式庫（2026-09-25 對映像 vendor/ 查 DT_NEEDED）：
        'lib/libAsusRGBSensorHAL.so', 'lib64/libAsusRGBSensorHAL.so',   # <- libxditk_ditArchLIB（雷射/RGB）
        'lib/libpreisp_camera.so', 'lib/libpreisp_shimlayer.so',       # <- camera.msm8998、libmmcamera2_*
        'lib/libjpegHWCompress.so',                                    # <- libasuscameraext_jpeg_hw_encoder
        'lib/libtrueportrait.so',                                      # <- libmmcamera_trueportrait_lib
        'usr/idc/focal-touchscreen.idc', 'usr/keychars/focal-touchscreen.kcm',
    ]
    # 刻意不收：
    #   libsensor1 / libsensor_reg  vendor/ 也有（64 位元逐 byte 相同，32 位元的 libsensor1 差 16 bytes），
    #                               兩份都收會產生同名的 prebuilt_libsensor1 模組。非 Treble 的 legacy
    #                               linkerconfig 是單一 namespace，vendor 那份照樣找得到
    #   libkeymaster1 / libsoftkeymaster  指紋整條（gxFpDaemon、fingerprint.gx52*、libfp_client、libfpservice、
    #                               FpCmd）都 NEEDED 它們與 libsoftkeymasterdevice，但 nm 比對**一個符號都沒用到**
    #                               （過度連結）。extract-files.py 用 remove_needed 拿掉，就不必帶這兩個 Oreo 庫
    #                               —— libsoftkeymaster 還連著 22.2 已不存在的 libkeystore_binder
    #   libmmosal                   vendor 用的是 libmmosal_proprietary；這個只有 WFD 與 system 側 libmmparser 用
    sysset = set(system)
    missing_sys = [r for r in SYSTEM_EXTRA if r not in sysset]
    if missing_sys:
        sys.exit('!!! system 側清單裡有 ASUS 映像沒有的：%s' % missing_sys)
    sys_extra = ['system/' + r for r in SYSTEM_EXTRA]

    # 改名安裝（src:dst）
    # - ACDB：ASUS 的 libacdbloader 用 ro.build.product 當目錄名（先找 /asusfw/audio/acdbdata/<名>、
    #   再找 /vendor/etc/acdbdata/<名>）。原廠是 ZS551KL，我們是 Z01G，ro.* 蓋不掉 -> 同一份再以 Z01G 裝一份
    #   （16.0 tools/31 的 EXTRA_RENAMED）。ro.boot.id.stage=7 會選 _MP
    # - mixer_paths：22.2 的 audio HAL 是原始碼編的 CAF 版，依音效卡名 msm8998-tasha-snd-card 找
    #   mixer_paths_tasha.xml（platform.c 的 MIXER_XML_BASE_STRING 那段）；ASUS 調過的是 system/etc 的
    #   mixer_paths_ZS551KL.xml（通用 tasha 版的超集：547 對 463 條路徑）
    acdb = ['Bluetooth_cal.acdb', 'General_cal.acdb', 'Global_cal.acdb', 'Handset_cal.acdb',
            'Hdmi_cal.acdb', 'Headset_cal.acdb', 'Speaker_cal.acdb', 'workspaceFile.qwsp']
    renamed = [('vendor/etc/acdbdata/ZS551KL%s/ZS551KL_%s' % (s, t), 'vendor/etc/acdbdata/Z01G%s/Z01G_%s' % (s, t))
               for s in ('', '_MP') for t in acdb]
    renamed.append(('system/etc/mixer_paths_ZS551KL.xml', 'vendor/etc/mixer_paths_tasha.xml'))
    # 搬到 /vendor：vendor 網域讀 system_file 撞 system/sepolicy/private/domain.te 的 neverallow（SELinux 第一批）
    # - audbg 兩支腳本由 init 以 /vendor/bin/sh 執行（qti_init_shell），init.target.rc 改指 /vendor/bin
    # - preisp_profiles.xml：libpreisp_camera.so 寫死 "/etc/preisp_profiles.xml"（24 字元），extract-files.py
    #   把它換成 "/vendor/etc/preisp.xml"（22 字元，後補 NUL），所以這裡要裝成這個短名字
    renamed += [('system/etc/init.asus.audbg.sh', 'vendor/bin/init.asus.audbg.sh'),
                ('system/etc/init.asus.checkaudbg.sh', 'vendor/bin/init.asus.checkaudbg.sh'),
                ('system/etc/preisp_profiles.xml', 'vendor/etc/preisp.xml')]
    have = {'vendor/' + r for r in vendor} | {'system/' + r for r in system}
    missing_ren = [s for s, _ in renamed if s not in have]
    if missing_ren:
        sys.exit('!!! 改名來源不存在：%s' % missing_ren)

    # ---------------- 輸出
    hdr = ('# 由 tools/125_build_blob_lists_22.py 產生，不要手改。\n'
           '# 規則與理由見那支腳本的開頭與 bring-up 筆記的「blob 清單」。\n')
    with open(os.path.join(OUT, 'proprietary-files-oneplus.txt'), 'w', encoding='utf-8', newline='') as f:
        f.write(hdr + '# 來源：TheMuppets/proprietary_vendor_oneplus_msm8998-common（lineage-22.2）\n')
        f.write('\n'.join(op_out).lstrip('\n') + '\n')
    groups = OrderedDict()
    for p in sorted(kept):
        g = re.sub(r'^vendor/(lib64|lib|bin|etc|firmware|[^/]+).*', r'vendor/\1', p)
        groups.setdefault(g, []).append(p)
    with open(os.path.join(OUT, 'proprietary-files.txt'), 'w', encoding='utf-8', newline='') as f:
        f.write(hdr + '# 來源：ASUS 原廠 1911.117 的 system.img（vendor 在 /system/vendor）\n')
        for g, ps in groups.items():
            f.write('\n# %s（%d）\n' % (g, len(ps)))
            f.write('\n'.join(p + (';DISABLE_CHECKELF' if p in CHECKELF_OFF else '') for p in ps) + '\n')
        stale = CHECKELF_OFF - set(kept)
        if stale:
            sys.exit('!!! CHECKELF_OFF 裡有不在清單上的：%s' % sorted(stale))
        f.write('\n# system/etc/firmware（%d）—— ADSP、TAS2557、面板色溫…（16.0 ADSP -60 的教訓）\n' % len(sys_fw))
        f.write('\n'.join(sys_fw) + '\n')
        f.write('\n# system 側的 ASUS 硬體必需品（%d）—— 雷射、功放校正、mixer_paths、audbg、感測器、相機\n' % len(sys_extra))
        f.write('\n'.join(sys_extra) + '\n')
        f.write('\n# 改名安裝（%d）—— ACDB 以 Z01G 再裝一份、ASUS 的 mixer_paths 裝成 tasha（見 tools/125）\n' % len(renamed))
        # ;TRYSRCFIRST：extract_utils 的 Source._copy_file_to_path() 預設**先找 dst**。dump 裡剛好有
        # vendor/etc/mixer_paths_tasha.xml（ASUS 沒用到的通用版，783 條路徑、沒有 "... speaker"），
        # 於是拿到的是它而不是 system/etc/mixer_paths_ZS551KL.xml（902 條）-> 喇叭路徑全找不到、
        # 完全沒聲音（2026-09-25）。改名安裝的項目一律先找 src
        f.write('\n'.join('%s:%s;TRYSRCFIRST' % sd for sd in renamed) + '\n')
    # 給 extract-files.py 的 fixup（由符號表算，不要手改）：
    #   libstdcxx       replace_needed libstdc++.so -> libstdc++_vendor.so
    #   compiler_rt     add_needed libcompiler_rt.so
    #   clear_versions  clear_symbol_version（@ADSPRPC / @SDSPRPC / @LIBC_PRIVATE 的符號）
    import json
    with open(os.path.join(OUT, 'blob-fixups-generated.json'), 'w', encoding='utf-8', newline='') as f:
        json.dump(fix, f, indent=1, sort_keys=True)
        f.write('\n')
    rep.append('自動 fixup：%d 個檔（libstdc++ %d、compiler_rt %d、清符號版本 %d）' % (
        len(fix), sum(v['libstdcxx'] for v in fix.values()), sum(v['compiler_rt'] for v in fix.values()),
        sum(bool(v['clear_versions']) for v in fix.values())))

    n_op = sum(1 for l in op_out if l.strip() and not l.lstrip('\n').startswith('#'))
    rep.append('')
    rep.append('OnePlus 清單：%d 條' % n_op)
    rep.append('ASUS vendor：共 %d，收 %d，排除 %d' % (len(vendor), len(kept), len(vendor) - len(kept)))
    for k in sorted(excluded):
        rep.append('  排除 %-38s %d' % (k, len(excluded[k])))
    rep.append('ASUS system/etc/firmware：%d；system 側其他：%d' % (len(sys_fw), len(sys_extra)))
    fw = [p for p in kept if p.startswith('vendor/firmware/') and PIL_HINT.search(p)]
    rep.append('ASUS vendor/firmware 的 PIL 映像（.mdt/.bNN）：%d 個，例：%s' % (
        len(fw), ', '.join(sorted({os.path.basename(p).split('.')[0] for p in fw}))))
    rep.append('OnePlus 決定用 ASUS 的區段，ASUS 沒有同路徑的：%d' % len(miss))
    for s, p in miss:
        rep.append('    [%s] %s' % (s, p))
    for k in sorted(excluded):
        rep.append('\n== %s（%d）' % (k, len(excluded[k])))
        rep += ['    ' + x for x in sorted(excluded[k])]
    text = '\n'.join(rep) + '\n'
    if report:
        open(report, 'w', encoding='utf-8').write(text)
    print('\n'.join(rep[:rep.index('') + 12 + len(excluded)]))


if __name__ == '__main__':
    main()
