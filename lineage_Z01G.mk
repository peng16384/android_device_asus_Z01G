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

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from Z01G device
$(call inherit-product, device/asus/Z01G/device.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_NAME := lineage_Z01G
PRODUCT_DEVICE := Z01G
PRODUCT_BRAND := asus
PRODUCT_MODEL := ASUS_Z01GD
PRODUCT_MANUFACTURER := asus

PRODUCT_GMS_CLIENTID_BASE := android-asus

# 注意：build.prop 寫的是 WW_Phone，執行期 getprop 是 WW_Z01GD（ASUS runtime 覆寫）。
# 這裡先跟 build.prop 一致。
PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="WW_Phone-user 8.0.0 OPR1.170623.032 15.0410.1911.117-0 release-keys"

BUILD_FINGERPRINT := asus/WW_Phone/ASUS_Z01GD_1:8.0.0/OPR1.170623.032/15.0410.1911.117-0:user/release-keys
