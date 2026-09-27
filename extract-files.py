#!/usr/bin/env -S PYTHONPATH=../../../tools/extract-utils python3
#
# SPDX-FileCopyrightText: 2024 The LineageOS Project
# SPDX-FileCopyrightText: 2026 ZS551KL port
# SPDX-License-Identifier: Apache-2.0
#
# 兩個 vendor 模組（清單由 tools/125_build_blob_lists_22.py 產生）：
#
#   ./extract-files.py <ASUS 的 dump>             -> vendor/asus/Z01G          （proprietary-files.txt）
#   ./extract-files.py --oneplus <OnePlus 來源>   -> vendor/asus/Z01G-oneplus  （proprietary-files-oneplus.txt）
#
# 來源：ASUS = tools/126 準備的 ~/asus/dump（1911.117，a530_pfp.fw 已換 linux-firmware 1.87.01）
#       OnePlus = TheMuppets/proprietary_vendor_oneplus_msm8998-common 的 proprietary/
# 兩個來源不同，所以分兩次跑（extract_utils 一次只吃一個來源）。
#

import json
import os
import re
import sys

from extract_utils.fixups_blob import (
    blob_fixup,
    blob_fixups_user_type,
)
from extract_utils.fixups_lib import (
    lib_fixups,
    lib_fixups_user_type,
)
from extract_utils.main import (
    ExtractUtils,
    ExtractUtilsModule,
)

namespace_imports = [
    'device/asus/Z01G',
    'hardware/qcom-caf/msm8998',
    'hardware/qcom-caf/wlan',
    'vendor/qcom/opensource/dataservices',
]


def lib_fixup_vendor_suffix(lib: str, partition: str, *args, **kwargs):
    return f'{lib}_{partition}' if partition == 'vendor' else None


def remove_all_needed(libs) -> blob_fixup:
    fixup = blob_fixup()
    for lib in libs:
        fixup = fixup.remove_needed(lib)   # 檔案沒有這條 NEEDED 時 patchelf 什麼都不做
    return fixup


FP_UNUSED_NEEDED = (
    'libkeystore_binder.so', 'libbacktrace.so', 'libunwind.so', 'ld-android.so',
    'libsoftkeymasterdevice.so', 'libsoftkeymaster.so', 'libkeymaster1.so', 'libkeymaster_messages.so',
    'libandroid_runtime.so', 'libprotobuf-cpp-lite.so', 'liblzma.so',
)

# ---------------------------------------------------------------- ASUS（1911.117）
asus_blob_fixups: blob_fixups_user_type = {
    # （OnePlus 對 libmmcamera_faceproc 的 clear_symbol_version 已由 blob-fixups-generated.json 自動涵蓋）
    # Goodix 指紋整條是過度連結的（ASUS 的 Android.mk 把一整串 system 庫都連上去）。
    # 對 7 個檔逐一比 nm -D：下列 NEEDED 被用到的符號數**全部是 0**，而它們在 22.2
    # 不是不存在（libkeystore_binder、libbacktrace、libunwind、Oreo 的 keymaster 三庫）、
    # 就是沒有 vendor variant（ld-android、libandroid_runtime、libprotobuf-cpp-lite、liblzma）。
    # 真正用到的只有 libbinder / libutils / libcutils / liblog / libhardware / libc / libdl / libm、
    # libQSEEComAPI 與彼此（libfp_client、libfpservice）。
    **{
        f: remove_all_needed(FP_UNUSED_NEEDED)
        for f in (
            'vendor/bin/gxFpDaemon',
            'vendor/bin/FpCmd',
            'vendor/lib64/hw/fingerprint.gx5206.so',
            'vendor/lib64/hw/fingerprint.gx5216.so',
            'vendor/lib64/hw/gxfingerprint.default.so',
            'vendor/lib64/libfp_client.so',
            'vendor/lib64/libfpservice.so',
        )
    },
    # TAS2557 智慧功放的預設組態：21（量產機音樂用，mixer_paths 裡的 mp-stereo-speaker-dynamic-configuration-music）。
    # ASUS 的音訊 HAL 會依用途主動套 "*-dynamic-configuration-*" 這些路徑；22.2 的 CAF HAL 不認得，
    # 功放一直停在 platform-init 的組態 0（"Tuning Mode_48 KHz_s1_0"）。組態 0 的關閉序列讓功放留在有底噪
    # 的狀態 -> 每次播放結束兩個喇叭都有電流聲（只有硬體重置清得掉）；音質也不是量產機的調校（2026-09-25 實測）。
    # 寫進最上層的預設值：HAL 啟動時套上、通話路徑（voice-handset 的組態 27）還原時也回到 21。
    # 插在全檔唯一的 "Stereo Program" value="0"（最上層預設值）後面
    'vendor/etc/mixer_paths_tasha.xml': blob_fixup()
        .regex_replace(
            r'(<ctl name="Stereo Program" value="0" />)(\r?\n)',
            r'\1\2    <ctl name="Stereo Configuration" value="21" />\2'
            r'    <ctl name="Stereo LDAC Playback Volume" value="15" />\2',
        ),
    # ⚠ 聽筒通話（voice-handset，Program 1 / 組態 27）掛斷之後會掉回組態 0（又有電流聲）。在 mixer_paths 這層
    #   修不了：libaudioroute 依控制項編號寫回初始值，先寫組態 21（這時 Program 還是 1，驅動以 EINVAL 丟掉）、
    #   再寫 Program 0（驅動套該 Program 的預設組態 0）；它快取著 21，之後任何路徑再設 21 都不會真的寫
    #   （2026-09-26 試過在 speaker 路徑加一行，實測無效）。修在 kernel：tas2557-codec.c 記住被拒的組態，
    #   切到它所屬的 Program 時套用
}  # fmt: skip

# 通話擴音沒聲音（2026-09-27）：擴音 / VoIP 的通話路徑先把兩顆 TAS2557 設成 "DevA-Mute-DevB-Mute"，
# 原廠由 ASUS HAL 接著套 *-dynamic-configuration-call（組態 24/25 + DevA-MonoMix-DevB-MonoMix）解除 ——
# 22.2 的 CAF HAL 不認得那些路徑，功放就停在全靜音。把原廠那兩行直接寫進通話路徑（組態 24/25 都屬 Program 0，
# 與擴音時的 Program 相同，驅動不會拒絕；掛斷時 audio_route 把兩者還原成初始值 21 / default）。
# 實測：通話中手動套 24 + MonoMix，擴音立刻有聲音
for _path, _conf in (('voicemmode1-call speaker', 24), ('voicemmode2-call speaker', 24),
                     ('compress-voip-call speaker', 24), ('compress-voip-call handset-for-voip', 25)):
    asus_blob_fixups['vendor/etc/mixer_paths_tasha.xml'].regex_replace(
        r'(<path name="%s">\r?\n)(\s*)<ctl name="Stereo DSPChl Setup" value="DevA-Mute-DevB-Mute" />(\r?\n)'
        % re.escape(_path),
        r'\1\2<ctl name="Stereo Configuration" value="%d" />\3'
        r'\2<ctl name="Stereo DSPChl Setup" value="DevA-MonoMix-DevB-MonoMix" />\3' % _conf,
    )


def asus_fixup(path: str) -> blob_fixup:
    """同一個檔只能有一組 fixup —— 已有的就接著疊（例：libfp_client 同時要 remove_needed 與 libstdc++）"""
    return asus_blob_fixups.setdefault(path, blob_fixup())


# fpseek 偵測到 Goodix 型號後 setprop ro.hardware.fingerprint —— 那是 AOSP 的 exported_default_prop，
# SELinux 只准 init / vendor_init 寫（domain.te 的 neverallow）。改名成同長度（23 字元）的 vendor 屬性，
# 由 init.target.rc 抄進 ro.hardware.fingerprint（fps_hal、fpservice.sh 照舊讀那一條）。檔內只出現這一次
asus_fixup('vendor/bin/fpseek') \
    .binary_regex_replace(re.escape(b'ro.hardware.fingerprint\x00'), b'vendor.asus.fp.hwmodule\x00')

# 由 tools/125 從符號表算出來的 fixup（blob-fixups-generated.json；完整編譯的 check_elf 抓出這幾類，
# 一顆一顆列不完）：
# - libstdcxx：vendor 能連的是 libstdc++_vendor（裝成 libstdc++_vendor.so），DT_NEEDED 要跟著改
# - compiler_rt：__aeabi_d2lz / ldivmod… 這些 compiler-rt 輔助函式，Oreo 的 liblog / libm 意外匯出，
#   ASUS 的相機庫靠它們解析；22.2 不再匯出（d2lz 等連 libc 都沒有）-> 直接連 libcompiler_rt
# - clear_versions：@LIBC_PRIVATE（新 bionic 不給 vendor）、@ADSPRPC / @SDSPRPC（OnePlus 的 fastrpc 庫沒有版本定義）
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'blob-fixups-generated.json')) as fh:
    for path, fx in json.load(fh).items():
        fixup = asus_fixup(path)
        if fx['libstdcxx']:
            fixup.replace_needed('libstdc++.so', 'libstdc++_vendor.so')
        if fx['compiler_rt']:
            fixup.add_needed('libcompiler_rt.so')
        for sym in fx['clear_versions']:
            fixup.clear_symbol_version(sym)

# 手動的：用了 __android_log_print 卻沒有 NEEDED liblog（Oreo 上靠別的庫間接帶進來）
asus_fixup('vendor/lib/libmmcamera2_stats_modules.so').add_needed('liblog.so')

# android::Looper 變大了：舊 blob 自己 `new Looper(false)`，operator new 的大小是編譯時寫死的舊 sizeof，
# A15 的建構子寫出配置範圍 -> 堆積被寫壞。量法：A15 libutils 的 sp<Looper>::make() 裡 operator new 的參數。
#   ILP32：A15 0x88，Oreo 0x70（libpreisp_camera 兩處 `movs r0, #0x70`）
#   LP64 ：A15 0x108，OnePlus（A10）0xe0（slim_daemon 的 `orr w0, wzr, #0xe0`）
# libpreisp_camera 是望遠鏡頭（IMX351）的 Rockchip pre-ISP：camera provider 一開 camera 2 就崩潰（Looper::pollOnce
# 讀到 0x10），CameraService 把所有客戶端踢掉 -> 內建相機（一啟動就列舉所有鏡頭）開不起來、Open Camera 的望遠
# 「占用中」（2026-09-25）。改的是配置大小的那一條指令，樣式各 8 bytes、在檔內唯一（tools/135 會檢查）
asus_fixup('system/lib/libpreisp_camera.so') \
    .binary_regex_replace(re.escape(b'\x70\x20\x25\x63\xff\xf7'), b'\x88\x20\x25\x63\xff\xf7') \
    .binary_regex_replace(re.escape(b'\x70\x20\xff\xf7\xae\xe9'), b'\x88\x20\xff\xf7\xae\xe9') \
    .binary_regex_replace(re.escape(b'/etc/preisp_profiles.xml\x00'), b'/vendor/etc/preisp.xml\x00\x00\x00')
# ↑ 最後一條：RK1608 的設定檔路徑。/etc -> /system/etc 是 system_file，vendor 網域（相機 HAL）讀它撞
#   domain.te 的 neverallow -> 改讀 /vendor/etc/preisp.xml（同長度：22 字元 + 3 個 NUL = 原本 24 + 1）。
#   tools/125 把 system/etc/preisp_profiles.xml 裝成 vendor/etc/preisp.xml

# libstdc++：bionic 只有 libstdc++_vendor 有 vendor variant（ASUS 的 Oreo blob 還連著它）
asus_lib_fixups: lib_fixups_user_type = {
    **lib_fixups,
    'libstdc++': lib_fixup_vendor_suffix,
}

asus_module = ExtractUtilsModule(
    'Z01G',
    'asus',
    blob_fixups=asus_blob_fixups,
    lib_fixups=asus_lib_fixups,
    # ASUS 的 blob 會連 OnePlus 模組提供的 QTI 基礎庫（libdiag、libqmi_cci、libgsl、libadsprpc…）
    namespace_imports=namespace_imports + ['vendor/asus/Z01G-oneplus'],
)

# ---------------------------------------------------------------- OnePlus 5（OOS 10 / FP3）
# 只留套用在我們有借的檔案上的修補（OnePlus 的 extract-files.py，lineage-22.2）
oneplus_lib_fixups: lib_fixups_user_type = {
    **lib_fixups,
    (
        'com.qualcomm.qti.dpm.api@1.0',
        'vendor.qti.imsrtpservice@3.0',
    ): lib_fixup_vendor_suffix,
}

oneplus_blob_fixups: blob_fixups_user_type = {
    (
        'system_ext/lib64/lib-imsvideocodec.so',
        'system_ext/lib64/lib-imscamera.so',
    ): blob_fixup()
        .add_needed('libgui_shim.so')
        .replace_needed('libqdMetaData.so', 'libqdMetaData.system.so'),
    # libprotobuf-cpp-lite-v29：Lineage 的 hardware/lineage/compat 提供、不跟 /system 撞名的 VNDK v29 protobuf
    # （非 Treble 的單一 namespace 會先找到 system 的 A15 版）。⚠ OnePlus 清單把這個檔釘了 hash，
    # tools/125 的 OP_UNPIN 要拿掉，這個 fixup 才會真的跑
    'vendor/lib64/libwvhidl.so': blob_fixup()
        .add_needed('libcrypto_shim.so')
        .replace_needed('libprotobuf-cpp-lite.so', 'libprotobuf-cpp-lite-v29.so'),
    # android::Looper：A15 LP64 是 0x108，這支用 A10 的 0xe0 配置 -> `orr w0, wzr, #0xe0` 改成 `mov w0, #0x108`
    # （說明見上面 libpreisp_camera 那段）
    'vendor/bin/slim_daemon': blob_fixup()
        .binary_regex_replace(re.escape(b'\xe0\x0b\x1b\x32\xfa\x50\x00\x94'), b'\x00\x21\x80\x52\xfa\x50\x00\x94'),
    (
        'vendor/lib/libOGLManager.so',
        'vendor/lib64/libOGLManager.so',
    ): blob_fixup()
        .clear_symbol_version('AHardwareBuffer_allocate')
        .clear_symbol_version('AHardwareBuffer_describe')
        .clear_symbol_version('AHardwareBuffer_lock')
        .clear_symbol_version('AHardwareBuffer_release')
        .clear_symbol_version('AHardwareBuffer_unlock'),
}  # fmt: skip

oneplus_module = ExtractUtilsModule(
    'Z01G-oneplus',
    'asus',
    device_rel_path='device/asus/Z01G',
    skip_main_proprietary_file=True,
    blob_fixups=oneplus_blob_fixups,
    lib_fixups=oneplus_lib_fixups,
    # libQSEEComAPI 兩個架構都由 ASUS 模組提供（tools/125 的 OP_DROP_FILES）
    namespace_imports=namespace_imports + ['vendor/asus/Z01G'],
)
oneplus_module.add_proprietary_file('proprietary-files-oneplus.txt')

if __name__ == '__main__':
    if '--oneplus' in sys.argv:
        sys.argv.remove('--oneplus')
        module = oneplus_module
    else:
        module = asus_module
    utils = ExtractUtils.device(module)
    utils.run()
