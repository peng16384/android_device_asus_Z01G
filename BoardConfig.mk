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
# ASUS ZenFone 4 Pro (ZS551KL) — codename Z01G / Z01GD，msm8998，A-only，非 Treble
#
# 骨架來自 LineageOS/android_device_xiaomi_msm8998-common (lineage-16.0)。
# 板級參數以 shakalaca/android_device_asus_Z01G 與本機實測為準。

BOARD_VENDOR := asus

DEVICE_PATH := device/asus/Z01G

TARGET_SPECIFIC_HEADER_PATH := $(DEVICE_PATH)/include

# ---------------------------------------------------------------------------
# Architecture
#   msm8998 = Kryo 280（A73 + A53）。參考樹用 cortex-a73，沿用之。
# ---------------------------------------------------------------------------
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a73

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a73

# ---------------------------------------------------------------------------
# Bootloader / Platform
# ---------------------------------------------------------------------------
TARGET_BOOTLOADER_BOARD_NAME := msm8998
TARGET_NO_BOOTLOADER := true
TARGET_BOARD_PLATFORM := msm8998
TARGET_BOARD_PLATFORM_GPU := qcom-adreno540

# ---------------------------------------------------------------------------
# Kernel
#
# BOARD_KERNEL_BASE 是 0x00000000 而非一般 qcom 的 0x80000000。
# 兩個獨立來源印證：
#   1) 拆原廠 boot.img header：kernel_addr=0x00008000、tags_addr=0x00000100、
#      ramdisk_addr=0x01000000、second_addr=0x00f00000
#   2) shakalaca/android_device_asus_Z01G/BoardConfig.mk 同樣寫 0x00000000
#
# cmdline 用原廠 boot header 內的那份（其餘由 bootloader 追加）。
# 注意：原廠會追加 androidboot.veritymode=enforcing 與 dm="system ... android-verity"，
#       LineageOS 自簽不做 verity，不要自己加回去。
# ---------------------------------------------------------------------------
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_RAMDISK_OFFSET := 0x01000000
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb
BOARD_MKBOOTIMG_ARGS := --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 --second_offset 0x00f00000

# ---------------------------------------------------------------------------
# ramdisk 根目錄要多建的掛載點
#
# 這幾個目錄原本是 init.qcom.rc / init.z01g.rc 在執行期 mkdir 出來的，
# 而那些 rc 在 /vendor/etc/init/ 底下 → init 以 **vendor_init** 的身分執行它們。
# init 的 mkdir 會先照 file_contexts 設好 fscreate context 再建目錄，於是
# /firmware 是以 firmware_file 這個型別被建立的 —— 但那是 contextmount_type
# （靠 mount 的 context= 標記整個檔案系統），AOSP 有：
#
#     domain.te:511  neverallow * contextmount_type:dir_file_class_set
#                        { create write setattr relabelfrom relabelto ... };
#
# **連 init 自己都不准建**。也就是說掛載點必須在 ramdisk 裡就存在。
# Treble 裝置本來就是這樣（AOSP 的 generic_arm64_ab BoardConfig 也這樣寫）。
#
# 目錄存在的話 init 的 mkdir 會拿到 EEXIST 而不進行建立，SELinux 的
# create 檢查根本不會發生，後面的 chown/chmod 只碰 rootfs 型別。
#
# ⚠ 這是切 enforcing 的必要條件：建不出 /firmware 就掛不上 modem 分割，
#   ADSP 會回到那個 -60，連帶沒聲音沒相機。
BOARD_ROOT_EXTRA_FOLDERS += firmware bt_firmware dsp persist asusfw

BOARD_KERNEL_CMDLINE := console=ttyMSM0,115200,n8 androidboot.console=ttyMSM0
BOARD_KERNEL_CMDLINE += earlycon=msm_serial_dm,0xc1b0000 androidboot.hardware=qcom
BOARD_KERNEL_CMDLINE += user_debug=31 msm_rtb.filter=0x37 ehci-hcd.park=3
BOARD_KERNEL_CMDLINE += lpm_levels.sleep_disabled=1 sched_enable_hmp=1
BOARD_KERNEL_CMDLINE += sched_enable_power_aware=1 service_locator.enable=1
BOARD_KERNEL_CMDLINE += swiotlb=2048 androidboot.configfs=true
BOARD_KERNEL_CMDLINE += androidboot.usbcontroller=a800000.dwc3
# bring-up 階段先跑 permissive —— device tree 還沒有自己的 sepolicy，
# enforcing 下的 denial 會擋掉一堆東西而且不容易從外部觀察。
# 能穩定開機、sepolicy 補齊之後再拿掉這行。
# （同機種的 shakalaca/android_device_asus_Z01G 也是這樣設。）
# SELinux：2026-09-24 切成 enforcing。
#
# 十輪政策迭代之後（85 -> 0 條 denial），加上執行期 setenforce 1 實測
# （Wi-Fi 斷線重連、藍牙、飛航模式、相機、聲音、指紋登錄與解鎖都過，
#  permissive=0 的 denial 是 0）才切。
#
# 回復方式（10 秒，不動 /system）：
#     fastboot flash boot work\out\boot-permissive-rollback.img
# sepolicy / *_file_contexts / *_property_contexts 全都在 ramdisk 裡，
# 所以純 SELinux 的變更只要刷 boot.img，不必走 TWRP 刷整包。
BOARD_KERNEL_CMDLINE += androidboot.selinux=enforcing

TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_KERNEL_CONFIG := zs551kl-perf_defconfig
TARGET_KERNEL_SOURCE := kernel/asus/msm8998
TARGET_KERNEL_CROSS_COMPILE_PREFIX := aarch64-linux-android-

# ---------------------------------------------------------------------------
# Partitions（來源：fastboot getvar all + /proc/partitions）
#
#   boot     sde11  32 MiB
#   recovery sda15  32 MiB
#   system   sda19   5 GiB   ← 非 Treble，vendor 在 /system/vendor 底下
#   cache    sda18 128 MiB
#   userdata sda20  0xD56C2F000
#
# 沒有 vendor 分割 -> 不設 BOARD_VENDORIMAGE_*。
# ---------------------------------------------------------------------------
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 5368709120
BOARD_CACHEIMAGE_PARTITION_SIZE := 134217728
BOARD_USERDATAIMAGE_PARTITION_SIZE := 57290190848
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_FLASH_BLOCK_SIZE := 262144 # (BOARD_KERNEL_PAGESIZE * 64)

TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# 非 Treble：vendor 就是 /system/vendor
TARGET_COPY_OUT_VENDOR := system/vendor

# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------
BOARD_USES_ALSA_AUDIO := true
BOARD_SUPPORTS_SOUND_TRIGGER := true

AUDIO_FEATURE_ENABLED_COMPRESS_VOIP := true
AUDIO_FEATURE_ENABLED_EXTN_FORMATS := true
AUDIO_FEATURE_ENABLED_EXTN_FLAC_DECODER := true
AUDIO_FEATURE_ENABLED_FM_POWER_OPT := true
AUDIO_FEATURE_ENABLED_HDMI_SPK := true
AUDIO_FEATURE_ENABLED_PCM_OFFLOAD := true
AUDIO_FEATURE_ENABLED_PCM_OFFLOAD_24 := true
AUDIO_FEATURE_ENABLED_FLAC_OFFLOAD := true
AUDIO_FEATURE_ENABLED_VORBIS_OFFLOAD := true
AUDIO_FEATURE_ENABLED_APE_OFFLOAD := true
AUDIO_FEATURE_ENABLED_AAC_ADTS_OFFLOAD := true
AUDIO_FEATURE_ENABLED_PROXY_DEVICE := true
AUDIO_FEATURE_ENABLED_AUDIOSPHERE := true
AUDIO_FEATURE_ENABLED_USB_TUNNEL_AUDIO := true
AUDIO_FEATURE_ENABLED_VBAT_MONITOR := true
AUDIO_FEATURE_ENABLED_ANC_HEADSET := true
AUDIO_FEATURE_ENABLED_CUSTOMSTEREO := true
AUDIO_FEATURE_ENABLED_FLUENCE := true
AUDIO_FEATURE_ENABLED_HDMI_EDID := true
AUDIO_FEATURE_ENABLED_HDMI_PASSTHROUGH := true
AUDIO_FEATURE_ENABLED_DISPLAY_PORT := true
AUDIO_FEATURE_ENABLED_HFP := true
AUDIO_FEATURE_ENABLED_MULTI_VOICE_SESSIONS := true
AUDIO_FEATURE_ENABLED_KPI_OPTIMIZE := true
AUDIO_FEATURE_ENABLED_SPKR_PROTECTION := true
AUDIO_FEATURE_ENABLED_ACDB_LICENSE := true
AUDIO_FEATURE_ENABLED_SOURCE_TRACKING := true
AUDIO_FEATURE_ENABLED_GEF_SUPPORT := true
AUDIO_FEATURE_ENABLED_RAS := true

AUDIO_USE_LL_AS_PRIMARY_OUTPUT := true
USE_CUSTOM_AUDIO_POLICY := 1
USE_XML_AUDIO_POLICY_CONF := 1

# ---------------------------------------------------------------------------
# Bluetooth
# ---------------------------------------------------------------------------
BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR := $(DEVICE_PATH)/bluetooth
BOARD_HAVE_BLUETOOTH_QCOM := true

# ---------------------------------------------------------------------------
# Camera
#   本機 sensor：IMX362（主）/ IMX351（望遠）/ IMX319（前），另有 depth_map + bokeh
# ---------------------------------------------------------------------------
TARGET_USES_MEDIA_EXTENSIONS := true
TARGET_USES_QTI_CAMERA_DEVICE := true
USE_DEVICE_SPECIFIC_CAMERA := true

# ---------------------------------------------------------------------------
# Display
#   面板：Raydium RM67198 1080p command mode（單 DSI），6.0" AMOLED 1080x2160
#   不設的話 vendor/lineage/bootanimation 會退回預設的 1080x1920，開機動畫比例會錯
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Shim 函式庫
#
# LineageOS 在 bionic linker 裡加的機制（linker.cpp 的 parse_LD_SHIM_LIBS）：
# 格式是「目標函式庫的實際路徑|要順便載入的 shim」，用空白或冒號分隔。
# 載入目標函式庫時，shim 會被放進同一個符號查找群組。
#
# 為什麼需要：/vendor/bin/gxFpDaemon（指紋 daemon，也是 Home 鍵的來源）與
# fingerprint.gx52*.so 都連 libkeymaster1.so —— 那是 Oreo blob（AOSP 9 沒這個模組），
# 它要的 keymaster::copy_size_and_data_from_buf 在 Pie 的 libkeymaster_messages.so
# 裡 mangled name 變了（UniquePtr/DefaultDelete 搬進了 keymaster 命名空間），
# 函式本身與 ABI 完全相同。詳見 libshims/keymaster_compat.cpp 的檔頭。
#
# 掛在 libkeymaster1.so 上而不是 gxFpDaemon 上：缺符號的是它，
# 而且這樣只有真的用到它的行程會被影響。
# ---------------------------------------------------------------------------
TARGET_LD_SHIM_LIBS := \
    /system/lib/libkeymaster1.so|libshim_keymaster.so \
    /system/lib64/libkeymaster1.so|libshim_keymaster.so

# 實機（第一次成功開機後 dumpsys display）回報：
#   DisplayDeviceInfo{"Built-in Screen": 1080 x 1920, 60.000004 fps, density 480,
#                     403.411 x 403.041 dpi}
# 原本寫 2160 是我照 18:9 機型猜的 —— ZS551KL 是 5.5 吋 Full HD（16:9），不是全螢幕。
TARGET_SCREEN_WIDTH := 1080
TARGET_SCREEN_HEIGHT := 1920

TARGET_FORCE_HWC_FOR_VIRTUAL_DISPLAYS := true
TARGET_USES_GRALLOC1 := true
TARGET_USES_HWC2 := true
TARGET_USES_ION := true

MAX_EGL_CACHE_KEY_SIZE := 12*1024
MAX_EGL_CACHE_SIZE := 2048*1024
MAX_VIRTUAL_DISPLAY_DIMENSION := 4096

OVERRIDE_RS_DRIVER := libRSDriver_adreno.so

VSYNC_EVENT_PHASE_OFFSET_NS := 2000000
SF_VSYNC_EVENT_PHASE_OFFSET_NS := 6000000

# ---------------------------------------------------------------------------
# DRM
# ---------------------------------------------------------------------------
TARGET_ENABLE_MEDIADRM_64 := true

# ---------------------------------------------------------------------------
# Filesystem
# ---------------------------------------------------------------------------
TARGET_FS_CONFIG_GEN := $(DEVICE_PATH)/config.fs

# ---------------------------------------------------------------------------
# GPS
# ---------------------------------------------------------------------------
USE_DEVICE_SPECIFIC_GPS := true
BOARD_VENDOR_QCOM_LOC_PDK_FEATURE_SET := true

# ---------------------------------------------------------------------------
# HIDL
# ---------------------------------------------------------------------------
DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml
DEVICE_MATRIX_FILE := $(DEVICE_PATH)/compatibility_matrix.xml

# ---------------------------------------------------------------------------
# QCOM
# ---------------------------------------------------------------------------
BOARD_USES_QCOM_HARDWARE := true

# ---------------------------------------------------------------------------
# Recovery
# ---------------------------------------------------------------------------
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.qcom
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
TARGET_RECOVERY_UI_BLANK_UNBLANK_ON_INIT := true

# ---------------------------------------------------------------------------
# RIL
# ---------------------------------------------------------------------------
TARGET_RIL_VARIANT := caf
TARGET_USES_OLD_MNC_FORMAT := true

# ---------------------------------------------------------------------------
# Security patch level
#   原廠 boot.img 的 os_patch_level 是 2019-11（最後一版官方韌體 15.0410.1911.117）
# ---------------------------------------------------------------------------
VENDOR_SECURITY_PATCH := 2019-11-01

# ---------------------------------------------------------------------------
# SELinux
#   先跑 permissive 開機，確認起得來之後再轉 enforcing
# ---------------------------------------------------------------------------
include device/qcom/sepolicy/sepolicy.mk
BOARD_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor
BOARD_PLAT_PUBLIC_SEPOLICY_DIR += $(DEVICE_PATH)/sepolicy/public
BOARD_PLAT_PRIVATE_SEPOLICY_DIR += $(DEVICE_PATH)/sepolicy/private

# ---------------------------------------------------------------------------
# Wifi
#   qcacld；注意 ASUS 的 GPL kernel 原始碼「不含」qcacld 驅動，
#   要從 CAF（LA.UM.6.4 / msm8998）或其他 msm8998 裝置 kernel 補進 kernel/asus/msm8998
# ---------------------------------------------------------------------------
BOARD_HAS_QCOM_WLAN := true
BOARD_HAS_QCOM_WLAN_SDK := true
BOARD_WLAN_DEVICE := qcwcn

# 驅動是編進 kernel 的（CONFIG_QCA_CLD_WLAN=y），不是模組，所以 HAL 不能用
# insmod 啟動它 —— 改成寫這個 sysfs 節點觸發。
# 之所以編成 built-in：原廠的 qca_cld3_wlan.ko 因為 modversions CRC 對不上
# 我們自編的 kernel 而不能用（見 tools/71_ko_crc_check.py），必須自己編；
# 而編成 built-in 可以完全繞過 CONFIG_MODULE_SIG_FORCE=y 的簽章檢查。
# LineageOS 的 OnePlus msm8998（同平台同版本）也是這樣設的。
WIFI_DRIVER_STATE_CTRL_PARAM := "/sys/kernel/boot_wlan/boot_wlan"
WIFI_DRIVER_STATE_OFF := 0
WIFI_DRIVER_STATE_ON := 1
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_WPA_SUPPLICANT_PRIVATE_LIB := lib_driver_cmd_$(BOARD_WLAN_DEVICE)
BOARD_HOSTAPD_DRIVER := NL80211
BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_$(BOARD_WLAN_DEVICE)
HOSTAPD_VERSION := VER_0_8_X
WPA_SUPPLICANT_VERSION := VER_0_8_X
WIFI_DRIVER_FW_PATH_AP := "ap"
WIFI_DRIVER_FW_PATH_STA := "sta"
WIFI_DRIVER_FW_PATH_P2P := "p2p"
WIFI_DRIVER_OPERSTATE_PATH := "/sys/class/net/wlan0/operstate"
WIFI_HIDL_FEATURE_DUAL_INTERFACE := true

# ---------------------------------------------------------------------------
# Assert —— 刻意不設
#
# 設了的話 updater-script 會產生：
#   assert(getprop("ro.product.device") == "Z01G" || getprop("ro.build.product") == ...)
# 但這台的 TWRP（3.7.0_9-0；更早的 3.2.1 也一樣）**沒有設 ro.product.device，
# 也沒有 ro.build.product**（只有 ro.omni.device=Z01G 與
# ro.product.name=omni_Z01G），兩個都回空字串 -> 斷言必定失敗：
#   abort("E3004: This package is for device: ...; this device is .")
#   -> TWRP 顯示 "updater process ended with ERROR: 7"
# 實測與 /system 在不在無關：system 完好時照樣失敗。
#
# TARGET_OTA_ASSERT_DEVICE 只能改比對的名稱，改不了比對哪些屬性，
# 所以在這裡解決不了。改由 tools/28_widen_device_assert.sh 在編好之後
# 把那一行換成也認 ro.omni.device / ro.product.name 的版本 ——
# 仍然擋得住別的機型（實測名稱寫錯時照樣 E3004）。
# TARGET_OTA_ASSERT_DEVICE := Z01G,Z01GD,ASUS_Z01GD,ASUS_Z01GD_1,ZS551KL

# ---------------------------------------------------------------------------
# Inherit from proprietary files（由 setup-makefiles.sh 產生）
# ---------------------------------------------------------------------------
-include vendor/asus/Z01G/BoardConfigVendor.mk
