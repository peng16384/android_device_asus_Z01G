#
# Copyright (C) 2017-2023 The LineageOS Project
# Copyright (C) 2026 ZS551KL port
#
# SPDX-License-Identifier: Apache-2.0
#
# ASUS ZenFone 4 Pro（ZS551KL / Z01G），LineageOS 22.2。
# 骨架：OnePlus msm8998-common 的 BoardConfigCommon.mk（見 ORIGIN.md）+ dumpling 的 BoardConfig.mk，
# 值換成 ZS551KL 的（16.0 的 BoardConfig.mk）。
#

DEVICE_PATH := device/asus/Z01G

# Architecture
TARGET_BOOTLOADER_BOARD_NAME := msm8998
TARGET_NO_BOOTLOADER := true
TARGET_BOARD_PLATFORM := msm8998

TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a73

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a73

# Kernel
# cmdline：原廠 boot header 的那份（其餘由 bootloader 追加，見 CLAUDE.md）。
# ⚠ bring-up 期間 permissive；穩定後拿掉（16.0 的做法）。
#
# ⚠⚠ ASUS 的 ABL 組出來的最終 cmdline 上限 1024 bytes（實測 2026-09-25）。ABL 會在 header 的
#    cmdline 後面再附加約 600 bytes（dm= verity、panel、androidboot.id.*、bootcount…），
#    超過就停在「Powered by android」，約一兩分鐘後自己退回 fastboot / recovery —— 看起來完全像
#    kernel 開不起來。header 的 cmdline 必須 ≤ 400 bytes（tools/135 會檢查）。
#    實測：header 392 -> 能開；429 / 452 -> 卡住；380 -> 能開。
#    因此拿掉 earlycon（只有接 UART 才有用；console=ttyMSM0 仍在）與 loop.max_part（OnePlus 帶來的）
BOARD_KERNEL_CMDLINE := console=ttyMSM0,115200,n8 androidboot.console=ttyMSM0
BOARD_KERNEL_CMDLINE += androidboot.hardware=qcom
BOARD_KERNEL_CMDLINE += user_debug=31 msm_rtb.filter=0x37 ehci-hcd.park=3
BOARD_KERNEL_CMDLINE += lpm_levels.sleep_disabled=1 sched_enable_hmp=1
BOARD_KERNEL_CMDLINE += sched_enable_power_aware=1 service_locator.enable=1
BOARD_KERNEL_CMDLINE += swiotlb=2048 androidboot.configfs=true
BOARD_KERNEL_CMDLINE += androidboot.usbcontroller=a800000.dwc3
# first stage init 只為 boot device 建 /dev/block/by-name（fs_mgr GetBootDevices()）。
# bootloader 只給 androidboot.bootdevice=1da4000.ufshc（沒有底線、不是 boot_devices），要自己補
BOARD_KERNEL_CMDLINE += androidboot.boot_devices=soc/1da4000.ufshc
# （2026-09-26 起 enforcing；permissive 版的 boot.img 見 tools/139）
# header v0、base 0：與原廠逐欄一致（16.0 移植時拆原廠 boot 驗證過；shakalaca 的 Z01G 樹也相同）
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb
BOARD_MKBOOTIMG_ARGS := --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 --second_offset 0x00f00000
# kernel：4.4.302 + ASUS 驅動（z01g 分支）。正式設定，不含 16.0 測試平台的 qtaguid 等
TARGET_KERNEL_SOURCE := kernel/asus/msm8998
TARGET_KERNEL_CONFIG := z01g_defconfig
# kernel 模組（=m 的：wil6210、DVB、rdbg、test-iosched…，都用不到）裝到 /system/lib/modules。
# 不設的話走 vendor/lineage/build/tasks/kernel.mk 的「No vendor partition」分支：模組裝在 system/vendor/lib/modules，
# 寫進 system 的 file_list 卻是 lib/modules/*.ko（少了 vendor/）-> build_image FileNotFoundError（Lineage 的 bug）
NEED_KERNEL_MODULE_SYSTEM := true

# Platform
BOARD_USES_QCOM_HARDWARE := true

# ANT+
BOARD_ANT_WIRELESS_DEVICE := "qualcomm-hidl"

# Audio
AUDIO_FEATURE_ENABLED_EXTENDED_COMPRESS_FORMAT := true
BOARD_SUPPORTS_SOUND_TRIGGER := true
BOARD_USES_ALSA_AUDIO := true

# Display（原廠 ro.sf.lcd_density=480；OnePlus 5T 是 420）
TARGET_SCREEN_DENSITY := 480

# Filesystem
TARGET_FS_CONFIG_GEN += $(DEVICE_PATH)/config.fs

# HIDL
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE := \
    $(DEVICE_PATH)/framework_compatibility_matrix.xml \
    hardware/qcom-caf/common/vendor_framework_compatibility_matrix.xml \
    hardware/qcom-caf/common/vendor_framework_compatibility_matrix_legacy.xml \
    vendor/lineage/config/device_framework_matrix.xml
DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml
DEVICE_MATRIX_FILE := hardware/qcom-caf/common/compatibility_matrix.xml

# Memory
TARGET_USES_ION := true

# A-only（沒有 _a/_b）。⚠ Android 15 的 build/make/core/board_config.mk:945 在沒設時**預設 true**，
# 不設就會走 A/B 的 OTA 流程（ota_from_target_files: META/ab_partitions.txt is required for ab_update）
# 而且 ro.build.ab_update=true 會誤導 updater / recovery
AB_OTA_UPDATER := false

# Partitions
# 分割表不動（CLAUDE.md 安全規則）：沒有 vendor 分割區 -> vendor 放在 system 裡（與 16.0 相同）。
# 大小取自 /proc/partitions 與 fastboot getvar（CLAUDE.md「分割表」一節）。
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_CACHEIMAGE_PARTITION_SIZE := 134217728
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 5368709120
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_FLASH_BLOCK_SIZE := 262144
TARGET_COPY_OUT_VENDOR := system/vendor
# persist 掛在 /mnt/vendor/persist（22.2 的慣例，device/qcom/sepolicy-legacy-um 依此標記），
# 再 bind mount 到 /persist（init.target.rc 的 on fs）。/persist 不能是 symlink：ASUS 的 sensors.qcom 開
# /persist/sensors/sns.reg 前會 realpath 檢查，解析成 /mnt/vendor/persist/... 就判「invalid directory path」、
# 不提供感測器註冊表 -> SLPI 的 SMGR 起不來 -> 加速度計 / 陀螺儀 / 磁力計全沒有（2026-09-26）
BOARD_ROOT_EXTRA_FOLDERS += persist
# ASUS 的 Oreo blob 用舊路徑：keymaster（keystore.msm8998.so）/ 指紋 / HDCP 從 /firmware/image 載 TZ app，
# wcnss_filter 讀 /bt_firmware。fstab 掛在 Treble 路徑（sepolicy-legacy-um 依此標記），這裡接過去
BOARD_ROOT_EXTRA_SYMLINKS += /vendor/firmware_mnt:/firmware /vendor/bt_firmware:/bt_firmware /vendor/dsp:/dsp
# ASUS 的 /asusfw（音訊校正、功放韌體、OIS 韌體）；掛載點必須在 root 就存在
# （contextmount_type，init 不准建 —— 16.0 的 SELinux 教訓 5）
BOARD_ROOT_EXTRA_FOLDERS += asusfw
# /factory：SSN（USB 序號，見 init.qcom.usb.rc）
BOARD_ROOT_EXTRA_FOLDERS += factory

# Properties
TARGET_SYSTEM_EXT_PROP += $(DEVICE_PATH)/system_ext.prop
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# Recovery
TARGET_RECOVERY_DEVICE_DIRS := $(DEVICE_PATH)
# recovery（與 OTA 的 updater-script）用 bootdevice 路徑；原因見 recovery.fstab 開頭
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/recovery.fstab
TARGET_USERIMAGES_USE_EXT4 := true

# Releasetools
# OnePlus 的 releasetools 會刷 OnePlus 的韌體分割 —— 這台絕不能（CLAUDE.md 安全規則 1）
TARGET_OTA_ASSERT_DEVICE := Z01G,Z01GD,ASUS_Z01GD_1,ZS551KL

# RIL
ENABLE_VENDOR_RIL_SERVICE := true

# Security patch level（ASUS 最後一版的 vendor）
VENDOR_SECURITY_PATCH := 2019-11-01

# SELinux
include device/lineage/sepolicy/libperfmgr/sepolicy.mk
include device/qcom/sepolicy-legacy-um/SEPolicy.mk
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor
PRODUCT_PRIVATE_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/private
PRODUCT_PUBLIC_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/public

# Treble
# **不開 Full Treble**（bring-up 筆記的「架構決定」）：vendor 在 system 裡；ASUS 的 Oreo blob
# 會直接連 system 的程式庫。ro.treble.enabled != true 時 linkerconfig 用 legacy 設定
# （system/linkerconfig/main.cc:283），所有程式庫在同一個 namespace。
# ⚠ 不要設 PRODUCT_FULL_TREBLE_OVERRIDE（OnePlus 設 true，因為它有 vendor 分割區）。

# Verified Boot
BOARD_AVB_ENABLE := false

# Wi-Fi
BOARD_WLAN_DEVICE := qcwcn
BOARD_HOSTAPD_DRIVER := NL80211
BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_$(BOARD_WLAN_DEVICE)
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_WPA_SUPPLICANT_PRIVATE_LIB := lib_driver_cmd_$(BOARD_WLAN_DEVICE)
WIFI_HIDL_FEATURE_DUAL_INTERFACE := true
WIFI_HIDL_UNIFIED_SUPPLICANT_SERVICE_RC_ENTRY := true
WPA_SUPPLICANT_VERSION := VER_0_8_X
# 新 qcacld 用 /dev/wlan 寫 ON / OFF（16.0 是 /sys/kernel/boot_wlan/boot_wlan，
# 那個節點只在 16.0 測試平台的 kernel 設定才有 —— kernel 的 215b60d5）
WIFI_DRIVER_STATE_CTRL_PARAM := "/dev/wlan"
WIFI_DRIVER_STATE_ON := "ON"
WIFI_DRIVER_STATE_OFF := "OFF"

# Inherit the proprietary files（ASUS + 借 OnePlus 的兩個模組）
include vendor/asus/Z01G/BoardConfigVendor.mk
-include vendor/asus/Z01G-oneplus/BoardConfigVendor.mk
