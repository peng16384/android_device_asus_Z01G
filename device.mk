#
# Copyright (C) 2026 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ASUS ZenFone 4 Pro (ZS551KL / Z01G) — 骨架，尚未編譯驗證

DEVICE_PATH := device/asus/Z01G

# ---------------------------------------------------------------------------
# Dalvik / ART heap
#
# ############ 2026-09-23：一直都缺，裝了 GApps 才爆出來 ############
# 在這之前整棵樹沒有任何 dalvik.vm.heap* 設定（getprop 完全是空的）。
# AndroidRuntime.cpp 的 fallback 是：
#     parseRuntimeOption("dalvik.vm.heapsize", heapsizeOptsBuf, "-Xmx", "16m");
# 也就是 **system_server 與所有 App 都跑在 16 MB 的 heap 上**。
#
# 沒 GApps 時勉強撐得住，裝完 Open GApps nano（多一百多個套件）之後，
# system_server 在 StartPackageManagerService 階段直接：
#     E AndroidRuntime: *** FATAL EXCEPTION IN SYSTEM PROCESS: main
#     java.lang.OutOfMemoryError: OutOfMemoryError thrown while trying to
#     throw OutOfMemoryError; no stack trace available
# 然後無限重啟（實測 14 分鐘內重跑了 25 次）。
#
# 本機 MemTotal = 5,863,800 kB -> 6 GB 這一檔。
# （參考樹 shakalaca/Z01G 用的是 2048 那份 —— 同一台機器但顯然是沿用範本，
#  heapsize 同樣是 512m，差別在 growthlimit 192m vs 256m 與 GC 參數。）
# ####################################################################
# ---------------------------------------------------------------------------
$(call inherit-product, frameworks/native/build/phone-xhdpi-6144-dalvik-heap.mk)

# ---------------------------------------------------------------------------
# 非 Treble：blobs 都在 /system/vendor，HAL 走 passthrough 為主
# ---------------------------------------------------------------------------
PRODUCT_ENFORCE_RRO_TARGETS := *

# ---------------------------------------------------------------------------
# Oreo vendor blob 在 Pie 上需要的 HIDL 函式庫
#
# Android 9 不再預設安裝 android.hidl.base@1.0 / android.hidl.manager@1.0，
# 但 Oreo 編出來的 vendor 二進位檔全部連結它們。實測（tools/36_check_blob_deps.py）
# 有 144 個 blob 需要 android.hidl.base@1.0，結果是每一個 vendor HAL 都：
#   F linker: CANNOT LINK EXECUTABLE "...": library "android.hidl.base@1.0.so" not found
#   init: Service 'vendor.keymaster-3-0' ... exited with status 1   （重啟 191 次）
# 連帶 system_server 起不來、畫面停在開機 logo。
#
# 原本想用 PRODUCT_PACKAGES 從 AOSP 原始碼建，但**建不出來而且不會報錯**。
# 查 system/libhidl/transport/base/1.0/Android.bp：
#     hidl_interface { name: "android.hidl.base@1.0", core_interface: true, ... }
# core_interface: true 表示 Android 9 已經把它併進 libhidlbase，
# 不再產生獨立的 .so —— 這正是 Oreo blob 找不到它的根本原因。
# 所以改成收原廠 blob（LineageOS 各家舊機 device tree 也是這樣做），
# 見 tools/31_build_blob_list.py 的 EXTRA_SYSTEM_LIBS。
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 螢幕密度（1080x2160，6.0" AMOLED）
# ---------------------------------------------------------------------------
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxhdpi
PRODUCT_CHARACTERISTICS := nosdcard

# ---------------------------------------------------------------------------
# Overlay
# ---------------------------------------------------------------------------
DEVICE_PACKAGE_OVERLAYS += $(DEVICE_PATH)/overlay

# ---------------------------------------------------------------------------
# rootdir（fstab 與 init rc）
#
# 這台需要「兩份」fstab，各自被不同的東西讀：
#
#   /fstab.qcom（ramdisk 根目錄，由 rootdir/Android.mk 安裝）
#       Android 9 的 first-stage init 用它掛 /system。
#
#   /vendor/etc/fstab.qcom（下面的 PRODUCT_COPY_FILES）
#       ASUS 的 init.target.rc 第 50 行寫死：
#           on fs
#               mount_all /vendor/etc/fstab.qcom
#       /data、/cache、/persist、/firmware 全是這條掛起來的。
#
# 踩過的坑：只改 ramdisk 那份完全沒有效果 —— /data 的掛載參數
# （forceencrypt vs encryptable）是由 /vendor/etc/ 那份決定的。
# 原廠的 vendor/etc/fstab.qcom 已從 proprietary-files.txt 排除，否則會蓋掉這份。
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    fstab.qcom

# 注意：來源是 fstab.qcom.vendor 而不是 fstab.qcom —— 兩份內容「必須不同」。
#   ramdisk 的 /fstab.qcom          要有 /system（first-stage 掛載用）
#   /vendor/etc/fstab.qcom          不能有 /system（否則 fs_mgr 對已掛載的
#                                   分割區跑 e2fsck 失敗，整個 mount_all 回傳錯誤，
#                                   nonencrypted 事件不送出，zygote 永遠不啟動）
# 詳見 fstab.qcom.vendor 檔頭的說明。
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/rootdir/etc/fstab.qcom.vendor:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.qcom

# bring-up 除錯用的 init.z01g-debug.rc 已於 2026-09-23 移除。
#
# 它跑三個永久 service：cat /dev/kmsg、logcat、以及每 15 秒一次的
# `getprop | grep ...; ps -A` 快照，全部寫到 /data。
# 當初是為了「開不了機又沒有 adb」的情境（那時沒有 CONFIG_PSTORE，
# 重開機就拿不到上一次的 kernel log），但現在 adb 第 14 秒就上線、
# 開機也穩定，它只剩下副作用：
#   - getprop 不帶參數會讀 **所有** property 檔，permissive 下每 15 秒
#     產生一整批 AVC denial（實測 515 次 comm="getprop"，佔了
#     qti_init_shell 那 68 個唯一 denial 組合的絕大部分）
#   - 持續佔 CPU 與寫入 /data
# 寫 sepolicy 時這些雜訊會嚴重干擾判斷，所以先拿掉。
# 真的需要時 git 歷史裡找得回來（rootdir/etc/init.z01g-debug.rc）。

# ---------------------------------------------------------------------------
# Audio
#
# 用 AOSP 9 的 audio HAL service 與 impl，硬體實作沿用原廠的
# vendor/lib*/hw/audio.primary.msm8998.so（走 libhardware 傳統介面）。
#
# 為什麼不沿用原廠的 service/impl：
#   原廠 /vendor/bin/hw/android.hardware.audio@2.0-service 與
#   android.hardware.audio@2.0-impl.so 的 DT_NEEDED 全是 AOSP 函式庫
#   （libhardware / android.hardware.audio@2.0.so / ...），沒有任何 QTI 擴充，
#   等於就是 AOSP 版，沒有留著 Oreo 版的理由。
#
# 這一段是第二輪開機失敗（卡在開機動畫 27 分鐘）的根因：
#   原廠 service 的執行檔有收進來，但它的 .rc 被 blob 清單的 EXCLUDE_PATTERNS
#   排掉了 -> init 完全沒有這個服務 -> 沒人註冊 IDevicesFactory
#   -> audioserver 卡在 AudioFlinger 建構子的 getService()（實測等了 873 秒）
#   -> media.audio_flinger 沒註冊 -> system_server 卡住 -> 開機動畫無限播。
#   「執行檔在、服務定義不在」在編譯期完全不會報錯，只會安靜地卡開機。
#   改用 AOSP 模組後 .rc 由模組自己帶，不會再錯位；
#   另外寫了 tools/40_check_services.sh 專門檢查這種錯位。
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    android.hardware.audio@2.0-service \
    android.hardware.audio@2.0-impl \
    android.hardware.audio.effect@2.0-impl \
    tinymix

# 音量曲線表：原廠那份有 AOSP 不認識的 DEVICE_CATEGORY_HEADSET_nonEU，
# 一條解析失敗就讓整組曲線註冊不起來 -> STREAM_MUSIC Muted:true、索引卡 0
# -> 音量鍵與設定裡的滑桿全部無效。這裡裝剔除過的版本，
# 原廠那份已在 tools/31_build_blob_list.py 的 EXCLUDE_EXACT 排除。
# 重新產生：tools/91_strip_noneu_volumes.py
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/configs/audio/audio_policy_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_volumes.xml

# 錄影 profile：原廠那份有這顆相機正確的解析度與位元率，但用了 8 個
# AOSP 9 沒定義的 camcorder quality，直接指過去會讓 zygote 在 preload
# 階段 SIGABRT（MediaProfiles 的 CHECK 不是警告，是 abort）。
# 這裡裝剔除過的版本，原廠那份已在 tools/31 的 EXCLUDE_EXACT 排除。
# 重新產生：tools/93_sanitize_media_profiles.py
# 搭配 system.prop 的 media.settings.xml 才會生效。
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/configs/media/media_profiles_vendor.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_vendor.xml

# ---------------------------------------------------------------------------
# 其他改用 AOSP 版的 HAL
#
# 這幾個原廠 blob 都是「Oreo 執行檔 + Pie 函式庫」symbol 對不上，
# init 無限 restart（實測各 325 次），已從 proprietary-files.txt 排除：
#   wifi@1.0-service       缺 android::wifi_system::InterfaceTool 的 vtable
#   media.omx@1.0-service  缺 OmxStore 的無參數建構子
#   keymaster@3.0-service  impl.so 要 Oreo 版 SoftKeymasterContext::ParseKeyBlob，
#                          但 libsoftkeymasterdevice.so 不能換成 Oreo 的
#                          —— Pie 的 /system/bin/keystore 也連著它
#
# wifi / keymaster 的 AOSP 模組本來就有被建出來（.rc 已經安裝），
# 只是執行檔被 blob 蓋掉；這裡明確列出，避免之後變成有 .rc 沒執行檔。
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    android.hardware.wifi@1.0-service \
    android.hardware.keymaster@3.0-service \
    android.hardware.keymaster@3.0-impl \
    android.hardware.media.omx@1.0-service

# ---------------------------------------------------------------------------
# Bluetooth
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Camera
#   sensor：IMX362（主）/ IMX351（望遠）/ IMX319（前）
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    libgui_vendor \
    Snap

# ---------------------------------------------------------------------------
# Display
#   面板：Raydium RM67198 1080p command mode（單 DSI）
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    libtinyxml \
    libvulkan

# ---------------------------------------------------------------------------
# DRM
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Fingerprint
#   Goodix gx5206 / gx5216（不是參考機用的那顆）
#
#   指紋 HAL service 用 ASUS 的 blob（vendor/bin/hw/...@2.1-service），不加 AOSP 版：
#   ASUS 版直接載入 fingerprint.gx5206.so / gx5216.so，AOSP 版找的是
#   fingerprint.<ro.hardware>.so，名字對不上。兩邊都放的話同一個輸出路徑會被
#   blob 蓋掉原始碼（m nothing 會警告 overriding commands for target）。
#   若之後指紋不動，可以改成加回 AOSP 版、並把 blob 從 proprietary-files.txt 移除。
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Gatekeeper / Keymaster
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# GPS
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Health / Power / Thermal / Light / USB / Vibrator
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Media
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    libavservices_minijail_vendor

# ---------------------------------------------------------------------------
# Sensors
#   ASUS Proximitysensor / ASUS Lightsensor（走 ASUS 自己的 HAL）
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Wifi
#   注意：ASUS GPL kernel 原始碼不含 qcacld，要另外補進 kernel/asus/msm8998
#
#   不加 wpa_supplicant.conf —— 原廠那份（vendor/etc/wifi/wpa_supplicant.conf）
#   比較貼近這台的硬體，從 blob 走。兩邊都放會互相覆蓋。
#
#   但 p2p_supplicant.conf 必須自己補：原廠 /vendor/etc/wifi 裡根本沒有那一份
#   （Oreo 是由框架生成並複製到 /data/misc/wifi 的，Android 9 不再做），
#   而 ASUS 的 init.qcom.rc 的 wpa_supplicant 服務硬性用 -c 指定它，
#   找不到就整個退出 -> SupplicantStaIfaceHal: Failed to get ISupplicant。
#   實際的複製動作在 rootdir/etc/init.z01g.rc 的 on post-fs-data。
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/wifi/p2p_supplicant.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/p2p_supplicant.conf

PRODUCT_PACKAGES += \
    libwpa_client \
    wificond

# ---------------------------------------------------------------------------
# RIL
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    librmnetctl \
    libxml2

# 不要設 PRODUCT_BOOT_JARS += qcnvitems qcrilhook ——
#   qcnvitems 這台根本沒出貨（映像裡只有 qcrilhook.jar），加了會讓 ninja 報
#     error: .../JAVA_LIBRARIES/qcnvitems_intermediates/javalib.jar,
#            needed by .../dex_bootjars/system/framework/boot.prof, missing
#   qcrilhook 則是靠 etc/permissions/qcrilhook.xml 宣告成 shared library
#     <library name="com.qualcomm.qcrilhook" file="/system/framework/qcrilhook.jar"/>
#     不是 boot jar。
#   參考機（xiaomi/oneplus msm8998-common）的 PRODUCT_BOOT_JARS 放的是
#   telephony-ext / WfdCommon / org.ifaa.android.manager，跟這兩個無關。

# ---------------------------------------------------------------------------
# 硬體功能宣告（permissions XML）
#   依本機實際硬體挑選：NFC 是 NXP、有指紋、有雙鏡頭、無 WiGig
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.audio.low_latency.xml:system/etc/permissions/android.hardware.audio.low_latency.xml \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:system/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:system/etc/permissions/android.hardware.bluetooth_le.xml \
    frameworks/native/data/etc/android.hardware.camera.flash-autofocus.xml:system/etc/permissions/android.hardware.camera.flash-autofocus.xml \
    frameworks/native/data/etc/android.hardware.camera.front.xml:system/etc/permissions/android.hardware.camera.front.xml \
    frameworks/native/data/etc/android.hardware.camera.full.xml:system/etc/permissions/android.hardware.camera.full.xml \
    frameworks/native/data/etc/android.hardware.camera.raw.xml:system/etc/permissions/android.hardware.camera.raw.xml \
    frameworks/native/data/etc/android.hardware.fingerprint.xml:system/etc/permissions/android.hardware.fingerprint.xml \
    frameworks/native/data/etc/android.hardware.location.gps.xml:system/etc/permissions/android.hardware.location.gps.xml \
    frameworks/native/data/etc/android.hardware.nfc.xml:system/etc/permissions/android.hardware.nfc.xml \
    frameworks/native/data/etc/android.hardware.nfc.hce.xml:system/etc/permissions/android.hardware.nfc.hce.xml \
    frameworks/native/data/etc/android.hardware.opengles.aep.xml:system/etc/permissions/android.hardware.opengles.aep.xml \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:system/etc/permissions/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.compass.xml:system/etc/permissions/android.hardware.sensor.compass.xml \
    frameworks/native/data/etc/android.hardware.sensor.gyroscope.xml:system/etc/permissions/android.hardware.sensor.gyroscope.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:system/etc/permissions/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:system/etc/permissions/android.hardware.sensor.proximity.xml \
    frameworks/native/data/etc/android.hardware.sensor.stepcounter.xml:system/etc/permissions/android.hardware.sensor.stepcounter.xml \
    frameworks/native/data/etc/android.hardware.sensor.stepdetector.xml:system/etc/permissions/android.hardware.sensor.stepdetector.xml \
    frameworks/native/data/etc/android.hardware.telephony.gsm.xml:system/etc/permissions/android.hardware.telephony.gsm.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:system/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:system/etc/permissions/android.hardware.usb.accessory.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:system/etc/permissions/android.hardware.usb.host.xml \
    frameworks/native/data/etc/android.hardware.vulkan.level-0.xml:system/etc/permissions/android.hardware.vulkan.level-0.xml \
    frameworks/native/data/etc/android.hardware.vulkan.version-1_0_3.xml:system/etc/permissions/android.hardware.vulkan.version-1_0_3.xml \
    frameworks/native/data/etc/android.hardware.wifi.xml:system/etc/permissions/android.hardware.wifi.xml \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:system/etc/permissions/android.hardware.wifi.direct.xml \
    frameworks/native/data/etc/android.software.midi.xml:system/etc/permissions/android.software.midi.xml \
    frameworks/native/data/etc/android.software.sip.voip.xml:system/etc/permissions/android.software.sip.voip.xml \
    frameworks/native/data/etc/handheld_core_hardware.xml:system/etc/permissions/handheld_core_hardware.xml

# ---------------------------------------------------------------------------
# 從原廠抽出來的設定檔（TODO：還沒放進 configs/）
#   audio_policy / mixer_paths / media_codecs / thermal-engine.conf /
#   gps.conf / izat.conf / sensors 相關
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 導航鍵 / 實體鍵的 keylayout
#
# 第一次成功開機後實測：返回鍵正常，Home 與多工鍵沒反應。
# 原因是 /system/usr/keylayout/{focal-touchscreen,goodixfp,gpio-keys}.kl
# 整組沒被收進來（system 側的漏法，跟 SmartcardService 缺 jar 同一類）。
# 沒有專屬 .kl 就退回 AOSP 的 Generic.kl：
#   返回  focal-touchscreen key 158 -> Generic 有 BACK        => 正常
#   多工  focal-touchscreen key 139 -> Generic 是 MENU        => 沒反應
#   Home  goodixfp key 187~193（KEY_F17~）-> Generic 沒有      => 沒反應
#         （這台的指紋辨識器就是 Home 鍵）
#
# 不能直接抄原廠的 .kl：裡面有 ASUS 自己加在 framework 的 keycode 標籤
# （GESTURE_DOUBLE_CLICK / GESTURE_W / FINGERPRINT_EARLYWAKEUP ...），
# KeyLayoutMap.cpp 的 parseKey() 遇到不認得的標籤會 return BAD_VALUE，
# **整個檔案作廢**又退回 Generic。所以改放在 device tree，
# 由 tools/58_gen_keylayout.py 從原廠映像濾過之後產生。
#
# 另外兩個是純設定、沒有 keycode 標籤，直接從 blob 收：
#   usr/idc/focal-touchscreen.idc     觸控參數
#   usr/keychars/focal-touchscreen.kcm
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/keylayout/focal-touchscreen.kl:system/usr/keylayout/focal-touchscreen.kl \
    $(DEVICE_PATH)/keylayout/goodixfp.kl:system/usr/keylayout/goodixfp.kl \
    $(DEVICE_PATH)/keylayout/gpio-keys.kl:system/usr/keylayout/gpio-keys.kl

# ---------------------------------------------------------------------------
# 指紋 HAL 的 init rc（改自原廠，補上 interface 宣告並拿掉 disabled）
#
# 原廠那份的 fps_hal 是 disabled 而且沒有 interface 宣告
# （interface 這個 init 關鍵字是 Android 8.1 才加的，ASUS 停在 8.0），
# 又沒有任何地方會去 start 它 —— 在 Pie 上永遠不會啟動：
#   init: Could not find service hosting interface
#         android.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint/default
#
# 連帶 Home 鍵也不會動：這台的 Home 鍵就是指紋辨識器（goodixfp），
# goodix 驅動要等指紋 daemon 透過 ioctl 切到按鍵模式才會回報 KEY_HOME。
# 實測 getevent：按 Home 完全沒有任何 input event，
# 而同樣在 focal-touchscreen 上的 BACK / APP_SWITCH 都正常。
#
# 詳細說明在 rootdir/etc/android.hardware.biometrics.fingerprint@2.1-service.rc 檔頭。
# 原廠那份已從 proprietary-files.txt 排除，否則會蓋掉這一份。
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/rootdir/etc/android.hardware.biometrics.fingerprint@2.1-service.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc

# ---------------------------------------------------------------------------
# 裝置專屬 init
#
# ASUS 把裝置專屬的 init 放在 **boot ramdisk** 裡（init.asus.rc 等三個檔），
# 不是 /system/vendor/etc/init。我們的 ramdisk 是 AOSP 產的，所以那 43 KB
# 從來沒被帶過來 —— 裡面有 /dev/goodix_fp 等裝置節點的權限設定，
# 以及 fpseek / gx_fpd / fpservice 這條指紋啟動鏈。
# 缺了它 /dev/goodix_fp 是 root:root 0600，而 fps_hal 跑在 user system，
# 打不開 -> openHal 失敗 -> Settings 裡沒有指紋、Home 鍵也沒反應。
#
# 原廠那份已抽出存在 work/stock_ramdisk/ 供比對
# （tools/64_stock_ramdisk_probe.sh 產生）。只搬真正需要的部分，
# 詳見 rootdir/etc/init.z01g.rc 的檔頭。
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/rootdir/etc/init.z01g.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.z01g.rc

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# IMS / VoLTE —— org.codeaurora.ims
#
# 原廠 /system/app/ims/ims.apk 是 odex 的（apk 內沒有 classes.dex），
# 而且是對 Oreo 的 IMS API 編的，Pie 把那套整組搬到了
# android.telephony.ims.compat.*。所以這三個檔不是從 blob 清單來，
# 是由 tools/101_build_ims_apk.sh 從原廠映像重做：
#     vdexExtractor -f 還原 quicken 過的 dex
#     -> baksmali -> tools/99 改類別參照 -> smali
#     -> tools/100 把 manifest 的 intent action 換成 compat 版
#     -> 用 platform key 重簽（sharedUserId=android.uid.phone，簽名要相符）
#
# 搭配的設定在另外兩個地方，缺一不可：
#     overlay 的 config_ims_package + config_dynamic_bind_ims
#     system.prop 的 persist.dbg.*_avail_ovr 那幾條
#
# 那個 .jar 是 apk 的 uses-library（com.qti.vzw.ims.internal）宣告的，
# 沒有它 PackageManager 會直接拒裝；permissions xml 指定它要放在
# /system/vendor/framework/ 底下。
#
# ⚠ prebuilt/ims/ 在 .gitignore 裡。換機器或重新 clone 之後要先跑那支腳本，
#   否則這裡會因為找不到檔案而編譯失敗（這是刻意的，寧可大聲壞掉）。
# ---------------------------------------------------------------------------
# apk 走 prebuilt/Android.mk 的 BUILD_PREBUILT —— AOSP 明文擋掉 apk 進
# PRODUCT_COPY_FILES（build/make/core/Makefile:28）。
PRODUCT_PACKAGES += ims

PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/prebuilt/ims/qti-vzw-ims-internal.jar:$(TARGET_COPY_OUT_VENDOR)/framework/qti-vzw-ims-internal.jar \
    $(DEVICE_PATH)/prebuilt/ims/qti-vzw-ims-internal.xml:system/etc/permissions/qti-vzw-ims-internal.xml

# ---------------------------------------------------------------------------
# audio_policy_configuration.xml —— 補過 attachedDevices 的版本
#
# 原廠那份（/vendor/etc/）其實是 AOSP 的通用範本，ASUS 留在樹裡沒用過
#（它實際讀的是優先權更高的 /vendor/etc/audio/，而那份我們為了修藍牙排除了）。
# 樣板的 attachedDevices 沒有 Earpiece -> 框架認為這台沒有聽筒 ->
# Telecom 把聽筒路由整個停用 -> 通話中擴音關不掉。
#
# 重新產生：tools/104_patch_audio_policy.py（只加 3 行，會驗 XML）
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/configs/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml

# init.qcom.rc —— 補過 group 的版本（原廠那份已從 blob 清單排除）
#
# ASUS 那份的 qcom-sh 與 qcom-post-boot 只有 `user root`、沒有 group 行，
# 於是 gid 0 + 零個附加群組，碰不到 radio / system / wakelock 擁有的節點。
# enforcing 下那些存取要 CAP_DAC_OVERRIDE，而 qti_init_shell 不在 AOSP 的
# dac_override_allowed 裡（上游 qcom 也沒把它加進去）。
# 實測：/data/vendor/radio/copy_complete 停在 0 —— QCRIL 等的就是這個旗標
#（libril-qc-qmi-1.so 裡有這個字串）。
#
# 補的三行（前兩行照 LineageOS 16.0 的 OnePlus msm8998 樹，第三行是我們加的）：
#     qcom-sh         group root system radio
#     qcom-post-boot  group root system wakelock graphics
#     post-fs-data    chmod 0640 /data/vendor/radio/ver_info.txt
#
# 重新產生：tools/97_patch_qcom_init_rc.py（會逐行驗證只多了那三行）
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/rootdir/vendor/etc/init/hw/init.qcom.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.qcom.rc

# ---------------------------------------------------------------------------
# Shim 函式庫（掛法在 BoardConfig.mk 的 TARGET_LD_SHIM_LIBS）
#
# libshim_keymaster：補一個 Oreo mangled name 給 libkeymaster1.so，
# 否則 gxFpDaemon（指紋 daemon / Home 鍵來源）與 fingerprint.gx52*.so
# 都會 CANNOT LINK EXECUTABLE。詳見 libshims/keymaster_compat.cpp。
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    libshim_keymaster

# ---------------------------------------------------------------------------
# priv-app 權限白名單
#
# Android 9 把 ro.control_privapp_permissions 預設改成 enforce：
# /system/priv-app 底下每個 app 用到的 signature|privileged 權限都必須列在
# 白名單 XML 裡，少一條 PermissionManagerService.systemReady() 就丟
#     java.lang.IllegalStateException: Signature|privileged permissions
#     not in privapp-permissions whitelist: {...}
# -> system_server 死 -> zygote 偵測到子行程終止後 kill(getpid(), SIGKILL) 自盡
# -> init 重啟 zygote/audioserver/cameraserver/media/netd/wificond
# 實測週期 126 秒，畫面一直停在開機動畫。
#
# 這台缺的四條（dropbox 的 system_server_crash 一次列全）：
#   com.quicinc.cne.CNEService    INTERACT_ACROSS_USERS / PACKET_KEEPALIVE_OFFLOAD
#   com.qualcomm.qcrilmsgtunnel   INTERACT_ACROSS_USERS
#   com.qualcomm.location         CONTROL_LOCATION_UPDATES
#
# 裝到 /system/etc/permissions（不是 /vendor/etc）—— 這三個 app 都在
# /system/priv-app，PermissionManagerService 對非 vendor 的 app 只查前者。
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/permissions/privapp-permissions-qti.xml:system/etc/permissions/privapp-permissions-qti.xml

# ---------------------------------------------------------------------------
# USB / adb
#
# LineageOS 底下 USB 完全不列舉、adb 永遠連不上，根因在 /default.prop：
#     persist.sys.usb.config=none
# 這是 build/make/tools/post_process_props.py 的 fallback ——
# 沒有人指定值時它就填 none。開機時 init 走：
#     init: processing action (persist.sys.usb.config=* && boot) from (/init.usb.rc:102)
#       -> setprop sys.usb.config none
#     init: processing action (sys.usb.config=none && sys.usb.configfs=1)
#       -> write /config/usb_gadget/g1/UDC none   （gadget 從頭到尾沒被綁定）
# 所以 USB 根本沒被啟用，不是 adbd 的問題。
#
# 另外兩個看起來很嚇人但其實無害的訊息（原廠 Oreo 也一樣）：
#   init: Command 'mount configfs none /config' ... failed: Device or resource busy
#       AOSP 的 init.rc 已經掛過了，ASUS 的 rc 再掛一次而已。
#   init: Command 'write .../serialnumber ${ro.serialno}' ... cannot expand
#       這台的 bootloader 不傳 androidboot.serialno（實測 cmdline 裡沒有），
#       所以 ro.serialno 是空的。init 只會跳過這一行，其餘照跑。
# ---------------------------------------------------------------------------
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    persist.sys.usb.config=adb

# ---------------------------------------------------------------------------
# Inherit from proprietary blobs（由 setup-makefiles.sh 產生）
# ---------------------------------------------------------------------------
$(call inherit-product-if-exists, vendor/asus/Z01G/Z01G-vendor.mk)
