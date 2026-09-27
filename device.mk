#
# Copyright (C) 2017 The LineageOS Open Source Project
# Copyright (C) 2026 ZS551KL port
#
# SPDX-License-Identifier: Apache-2.0
#
# 骨架：OnePlus msm8998-common 的 common.mk（見 ORIGIN.md）+ dumpling 的 device.mk。
# 拿掉的 OnePlus 專屬：OnePlusDoze、IFAA、Pocket mode、Tri-state-key、LiveDisplay、
# librecovery_updater_oneplus、hardware/oneplus、libinit_oneplus、觸控 HAL。
# 先拿掉：ANT+（這台沒有）。NFC 2026-09-28 補回（見下面 NFC 一節）。
# TODO(Z01G)：標記的地方要換成 ASUS 的內容（音訊設定、media profiles、振動…）。

# Add common definitions for Qualcomm
$(call inherit-product, hardware/qcom-caf/common/common.mk)

$(call inherit-product, $(SRC_TARGET_DIR)/product/non_ab_device.mk)

# blob：ASUS 原廠 + 借 OnePlus 5 的 SoC 共通部分（extract-files.py / tools/125、127）
$(call inherit-product, vendor/asus/Z01G/Z01G-vendor.mk)
$(call inherit-product, vendor/asus/Z01G-oneplus/Z01G-oneplus-vendor.mk)

# Setup dalvik vm configs（6 GB RAM；16.0 沒 inherit 這個 -> heap 16m 的教訓）
$(call inherit-product, frameworks/native/build/phone-xhdpi-6144-dalvik-heap.mk)

# Screen（dumpling 是 1080x2160 / xxhdpi；ZS551KL 1080x1920、density 480）
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxhdpi
TARGET_SCREEN_HEIGHT := 1920
TARGET_SCREEN_WIDTH := 1080

PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := true

# ⚠⚠ 一定要強制 VINTF manifest。不強制時 libhidl 的 getRawServiceInternal() **每一次 getService 都先 sleep(1)**
#    （ServiceManagement.cpp 的 "Potential race detected"），而且對 manifest 沒宣告的版本走 legacy 路徑去等。
#    Treble 裝置由 PRODUCT_FULL_TREBLE 順便打開，我們不是 Treble 所以預設沒開。2026-09-25 的症狀：
#    - 整台卡卡的（所有 HIDL 呼叫都被拖一秒）
#    - 藍牙 stack 只等 HAL 500 ms -> 探 @1.1 就超時 abort
#    - RIL 往下探 IRadio 1.6 -> 1.5 -> ...，抓著鎖每步一秒 -> com.android.phone 啟動 ANR、重啟 192 次、SIM 沒反應
#    代價：有註冊但 manifest 沒宣告的 HIDL 服務會找不到（比對過：只剩 secure_element 與指紋 HAL，後者刻意不宣告）
# ⚠ 要設 _OVERRIDE：build/make/core/config.mk 會用 $(PRODUCT_FULL_TREBLE) 把 PRODUCT_ENFORCE_VINTF_MANIFEST
#   直接蓋掉（實測第一次寫成不帶 _OVERRIDE，soong.variables 的 Enforce_vintf_manifest 仍是 false）。
#   這只打開 manifest 強制；PRODUCT_TREBLE_LINKER_NAMESPACES 不動，所以 PRODUCT_FULL_TREBLE 仍是 false
PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE := true

# Overlays
DEVICE_PACKAGE_OVERLAYS += \
    $(LOCAL_PATH)/overlay \
    $(LOCAL_PATH)/overlay-lineage

PRODUCT_ENFORCE_RRO_TARGETS += *

# Evolution X：Updater 的 OTA 清單網址（rro_overlays/EvolutionUpdaterOverlay）。只在 Evolution X 的樹裡裝
ifneq ($(wildcard packages/apps/Updater/app/src/main/java/org/evolution),)
PRODUCT_PACKAGES += Z01GEvolutionUpdaterOverlay
endif

# NFC（NXP PN548 + eSE，kernel 的 nq-nci 驅動、/dev/nq-nci）—— 照 OnePlus 5：HAL 用 LineageOS 原始碼的
# hardware/nxp/nfc/pn8x，不用原廠 QTI 的 NQ HAL（Oreo 的 vendor.nxp.hardware.nfc@1.0）。
# 韌體 libpn548ad_fw.so 與 libnfc-nxp.conf（ASUS 的 libnfc-mtp_default.conf）是 blob（tools/125 的改名安裝）；
# libnfc-nci.conf 是 OnePlus 的通用版。NFC 應用本身是 APEX（com.android.nfcservices），看到下面的 feature 才會啟動
PRODUCT_PACKAGES += \
    android.hardware.nfc@1.2-service \
    com.android.nfc_extras \
    Tag

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/nfc/libnfc-nci.conf:$(TARGET_COPY_OUT_VENDOR)/etc/libnfc-nci.conf \
    frameworks/native/data/etc/android.hardware.nfc.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.xml \
    frameworks/native/data/etc/android.hardware.nfc.hce.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.hce.xml \
    frameworks/native/data/etc/android.hardware.nfc.hcef.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.hcef.xml \
    frameworks/native/data/etc/com.android.nfc_extras.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/com.android.nfc_extras.xml \
    frameworks/native/data/etc/com.nxp.mifare.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/com.nxp.mifare.xml

# Partitions
PRODUCT_PACKAGES += \
    vendor_bt_firmware_mountpoint \
    vendor_dsp_mountpoint \
    vendor_firmware_mnt_mountpoint

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.audio.low_latency.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.audio.low_latency.xml \
    frameworks/native/data/etc/android.hardware.audio.pro.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.audio.pro.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.camera.flash-autofocus.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.flash-autofocus.xml \
    frameworks/native/data/etc/android.hardware.camera.front.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.front.xml \
    frameworks/native/data/etc/android.hardware.camera.full.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.full.xml \
    frameworks/native/data/etc/android.hardware.camera.raw.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.raw.xml \
    frameworks/native/data/etc/android.hardware.fingerprint.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.fingerprint.xml \
    frameworks/native/data/etc/android.hardware.location.gps.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.location.gps.xml \
    frameworks/native/data/etc/android.hardware.opengles.aep.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.opengles.aep.xml \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.assist.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.assist.xml \
    frameworks/native/data/etc/android.hardware.sensor.compass.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.compass.xml \
    frameworks/native/data/etc/android.hardware.sensor.gyroscope.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.gyroscope.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.proximity.xml \
    frameworks/native/data/etc/android.hardware.sensor.stepcounter.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.stepcounter.xml \
    frameworks/native/data/etc/android.hardware.sensor.stepdetector.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.stepdetector.xml \
    frameworks/native/data/etc/android.hardware.telephony.cdma.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.cdma.xml \
    frameworks/native/data/etc/android.hardware.telephony.gsm.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.gsm.xml \
    frameworks/native/data/etc/android.hardware.telephony.ims.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.ims.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.accessory.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.host.xml \
    frameworks/native/data/etc/android.hardware.vulkan.level-0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.level.xml \
    frameworks/native/data/etc/android.hardware.vulkan.version-1_1.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.version.xml \
    frameworks/native/data/etc/android.hardware.vulkan.compute-0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.compute-0.xml \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml \
    frameworks/native/data/etc/android.hardware.wifi.passpoint.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.passpoint.xml \
    frameworks/native/data/etc/android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml \
    frameworks/native/data/etc/android.software.ipsec_tunnels.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.ipsec_tunnels.xml \
    frameworks/native/data/etc/android.software.midi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.midi.xml \
    frameworks/native/data/etc/android.software.opengles.deqp.level-2020-03-01.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.opengles.deqp.level.xml \
    frameworks/native/data/etc/android.software.vulkan.deqp.level-2020-03-01.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.vulkan.deqp.level.xml

# ZS551KL 有 microSD 槽 -> 不設 PRODUCT_CHARACTERISTICS := nosdcard（OnePlus 5 沒有）

# Audio
PRODUCT_PACKAGES += \
    android.hardware.audio@6.0-impl:32 \
    android.hardware.audio.effect@6.0-impl:32 \
    android.hardware.audio.service \
    audio.primary.msm8998 \
    audio.r_submix.default \
    audio.usb.default \
    libaudio-resampler \
    libhdmiedid \
    libhfp \
    libqcompostprocbundle \
    libqcomvisualizer \
    libqcomvoiceprocessing \
    libsndmonitor \
    libspkrprot \
    libssrec \
    libvolumelistener

# policy / volumes / effects / output policy 用 OnePlus 的（配原始碼編的 CAF audio HAL；已有 Earpiece 與
# Telephony —— 16.0「擴音關不掉」的那個缺口不存在）。
# audio_platform_info.xml、graphite_ipc_platform_info.xml、mixer_paths_tasha.xml、ACDB 用 ASUS 的，
# 由 vendor/asus/Z01G 裝（tools/125；mixer_paths 與 ACDB 是改名安裝）
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/audio/audio_effects.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_effects.xml \
    $(LOCAL_PATH)/audio/audio_output_policy.conf:$(TARGET_COPY_OUT_VENDOR)/etc/audio_output_policy.conf \
    $(LOCAL_PATH)/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml \
    $(LOCAL_PATH)/audio/audio_policy_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_volumes.xml

PRODUCT_COPY_FILES += \
    frameworks/av/services/audiopolicy/config/a2dp_in_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/a2dp_in_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/bluetooth_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/r_submix_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/r_submix_audio_policy_configuration.xml

# Bluetooth
PRODUCT_PACKAGES += \
    android.hardware.bluetooth.audio-impl \
    audio.bluetooth.default \
    vendor.qti.hardware.btconfigstore@1.0.vendor \
    vendor.qti.hardware.btconfigstore@2.0.vendor

# Camera
PRODUCT_PACKAGES += \
    android.hardware.camera.provider@2.4-impl:32 \
    android.hardware.camera.provider@2.4-service

# Configstore
PRODUCT_PACKAGES += \
    disable_configstore

# Display
PRODUCT_PACKAGES += \
    android.hardware.graphics.allocator@2.0-impl:64 \
    android.hardware.graphics.allocator@2.0-service \
    android.hardware.graphics.composer@2.1-service \
    android.hardware.graphics.mapper@2.0-impl-2.1 \
    gralloc.msm8998 \
    hwcomposer.qcom \
    libdisplayconfig \
    vendor.qti.hardware.memtrack-service

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/FOSSConfig.xml:$(TARGET_COPY_OUT_VENDOR)/etc/FOSSConfig.xml

# DRM
PRODUCT_PACKAGES += \
    android.hardware.drm-service.clearkey \
    libcrypto_shim.vendor

# Fastbootd
PRODUCT_PACKAGES += \
    fastbootd

# Fingerprint sensor（Goodix gx5206 / gx5216；Home 鍵也靠它 —— HAL 連上 gxFpDaemon 後 daemon 才送 KEY_HOME）
# ⚠ 要配 patches/frameworks/native/0001：ASUS 的 libfp_client.so / fingerprint.gx52*.so（Oreo）把 android::Parcel
#   放在堆疊上、只留 Oreo 的 104 bytes，A15 的 Parcel 是 120 -> 建構子寫出界 -> "stack corruption detected"。
#   那個 patch 把 LP64 Parcel 縮回 104（重排 bool、拿掉沒用的 mReserved）。
#   沒有它的話 HAL 一碰就死，又因為自帶 VINTF 片段被框架無限叫起來：一次開機 ctl.interface_start 14 萬次、
#   log 塞爆 /data、手機發燙（2026-09-25）。tools/135 會檢查 patch 有套上。
# 啟動方式在 init.target.rc（disabled + interface，由 hwservicemanager 在第一次 getService 時啟動）
PRODUCT_PACKAGES += \
    android.hardware.biometrics.fingerprint@2.1-service

# Framework detect
PRODUCT_PACKAGES += \
    libvndfwk_detect_jni.qti \
    libvndfwk_detect_jni.qti.vendor

# Gatekeeper HAL
PRODUCT_PACKAGES += \
    android.hardware.gatekeeper@1.0-impl \
    android.hardware.gatekeeper@1.0-service

# GMS
ifeq ($(WITH_GMS),true)
GMS_MAKEFILE=gms_minimal.mk
endif

# GPS / Location —— 用 ASUS 的整套（16.0 驗證過）：impl、libloc_*、loc_launcher / xtra-daemon / slim_daemon 與
# gps.conf / izat.conf / flp.conf / lowi.conf 都來自 vendor/asus/Z01G（tools/125 的 'GPS': ASUS）。
# OnePlus 的定位堆疊（A10）講的 QMI LOC 比這台的 modem 新，引擎鎖定解不開、一顆衛星都沒有（2026-09-26）。
# ASUS 只有 impl（android.hardware.gnss@1.0-impl-qti.so；16.0 是 system_server passthrough 載入），
# 宿主用 AOSP 的 android.hardware.gnss@1.0-service（registerPassthroughServiceImplementation<IGnss>，
# 依檔名前綴 android.hardware.gnss@1.0-impl 找到 -impl-qti）。⚠ 不要裝 AOSP 的 android.hardware.gnss@1.0-impl
# （它包的是 gps.<board>.so 舊式 HAL，這台沒有）
PRODUCT_PACKAGES += \
    android.hardware.gnss@1.0-service

# Health
PRODUCT_PACKAGES += \
    android.hardware.health@2.1-impl:64 \
    android.hardware.health@2.1-impl.recovery \
    android.hardware.health@2.1-service

# HIDL
PRODUCT_PACKAGES += \
    android.hidl.allocator@1.0.vendor \
    libhidlmemory.vendor:64 \
    libhwbinder \
    libhwbinder.vendor

# Init
PRODUCT_PACKAGES += \
    fstab.qcom \
    fstab.qcom.ramdisk \
    init.devstart.sh \
    init.qcom.rc \
    init.qcom.usb.rc \
    init.radio.sh \
    init.target.rc \
    init.z01g.ssn.sh \
    ueventd.qcom.rc

# bring-up 的 log 管道（init.z01g-debug.rc + z01g-snap.sh：沒有 adb 時把 kmsg / logcat / 狀態快照寫進 /data，
# 在 TWRP 唯讀掛 /data 讀）已於 2026-09-26 移除。開不了機又沒有 adb 時要再加回來（做法見 bring-up 筆記「開機的四道關卡」一節）

# config.fs 的 vendor/ 條目（capabilities）要進 system.img：沒有 vendor 分割區，
# 靠 patches/build/make/0001 讓 fs_config_files_system 保留 vendor/ 條目（tools/136 套）


# IRQ（msm_irqbalance.conf）與 IRSC（sec_config）用 ASUS 的，由 vendor/asus/Z01G 裝：
# 前者配這台的 IRQ 配置，後者是 IPC router 的 QMI 服務權限表（配 ASUS 的 modem 韌體）

# Keymaster
PRODUCT_PACKAGES += \
    android.hardware.keymaster@3.0-impl \
    android.hardware.keymaster@3.0-service

# Keylayout（16.0 的 tools/58 從原廠濾過；goodixfp.kl 刻意不映射 key 192 —— 登錄指紋時驅動每碰一次送一次，
# 映射成 HOME 會把人踢出登錄畫面。gpio-keys.kl 22.2 版改掉 Android 15 已不認得的 WAKE_DROPPED）
# 觸控的 idc / kcm 用 ASUS 原廠的（vendor/asus/Z01G，system/usr/）
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/keylayout/focal-touchscreen.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/focal-touchscreen.kl \
    $(LOCAL_PATH)/keylayout/goodixfp.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/goodixfp.kl \
    $(LOCAL_PATH)/keylayout/gpio-keys.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/gpio-keys.kl

# Lights
PRODUCT_PACKAGES += \
    android.hardware.light-service.lineage

# Lineage Health
PRODUCT_PACKAGES += \
    vendor.lineage.health-service.default

$(call soong_config_set,lineage_health,charging_control_charging_path,/sys/class/power_supply/battery/charging_enabled)

# Media
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/media_codecs.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs.xml \
    $(LOCAL_PATH)/configs/media_codecs_performance.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_performance.xml \
    $(LOCAL_PATH)/configs/media_profiles_V1_0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_V1_0.xml

PRODUCT_COPY_FILES += \
    frameworks/av/media/libstagefright/data/media_codecs_google_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_audio.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_telephony.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_telephony.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_video.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_video.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_video_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_video_le.xml

# Media Extensions
PRODUCT_PACKAGES += \
    libmediametrics \
    libregistermsext \
    mediametrics

# Native Public Libraries
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/public.libraries.txt:$(TARGET_COPY_OUT_VENDOR)/etc/public.libraries.txt

# OMX
PRODUCT_PACKAGES += \
    libc2dcolorconvert \
    libOmxCore \
    libOmxVdec \
    libOmxVenc \
    libstagefrighthw

# Privapp Whitelist
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/system_ext-privapp-permissions-qti.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/privapp-permissions-qti.xml

# Power
PRODUCT_PACKAGES += \
    android.hardware.power-service.lineage-libperfmgr \
    libqti-perfd-client

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/powerhint.json:$(TARGET_COPY_OUT_VENDOR)/etc/powerhint.json \
    system/core/libprocessgroup/profiles/cgroups_28.json:$(TARGET_COPY_OUT_VENDOR)/etc/cgroups.json \
    system/core/libprocessgroup/profiles/task_profiles_28.json:$(TARGET_COPY_OUT_VENDOR)/etc/task_profiles.json

# Protobuf
# libprotobuf-cpp-lite-v29：Widevine（OnePlus 的 libwvhidl）要的 VNDK v29 protobuf，Lineage 的 hardware/lineage/compat
# 本來就有這個不跟 /system 撞名的版本（檔名與 SONAME 都是 -v29）。extract-files.py 把 libwvhidl 的 NEEDED 改過去
# —— vendorcompat 那份裝成 vendor/lib64/libprotobuf-cpp-lite.so，非 Treble 的單一 namespace 永遠先找到 system 的
PRODUCT_PACKAGES += \
    libprotobuf-cpp-full-vendorcompat \
    libprotobuf-cpp-lite-v29

# Properties
PRODUCT_COMPATIBLE_PROPERTY_OVERRIDE := true

# Low power Whitelist
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/qti_whitelist.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/sysconfig/qti_whitelist.xml

# RIL
PRODUCT_PACKAGES += \
    libsysutils.vendor \
    libprotobuf-cpp-lite-3.9.1-vendorcompat

PRODUCT_PACKAGES += \
    CarrierConfigOverlay \
    ims-ext-common \
    ims_ext_common.xml \
    qti-telephony-hidl-wrapper \
    qti_telephony_hidl_wrapper.xml \
    qti-telephony-utils \
    qti_telephony_utils.xml \
    telephony-ext

PRODUCT_BOOT_JARS += \
    telephony-ext

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/qmi_fw.conf:$(TARGET_COPY_OUT_VENDOR)/etc/qmi_fw.conf

# Seccomp policy
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/seccomp_policy/mediacodec-seccomp.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediacodec.policy

# Sensors
PRODUCT_PACKAGES += \
    android.hardware.sensors@1.0-impl:64 \
    android.hardware.sensors@1.0-service

# Shipping API level (for CTS backward compatibility)
PRODUCT_SHIPPING_API_LEVEL := 25

# Soong
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH) \
    hardware/google/interfaces \
    hardware/google/pixel \
    hardware/lineage/interfaces/power-libperfmgr \
    hardware/qcom-caf/common/libqti-perfd-client

# Tetheroffload
PRODUCT_PACKAGES += \
    ipacm \
    IPACM_cfg.xml

# USB
PRODUCT_PACKAGES += \
    android.hardware.usb@1.3-service.dual_role_usb

# Vibrator：ASUS 的 qpnp-haptic 是 timed_output，QTI 的 vibrator 服務只認 LED class / input FF
# -> 自己的 AIDL 服務（vibrator/）
PRODUCT_PACKAGES += \
    android.hardware.vibrator-service.z01g

# Weaver
PRODUCT_PACKAGES += \
    android.hardware.weaver@1.0

# Wifi
PRODUCT_PACKAGES += \
    android.hardware.wifi-service \
    hostapd \
    hostapd_cli \
    libwifi-hal-qcom \
    wificond \
    wpa_supplicant \
    wpa_supplicant.conf \
    TetheringConfigOverlay \
    WifiOverlay

# WiFi firmware symlinks
PRODUCT_PACKAGES += \
    firmware_wlan_mac.bin_symlink \
    firmware_WCNSS_qcom_cfg.ini_symlink \
    firmware_bdwlanc.bin_symlink \
    init.z01g.bdf.sh

# Vulkan 驅動在 /vendor/lib*/hw，非 Treble 的 default namespace 不找 hw/（見 Android.bp）
PRODUCT_PACKAGES += \
    vulkan.msm8998.so_symlink64 \
    vulkan.msm8998.so_symlink32

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/wifi/p2p_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/p2p_supplicant_overlay.conf \
    $(LOCAL_PATH)/wifi/wpa_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant_overlay.conf \
    $(LOCAL_PATH)/wifi/WCNSS_qcom_cfg.ini:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/WCNSS_qcom_cfg.ini

# OTA：LineageOS 的「更新程式」讀這個 JSON（公開 repo main 分支的 ota/Z01G.json；zip 在 GitHub Releases）。
# 欄位規則（packages/apps/Updater）：version = ro.lineage.build.version、romtype = ro.lineage.releasetype、
# datetime 要大於 ro.build.date.utc 才算新版。安裝時由 LineageOS Recovery 以 otacerts（發布用私鑰）驗簽
PRODUCT_SYSTEM_PROPERTIES += \
    lineage.updater.uri=https://raw.githubusercontent.com/peng16384/android_device_asus_Z01G/main/ota/Z01G.json
