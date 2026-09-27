#
# Copyright (C) 2017-2023 The LineageOS Project
# Copyright (C) 2026 ZS551KL port
#
# SPDX-License-Identifier: Apache-2.0
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

$(call inherit-product, device/asus/Z01G/device.mk)

$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_NAME := lineage_Z01G
PRODUCT_DEVICE := Z01G
PRODUCT_MANUFACTURER := asus
PRODUCT_BRAND := asus
PRODUCT_MODEL := ASUS_Z01GD

PRODUCT_GMS_CLIENTID_BASE := android-asus

# 原廠最後一版（1911.117）的 fingerprint / description —— 與 16.0 相同
#
# ⚠⚠ 不要設 DeviceName / SystemDevice（OnePlus 範本有）。22.2 的 gen_build_prop.py 用 DeviceName
#    產生 ro.build.product，而 ASUS 的 blob 拿 ro.build.product 做兩件事：
#    - gxfingerprint.default.so 的 gx_ta_start() 把它 property_get 進**8 bytes 的堆疊緩衝區**
#      （原廠值 ZS551KL 剛好 7 字 + NUL）。設成 ASUS_Z01GD_1 -> 蓋掉 stack canary ->
#      gxFpDaemon 每次啟動都 "stack corruption detected"（2026-09-25，19 個 tombstone）
#    - libacdbloader.so 用它當 ACDB 目錄名（我們裝了 Z01G 與 ZS551KL 兩份，沒有 ASUS_Z01GD_1）
#    不設的話 = TARGET_DEVICE = Z01G，與 16.0 相同（兩者都實測可用）
PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="WW_Phone-user 8.0.0 OPR1.170623.032 15.0410.1911.117-0 release-keys" \
    BuildFingerprint=asus/WW_Phone/ASUS_Z01GD_1:8.0.0/OPR1.170623.032/15.0410.1911.117-0:user/release-keys \
    DeviceProduct=WW_Phone \
    SystemName=WW_Phone

TARGET_VENDOR := asus

# Evolution X（vic）用的旗標 —— LineageOS 不讀這些變數，同一棵 device tree 兩邊共用。
# 螢幕尺寸給開機動畫用（1080x1920 也是 Evolution X 的預設，寫明免得將來預設改了）。
# GApps：預設 WITH_GMS=true（完整版）；system 分割只有 5 GB，放不下時改 TARGET_USES_MINI_GAPPS / _PICO_GAPPS
EVO_BUILD_TYPE := Unofficial
TARGET_SCREEN_HEIGHT := 1920
TARGET_SCREEN_WIDTH := 1080
